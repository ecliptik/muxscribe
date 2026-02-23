#!/usr/bin/env bash
# muxscribe — option names, defaults, and constants

# Plugin identity
MUXSCRIBE_VERSION="0.1.0"

# Option names (user-configurable via tmux set -g @option value)
MUXSCRIBE_OPT_KEY="@muxscribe-key"
MUXSCRIBE_OPT_STATUS_KEY="@muxscribe-status-key"
MUXSCRIBE_OPT_LOG_DIR="@muxscribe-log-dir"
MUXSCRIBE_OPT_RECORDING="@muxscribe-recording"
MUXSCRIBE_OPT_DEBOUNCE="@muxscribe-debounce"

# Defaults
MUXSCRIBE_DEFAULT_KEY="M"
MUXSCRIBE_DEFAULT_STATUS_KEY="M-m"
MUXSCRIBE_DEFAULT_LOG_DIR=""  # empty = use XDG
MUXSCRIBE_DEFAULT_RECORDING="off"
MUXSCRIBE_DEFAULT_DEBOUNCE="5"

# Hook array index — high number to avoid collisions with other plugins
MUXSCRIBE_HOOK_INDEX=100
