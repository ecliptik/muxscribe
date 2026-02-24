#!/usr/bin/env bash
# muxscribe — start/stop recording toggle

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

# Check if any tmux session (other than the given one) is still recording
any_other_session_recording() {
    local exclude_session="$1"
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null) || return 1
    while IFS= read -r sess; do
        [[ "$sess" == "$exclude_session" ]] && continue
        if is_session_recording "$sess"; then
            return 0
        fi
    done <<< "$sessions"
    return 1
}

start_recording() {
    local session_name
    session_name=$(get_session_name)

    # Initialize log directory and file
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    ensure_dir "$session_dir"

    # Initialize runtime directory (per-session)
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir "$session_name")
    ensure_dir "$runtime_dir"

    # Mark this session as recording (session-level option)
    set_session_option "$session_name" "$MUXSCRIBE_OPT_RECORDING" "on"

    # Set status indicator for status bar
    set_session_option "$session_name" "$MUXSCRIBE_OPT_STATUS" "● REC"

    # Register hooks (global — shared across sessions)
    "$CURRENT_DIR/hooks.sh" register "$session_name"

    # Capture initial snapshot for AI queue
    "$CURRENT_DIR/capture.sh" "session-start" "$session_name"

    # Start AI summarizer daemon if enabled
    if is_ai_enabled; then
        "$CURRENT_DIR/summarizer.sh" start "$session_name"
    fi

    display_message "recording started [$session_name]"
}

stop_recording() {
    local session_name
    session_name=$(get_session_name)

    # Stop AI summarizer daemon if enabled
    if is_ai_enabled; then
        "$CURRENT_DIR/summarizer.sh" stop "$session_name"
    fi

    # Only unregister global hooks if no other session is still recording
    if ! any_other_session_recording "$session_name"; then
        "$CURRENT_DIR/hooks.sh" unregister
    fi

    # Mark this session as not recording
    set_session_option "$session_name" "$MUXSCRIBE_OPT_RECORDING" "off"

    # Clear status indicator
    set_session_option "$session_name" "$MUXSCRIBE_OPT_STATUS" ""

    display_message "recording stopped [$session_name]"
}

show_status() {
    local session_name
    session_name=$(get_session_name)

    if is_session_recording "$session_name"; then
        local log_file
        log_file=$(resolve_log_file "$session_name")
        local size="0"
        [[ -f "$log_file" ]] && size=$(wc -c < "$log_file")
        display_message "recording [$session_name] — log: $log_file ($size bytes)"
    else
        display_message "not recording"
    fi
}

main() {
    local action="${1:-toggle}"

    case "$action" in
        toggle)
            local session_name
            session_name=$(get_session_name)
            if is_session_recording "$session_name"; then
                stop_recording
            else
                start_recording
            fi
            ;;
        start)
            local session_name
            session_name=$(get_session_name)
            if ! is_session_recording "$session_name"; then
                start_recording
            else
                display_message "already recording"
            fi
            ;;
        stop)
            local session_name
            session_name=$(get_session_name)
            if is_session_recording "$session_name"; then
                stop_recording
            else
                display_message "not recording"
            fi
            ;;
        status)
            show_status
            ;;
        *)
            display_message "unknown action: $action"
            ;;
    esac
}

main "$@"
