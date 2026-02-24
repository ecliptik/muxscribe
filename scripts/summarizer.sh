#!/usr/bin/env bash
# muxscribe — AI summarizer daemon
# Background process that polls the event queue and feeds batches to claude CLI

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

# Start the summarizer daemon
start_daemon() {
    local session_name="$1"

    local pid_file
    pid_file=$(resolve_ai_pid_file "$session_name")

    # Check if already running
    if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            echo "summarizer already running (pid $existing_pid)" >&2
            return 1
        fi
        rm -f "$pid_file"
    fi

    # Resolve paths (per-session)
    local queue_file
    queue_file=$(resolve_event_queue "$session_name")
    local session_id_file
    session_id_file=$(resolve_ai_session_id_file "$session_name")
    local lock_file
    lock_file=$(resolve_ai_lock_file "$session_name")
    local summary_file
    summary_file=$(resolve_summary_file "$session_name")
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")

    # Ensure directories exist
    ensure_dir "$(dirname "$queue_file")"
    ensure_dir "$session_dir"

    # Read configuration
    local model
    model=$(get_tmux_option "$MUXSCRIBE_OPT_AI_MODEL" "$MUXSCRIBE_DEFAULT_AI_MODEL")
    local interval
    interval=$(get_tmux_option "$MUXSCRIBE_OPT_AI_INTERVAL" "$MUXSCRIBE_DEFAULT_AI_INTERVAL")

    # Clear any stale session ID file (first claude call will create a fresh session)
    rm -f "$session_id_file"

    # Initialize empty queue file
    : > "$queue_file"

    # Launch daemon in background
    _run_daemon "$session_name" "$session_id_file" "$model" "$interval" \
        "$queue_file" "$lock_file" "$summary_file" </dev/null >/dev/null 2>&1 &
    local daemon_pid=$!

    echo "$daemon_pid" > "$pid_file"
    disown "$daemon_pid" 2>/dev/null
}

# Stop the summarizer daemon
stop_daemon() {
    local session_name="$1"

    local pid_file
    pid_file=$(resolve_ai_pid_file "$session_name")
    local session_id_file
    session_id_file=$(resolve_ai_session_id_file "$session_name")
    local queue_file
    queue_file=$(resolve_event_queue "$session_name")
    local lock_file
    lock_file=$(resolve_ai_lock_file "$session_name")
    local summary_file
    summary_file=$(resolve_summary_file "$session_name")

    # Read config for final flush
    local model
    model=$(get_tmux_option "$MUXSCRIBE_OPT_AI_MODEL" "$MUXSCRIBE_DEFAULT_AI_MODEL")

    # Kill the daemon
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # Wait briefly for it to exit
            local i=0
            while (( i < 10 )) && kill -0 "$pid" 2>/dev/null; do
                sleep 0.1
                (( i++ ))
            done
            # Force kill if still running
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi

    # Final flush: process any remaining events
    if [[ -f "$queue_file" ]] && [[ -s "$queue_file" ]]; then
        local batch_content
        batch_content=$(cat "$queue_file")
        : > "$queue_file"

        _call_claude "$session_id_file" "$model" "$summary_file" \
            "Final events before recording stopped:\n$batch_content\n\nUpdate $summary_file with a final summary. Add a closing note that recording has ended."
    fi

    # Cleanup
    rm -f "$queue_file" "$lock_file" "$session_id_file"
}

# Flush: force-process pending events immediately
flush_queue() {
    local session_name="$1"

    local queue_file
    queue_file=$(resolve_event_queue "$session_name")
    local session_id_file
    session_id_file=$(resolve_ai_session_id_file "$session_name")
    local lock_file
    lock_file=$(resolve_ai_lock_file "$session_name")
    local summary_file
    summary_file=$(resolve_summary_file "$session_name")
    local model
    model=$(get_tmux_option "$MUXSCRIBE_OPT_AI_MODEL" "$MUXSCRIBE_DEFAULT_AI_MODEL")

    if [[ ! -f "$queue_file" ]] || [[ ! -s "$queue_file" ]]; then
        return 0
    fi

    [[ ! -f "$session_id_file" ]] && return 1

    _process_batch "$session_id_file" "$model" "$queue_file" "$lock_file" "$summary_file"
}

# Internal: main daemon loop
_run_daemon() {
    local session_name="$1"
    local session_id_file="$2"
    local model="$3"
    local interval="$4"
    local queue_file="$5"
    local lock_file="$6"
    local summary_file="$7"

    # Send initial prompt to establish context (no --resume on first call)
    _call_claude "$session_id_file" "$model" "$summary_file" \
        "Recording started for tmux session '$session_name'. I'll send you batches of terminal events. After each batch, update the summary file at $summary_file."

    # Poll loop
    while true; do
        sleep "$interval"

        # Check if this session should still be running
        if ! is_session_recording "$session_name" 2>/dev/null; then
            break
        fi

        # Re-resolve summary file in case the date changed (daily rotation)
        summary_file=$(resolve_summary_file "$session_name")

        # Process any queued events
        _process_batch "$session_id_file" "$model" "$queue_file" "$lock_file" "$summary_file"
    done
}

# Internal: read and process a batch of events from the queue
_process_batch() {
    local session_id_file="$1"
    local model="$2"
    local queue_file="$3"
    local lock_file="$4"
    local summary_file="$5"

    # Skip if queue is empty or doesn't exist
    if [[ ! -f "$queue_file" ]] || [[ ! -s "$queue_file" ]]; then
        return 0
    fi

    # Acquire lock (non-blocking)
    exec 200>"$lock_file"
    if ! flock -n 200; then
        exec 200>&-
        return 0  # Another process is handling it
    fi

    # Read and clear the queue atomically
    local batch_content
    batch_content=$(cat "$queue_file" 2>/dev/null)
    : > "$queue_file"

    exec 200>&-

    # Skip if nothing was read
    if [[ -z "$batch_content" ]]; then
        return 0
    fi

    _call_claude "$session_id_file" "$model" "$summary_file" \
        "New events:\n$batch_content\n\nUpdate $summary_file with a summary of these events."
}

# Internal: invoke claude CLI with proper environment
_call_claude() {
    local session_id_file="$1"
    local model="$2"
    local summary_file="$3"
    local prompt="$4"

    # Unset CLAUDECODE to allow spawning claude inside a Claude Code session
    (
        unset CLAUDECODE
        claude -p \
            --model "$model" \
            --allowedTools "Read,Write" \
            --permission-mode bypassPermissions \
            --append-system-prompt "You are muxscribe, a development session logger. You will receive batches of tmux terminal events. Your job is to maintain a concise, readable development log summary at $summary_file. Write in markdown with YAML frontmatter (session, date, type: summary, tags: [muxscribe, dev-log, ai-summary]). Group related events. Focus on WHAT the developer is doing (editing files, running tests, debugging) not raw terminal output. Use ## headers for major activities with time ranges, bullet points for details. Be concise — this is a dev log, not a transcript. Always read the existing file first before writing updates." \
            "$prompt" \
            >/dev/null 2>&1
    )
}

main() {
    local action="${1:-}"
    local session_name="${2:-}"

    if [[ -z "$session_name" ]]; then
        session_name=$(get_session_name 2>/dev/null || echo "")
    fi

    case "$action" in
        start)
            start_daemon "$session_name"
            ;;
        stop)
            stop_daemon "$session_name"
            ;;
        flush)
            flush_queue "$session_name"
            ;;
        *)
            echo "Usage: summarizer.sh [start|stop|flush] [session_name]" >&2
            exit 1
            ;;
    esac
}

main "$@"
