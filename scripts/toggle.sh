#!/usr/bin/env bash
# muxscribe — start/stop recording toggle

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

start_recording() {
    local session_name
    session_name=$(get_session_name)

    # Initialize log directory and file
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    ensure_dir "$session_dir"

    # Initialize runtime directory
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    ensure_dir "$runtime_dir"
    chmod 700 "$runtime_dir" 2>/dev/null

    # Mark as recording
    set_tmux_option "$MUXSCRIBE_OPT_RECORDING" "on"

    # Register hooks
    "$CURRENT_DIR/hooks.sh" register "$session_name"

    # Write session start and initial snapshot
    "$CURRENT_DIR/writer.sh" init "$session_name"
    "$CURRENT_DIR/capture.sh" "session-start" "$session_name"

    display_message "recording started [$session_name]"
}

stop_recording() {
    local session_name
    session_name=$(get_session_name)

    # Unregister hooks
    "$CURRENT_DIR/hooks.sh" unregister

    # Write session end marker
    "$CURRENT_DIR/writer.sh" close "$session_name"

    # Mark as not recording
    set_tmux_option "$MUXSCRIBE_OPT_RECORDING" "off"

    display_message "recording stopped [$session_name]"
}

show_status() {
    local session_name
    session_name=$(get_session_name)

    if is_recording; then
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
            if is_recording; then
                stop_recording
            else
                start_recording
            fi
            ;;
        start)
            if ! is_recording; then
                start_recording
            else
                display_message "already recording"
            fi
            ;;
        stop)
            if is_recording; then
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
