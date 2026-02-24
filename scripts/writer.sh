#!/usr/bin/env bash
# muxscribe — markdown log writer

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

# Human-readable descriptions for event types
event_description() {
    local event_type="$1"
    case "$event_type" in
        session-start)         echo "Recording started" ;;
        session-closed)        echo "Session closed" ;;
        after-new-window)      echo "New window created" ;;
        after-split-window)    echo "Pane split" ;;
        after-kill-pane)       echo "Pane closed" ;;
        after-rename-window)   echo "Window renamed" ;;
        after-rename-session)  echo "Session renamed" ;;
        after-select-window)   echo "Switched window" ;;
        after-select-pane)     echo "Switched pane" ;;
        session-window-changed) echo "Window changed" ;;
        after-resize-pane)     echo "Pane resized" ;;
        after-resize-window)   echo "Window resized" ;;
        after-select-layout)   echo "Layout changed" ;;
        after-copy-mode)       echo "Copy mode toggled" ;;
        after-send-keys)       echo "Activity snapshot" ;;
        pane-exited)           echo "Pane process exited" ;;
        *)                     echo "$event_type" ;;
    esac
}

# Write YAML frontmatter and file header for a new day's log
write_header() {
    local session_name="$1"
    local log_file="$2"
    local date_str
    date_str=$(date '+%Y-%m-%d')
    local started
    started=$(timestamp_iso)
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")

    cat >> "$log_file" <<EOF
---
session: $session_name
date: $date_str
started: "$started"
host: $hostname
tags: [muxscribe, dev-log]
---

# Session: $session_name — $date_str

EOF
}

# Initialize a new recording session
init_session() {
    local session_name="$1"
    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    ensure_dir "$session_dir"

    local log_file
    log_file=$(resolve_log_file "$session_name")

    # Only write header if the file doesn't exist yet
    if [[ ! -f "$log_file" ]]; then
        write_header "$session_name" "$log_file"
    fi
}

# Write a session close marker
close_session() {
    local session_name="$1"
    local log_file
    log_file=$(resolve_log_file "$session_name")

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(timestamp_time)

    cat >> "$log_file" <<EOF

---

## $timestamp — recording-stopped

Recording stopped.

EOF
}

# Append an event entry from a capture event file
append_event() {
    local session_name="$1"
    local event_file="$2"

    if [[ ! -f "$event_file" ]]; then
        return 1
    fi

    local session_dir
    session_dir=$(resolve_session_log_dir "$session_name")
    ensure_dir "$session_dir"

    local log_file
    log_file=$(resolve_log_file "$session_name")

    # If the file doesn't exist (new day), write header
    if [[ ! -f "$log_file" ]]; then
        write_header "$session_name" "$log_file"
    fi

    # Parse the event file and format as markdown
    local event_type=""
    local timestamp=""
    local in_panes=false
    local current_pane_id=""
    local current_pane_idx=""
    local current_pane_cmd=""
    local current_pane_path=""
    local current_pane_active=""
    local pane_content=""
    local entry=""

    while IFS= read -r line; do
        if [[ "$line" == EVENT_TYPE=* ]]; then
            event_type="${line#EVENT_TYPE=}"
        elif [[ "$line" == TIMESTAMP=* ]]; then
            timestamp="${line#TIMESTAMP=}"
        elif [[ "$line" == "---PANES---" ]]; then
            in_panes=true
            local description
            description=$(event_description "$event_type")
            entry="---

## $timestamp — $event_type

$description

"
        elif [[ "$line" == WINDOW=* ]]; then
            local win_data="${line#WINDOW=}"
            local win_idx win_name win_active
            IFS='|' read -r win_idx win_name win_active <<< "$win_data"
            local active_marker=""
            [[ "$win_active" == "1" ]] && active_marker=" (active)"
            entry+="### Window $win_idx: $win_name$active_marker

"
        elif [[ "$line" == PANE_START=* ]]; then
            local pane_data="${line#PANE_START=}"
            IFS='|' read -r current_pane_id current_pane_idx current_pane_cmd current_pane_path current_pane_active <<< "$pane_data"
            pane_content=""
        elif [[ "$line" == PANE_END=* ]]; then
            # Trim trailing blank lines from pane content
            pane_content=$(printf '%s' "$pane_content" | awk 'NF{p=1} p' 2>/dev/null || printf '%s' "$pane_content")

            local active_marker=""
            [[ "$current_pane_active" == "1" ]] && active_marker=" *"
            entry+="**Pane $current_pane_idx**$active_marker — \`$current_pane_cmd\` in \`$current_pane_path\`
\`\`\`text
$pane_content
\`\`\`

"
            current_pane_id=""
            pane_content=""
        elif [[ -n "$current_pane_id" ]]; then
            # Accumulate pane content
            if [[ -n "$pane_content" ]]; then
                pane_content+=$'\n'"$line"
            else
                pane_content="$line"
            fi
        fi
    done < "$event_file"

    # Write the entry to the log file
    printf '%s' "$entry" >> "$log_file"
}

main() {
    local action="$1"
    local session_name="${2:-}"

    case "$action" in
        init)
            init_session "$session_name"
            ;;
        close)
            close_session "$session_name"
            ;;
        append)
            local event_file="${3:-}"
            append_event "$session_name" "$event_file"
            ;;
        *)
            echo "Usage: writer.sh [init|close|append] session_name [event_file]" >&2
            exit 1
            ;;
    esac
}

main "$@"
