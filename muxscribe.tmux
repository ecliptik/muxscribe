#!/usr/bin/env bash
# muxscribe — tmux session recorder
# TPM entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/variables.sh"
source "$CURRENT_DIR/scripts/helpers.sh"

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

main() {
    set_keybindings
}

main
