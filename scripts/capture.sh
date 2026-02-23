#!/usr/bin/env bash
# muxscribe — event capture and pane snapshot engine

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

# Debounce file — stores epoch of last capture
DEBOUNCE_FILE=""

init_debounce() {
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    ensure_dir "$runtime_dir"
    DEBOUNCE_FILE="$runtime_dir/last_capture"
}

# Check if we should skip this event due to debouncing
should_debounce() {
    local event_type="$1"

    # Only debounce high-frequency events
    case "$event_type" in
        after-send-keys|after-select-pane|after-resize-pane)
            ;;
        *)
            return 1  # don't debounce
            ;;
    esac

    local debounce_secs
    debounce_secs=$(get_tmux_option "$MUXSCRIBE_OPT_DEBOUNCE" "$MUXSCRIBE_DEFAULT_DEBOUNCE")

    if [[ -f "$DEBOUNCE_FILE" ]]; then
        local last_capture
        last_capture=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
        local now
        now=$(timestamp_epoch)
        local diff=$((now - last_capture))
        if (( diff < debounce_secs )); then
            return 0  # should debounce (skip)
        fi
    fi

    return 1  # don't debounce
}

# Update the debounce timestamp
update_debounce() {
    timestamp_epoch > "$DEBOUNCE_FILE"
}

# Capture content of a single pane
capture_pane_content() {
    local pane_id="$1"
    # -p: print to stdout, -J: join wrapped lines
    tmux capture-pane -p -J -t "$pane_id" 2>/dev/null
}

# Collect metadata for a single pane
collect_pane_metadata() {
    local pane_id="$1"
    tmux display-message -t "$pane_id" -p \
        '#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_active}|#{pane_width}x#{pane_height}' \
        2>/dev/null
}

# Snapshot all panes in a session and write to log
snapshot_session() {
    local event_type="$1"
    local session_name="$2"

    # Collect window and pane info
    local panes_data
    panes_data=$(tmux list-panes -s -t "$session_name" -F \
        '#{window_index}|#{window_name}|#{pane_id}|#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_active}|#{window_active}' \
        2>/dev/null)

    if [[ -z "$panes_data" ]]; then
        return 1
    fi

    # Build the event entry and pass to writer
    local timestamp
    timestamp=$(timestamp_time)
    local timestamp_iso
    timestamp_iso=$(timestamp_iso)

    # Create a temp file for the event data
    local runtime_dir
    runtime_dir=$(resolve_runtime_dir)
    local event_file="$runtime_dir/event_$$"

    {
        echo "EVENT_TYPE=$event_type"
        echo "TIMESTAMP=$timestamp"
        echo "TIMESTAMP_ISO=$timestamp_iso"
        echo "SESSION=$session_name"
        echo "---PANES---"

        local current_window=""
        while IFS='|' read -r win_idx win_name pane_id pane_idx pane_cmd pane_path pane_active win_active; do
            if [[ "$win_idx" != "$current_window" ]]; then
                echo "WINDOW=$win_idx|$win_name|$win_active"
                current_window="$win_idx"
            fi

            echo "PANE_START=$pane_id|$pane_idx|$pane_cmd|$pane_path|$pane_active"

            # Capture pane content (visible area only)
            capture_pane_content "$pane_id"

            echo "PANE_END=$pane_id"
        done <<< "$panes_data"
    } > "$event_file"

    # Pass to writer
    "$CURRENT_DIR/writer.sh" append "$session_name" "$event_file"

    # Cleanup
    rm -f "$event_file"
}

main() {
    local event_type="${1:-unknown}"
    local session_name="${2:-}"

    # If no session name provided, try to get it
    if [[ -z "$session_name" ]]; then
        session_name=$(get_session_name 2>/dev/null || echo "")
    fi

    # Skip if not recording
    if ! is_recording; then
        return 0
    fi

    # Skip if session name is empty (session might have closed)
    if [[ -z "$session_name" ]]; then
        return 0
    fi

    # Handle session-closed: write close marker (session may be gone soon)
    if [[ "$event_type" == "session-closed" ]]; then
        "$CURRENT_DIR/writer.sh" close "$session_name"
        return 0
    fi

    # Initialize debounce
    init_debounce

    # Check debounce
    if should_debounce "$event_type"; then
        return 0
    fi

    # Update debounce timestamp
    update_debounce

    # Snapshot the session
    snapshot_session "$event_type" "$session_name"
}

main "$@"
