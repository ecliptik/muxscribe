#!/usr/bin/env bash
# muxscribe — helper functions

# Read a tmux option with a fallback default
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [[ -z "$option_value" ]]; then
        printf '%s' "$default_value"
    else
        printf '%s' "$option_value"
    fi
}

# Set a tmux option globally
set_tmux_option() {
    local option="$1"
    local value="$2"
    tmux set-option -gq "$option" "$value"
}

# Read a session-level tmux option with global fallback
get_session_option() {
    local session="$1"
    local option="$2"
    local default_value="$3"
    local option_value
    # Try session-level first
    option_value=$(tmux show-option -t "$session" -qv "$option" 2>/dev/null)
    if [[ -n "$option_value" ]]; then
        printf '%s' "$option_value"
        return
    fi
    # Fall back to global
    option_value=$(tmux show-option -gqv "$option" 2>/dev/null)
    if [[ -n "$option_value" ]]; then
        printf '%s' "$option_value"
        return
    fi
    printf '%s' "$default_value"
}

# Set a session-level tmux option
set_session_option() {
    local session="$1"
    local option="$2"
    local value="$3"
    tmux set-option -t "$session" -q "$option" "$value" 2>/dev/null
}

# Display a message in the tmux status line
display_message() {
    tmux display-message "muxscribe: $1"
}

# Resolve the log directory, respecting user override and XDG
resolve_log_dir() {
    local user_override
    user_override=$(get_tmux_option "$MUXSCRIBE_OPT_LOG_DIR" "")

    if [[ -n "$user_override" ]]; then
        printf '%s' "$user_override"
    else
        printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/muxscribe"
    fi
}

# Resolve the session log directory (log_dir/session_name)
resolve_session_log_dir() {
    local session_name="$1"
    local log_dir
    log_dir=$(resolve_log_dir)
    # Sanitize session name for filesystem (replace / and spaces)
    local safe_name
    safe_name=$(printf '%s' "$session_name" | tr '/ ' '__')
    printf '%s/%s' "$log_dir" "$safe_name"
}

# Resolve today's log file path for a session
resolve_log_file() {
    local session_name="$1"
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    printf '%s/%s.md' "$session_dir" "$(date +%Y-%m-%d)"
}

# Resolve the runtime directory (for PID files, lock files)
# Accepts optional session_name to create per-session subdirs
resolve_runtime_dir() {
    local session_name="${1:-}"
    local base_dir
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        base_dir="${XDG_RUNTIME_DIR}/muxscribe"
    else
        base_dir="/tmp/muxscribe-$(id -u)"
    fi
    if [[ -n "$session_name" ]]; then
        local safe_name
        safe_name=$(printf '%s' "$session_name" | tr '/ ' '__')
        printf '%s/%s' "$base_dir" "$safe_name"
    else
        printf '%s' "$base_dir"
    fi
}

# Ensure a directory exists
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# Get the current timestamp in ISO 8601 format
timestamp_iso() {
    date '+%Y-%m-%dT%H:%M:%S'
}

# Get the current time as HH:MM:SS
timestamp_time() {
    date '+%H:%M:%S'
}

# Get epoch seconds (for debounce comparisons)
timestamp_epoch() {
    date '+%s'
}

# Check if a specific session is currently recording
is_session_recording() {
    local session="$1"
    local state
    state=$(get_session_option "$session" "$MUXSCRIBE_OPT_RECORDING" "off")
    [[ "$state" == "on" ]]
}

# Check if muxscribe is currently recording (current session)
is_recording() {
    local session
    session=$(get_session_name 2>/dev/null || echo "")
    if [[ -z "$session" ]]; then
        return 1
    fi
    is_session_recording "$session"
}

# Get the session name for the current tmux client
get_session_name() {
    tmux display-message -p '#{session_name}'
}

# Resolve today's AI summary file path for a session
resolve_summary_file() {
    local session_name="$1"
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    printf '%s/summary-%s.md' "$session_dir" "$(date +%Y-%m-%d)"
}

# Resolve the event queue file for AI processing
resolve_event_queue() {
    local session_name="${1:-}"
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir "$session_name")
    printf '%s/event-queue' "$runtime_dir"
}

# Resolve the AI session ID file (stores claude --resume session ID)
resolve_ai_session_id_file() {
    local session_name="${1:-}"
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir "$session_name")
    printf '%s/ai-session-id' "$runtime_dir"
}

# Resolve the summarizer daemon PID file
resolve_ai_pid_file() {
    local session_name="${1:-}"
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir "$session_name")
    printf '%s/summarizer.pid' "$runtime_dir"
}

# Resolve the summarizer lock file (prevents concurrent claude calls)
resolve_ai_lock_file() {
    local session_name="${1:-}"
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir "$session_name")
    printf '%s/summarizer.lock' "$runtime_dir"
}

# Append to event queue with file locking (flock with fallback)
append_to_event_queue_locked() {
    local queue_file="$1"
    local content="$2"
    if command -v flock >/dev/null 2>&1; then
        (
            flock -x 201
            printf '%s\n' "$content" >> "$queue_file"
        ) 201>"${queue_file}.lock"
    else
        # macOS fallback: use a simple mkdir lock
        local lockdir="${queue_file}.lockdir"
        local tries=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            (( tries++ ))
            if (( tries > 50 )); then
                # Give up on locking, append anyway
                break
            fi
            sleep 0.05
        done
        printf '%s\n' "$content" >> "$queue_file"
        rmdir "$lockdir" 2>/dev/null
    fi
}

# Check if AI summarization is enabled
is_ai_enabled() {
    local state
    state=$(get_tmux_option "$MUXSCRIBE_OPT_AI" "$MUXSCRIBE_DEFAULT_AI")
    [[ "$state" == "on" ]]
}
