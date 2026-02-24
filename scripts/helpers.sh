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
resolve_runtime_dir() {
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        printf '%s/muxscribe' "$XDG_RUNTIME_DIR"
    else
        printf '/tmp/muxscribe-%s' "$(id -u)"
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

# Check if muxscribe is currently recording
is_recording() {
    local state
    state=$(get_tmux_option "$MUXSCRIBE_OPT_RECORDING" "off")
    [[ "$state" == "on" ]]
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
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    printf '%s/event-queue' "$runtime_dir"
}

# Resolve the AI session ID file (stores claude --resume session ID)
resolve_ai_session_id_file() {
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    printf '%s/ai-session-id' "$runtime_dir"
}

# Resolve the summarizer daemon PID file
resolve_ai_pid_file() {
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    printf '%s/summarizer.pid' "$runtime_dir"
}

# Resolve the summarizer lock file (prevents concurrent claude calls)
resolve_ai_lock_file() {
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    printf '%s/summarizer.lock' "$runtime_dir"
}

# Check if AI summarization is enabled
is_ai_enabled() {
    local state
    state=$(get_tmux_option "$MUXSCRIBE_OPT_AI" "$MUXSCRIBE_DEFAULT_AI")
    [[ "$state" == "on" ]]
}
