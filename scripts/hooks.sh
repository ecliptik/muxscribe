#!/usr/bin/env bash
# muxscribe — hook registration and dispatch

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/variables.sh"
source "$CURRENT_DIR/helpers.sh"

IDX="$MUXSCRIBE_HOOK_INDEX"

# Global hooks (set with -g)
GLOBAL_HOOKS=(
    # Structure events
    "after-new-window"
    "after-split-window"
    "after-kill-pane"

    # Context events
    "after-rename-window"
    "after-rename-session"

    # Navigation events
    "after-select-window"
    "after-select-pane"
    "session-window-changed"

    # Layout events
    "after-resize-pane"
    "after-resize-window"
    "after-select-layout"

    # Activity events
    "after-copy-mode"
    "after-send-keys"

    # Lifecycle events
    "session-closed"
)

# Pane-level hooks (set with -gp or -gw)
PANE_HOOKS=(
    "pane-exited"
)

register_hooks() {
    local session_name="$1"
    local capture_script="$CURRENT_DIR/capture.sh"

    for hook in "${GLOBAL_HOOKS[@]}"; do
        tmux set-hook -g "${hook}[${IDX}]" \
            "run-shell \"$capture_script '${hook}' '#{session_name}'\""
    done

    # Pane-level hooks use -gw (global window/pane scope)
    for hook in "${PANE_HOOKS[@]}"; do
        tmux set-hook -gw "${hook}[${IDX}]" \
            "run-shell \"$capture_script '${hook}' '#{session_name}'\""
    done

    # Enable focus events for pane-focus hooks
    tmux set-option -g focus-events on
}

unregister_hooks() {
    for hook in "${GLOBAL_HOOKS[@]}"; do
        tmux set-hook -gu "${hook}[${IDX}]" 2>/dev/null
    done
    for hook in "${PANE_HOOKS[@]}"; do
        tmux set-hook -guw "${hook}[${IDX}]" 2>/dev/null
    done
}

main() {
    local action="$1"
    local session_name="${2:-}"

    case "$action" in
        register)
            register_hooks "$session_name"
            ;;
        unregister)
            unregister_hooks
            ;;
        *)
            echo "Usage: hooks.sh [register|unregister] [session_name]" >&2
            exit 1
            ;;
    esac
}

main "$@"
