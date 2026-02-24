#!/usr/bin/env bash
# muxscribe — tmux session recorder
# TPM entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/variables.sh"
source "$CURRENT_DIR/scripts/helpers.sh"

# Clean up stale state from a previous crash or unclean exit
cleanup_stale_state() {
    local has_active_recording=false

    # Check all live sessions for active recording state
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null) || return 0
    while IFS= read -r sess; do
        if is_session_recording "$sess"; then
            has_active_recording=true
            break
        fi
    done <<< "$sessions"

    # If no session is actively recording but hooks are still registered, clean up
    if ! "$has_active_recording"; then
        # Check if our hooks are still present
        if tmux show-hooks -g 2>/dev/null | grep -q "\[${MUXSCRIBE_HOOK_INDEX}\]"; then
            "$CURRENT_DIR/scripts/hooks.sh" unregister
        fi

        # Clean up stale PID files and lock files in runtime dirs
        local base_runtime_dir
        base_runtime_dir=$(resolve_runtime_dir)
        if [[ -d "$base_runtime_dir" ]]; then
            # Clean stale PID files (where the process is no longer running)
            local pid_file
            while IFS= read -r pid_file; do
                [[ -f "$pid_file" ]] || continue
                local pid
                pid=$(cat "$pid_file" 2>/dev/null)
                if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                    rm -f "$pid_file"
                fi
            done < <(find "$base_runtime_dir" -name 'summarizer.pid' 2>/dev/null)

            # Clean stale lock files
            find "$base_runtime_dir" -name '*.lock' -delete 2>/dev/null
            find "$base_runtime_dir" -name '*.lockdir' -type d -delete 2>/dev/null
        fi

        # Clear stale recording options from sessions
        while IFS= read -r sess; do
            local state
            state=$(tmux show-option -t "$sess" -qv "$MUXSCRIBE_OPT_RECORDING" 2>/dev/null)
            if [[ "$state" == "on" ]]; then
                set_session_option "$sess" "$MUXSCRIBE_OPT_RECORDING" "off"
                set_session_option "$sess" "$MUXSCRIBE_OPT_STATUS" ""
            fi
        done <<< "$sessions"
    fi
}

set_keybindings() {
    local toggle_key
    toggle_key=$(get_tmux_option "$MUXSCRIBE_OPT_KEY" "$MUXSCRIBE_DEFAULT_KEY")

    local status_key
    status_key=$(get_tmux_option "$MUXSCRIBE_OPT_STATUS_KEY" "$MUXSCRIBE_DEFAULT_STATUS_KEY")

    # prefix + M → toggle recording
    if [[ "$toggle_key" != "off" ]]; then
        tmux bind-key "$toggle_key" run-shell "$CURRENT_DIR/scripts/toggle.sh toggle"
    fi

    # prefix + Alt-m → show status
    if [[ "$status_key" != "off" ]]; then
        tmux bind-key "$status_key" run-shell "$CURRENT_DIR/scripts/toggle.sh status"
    fi
}

init_status() {
    # Initialize global status option to empty so format strings don't show literal text
    set_tmux_option "$MUXSCRIBE_OPT_STATUS" ""
}

main() {
    init_status
    cleanup_stale_state
    set_keybindings
}

main
