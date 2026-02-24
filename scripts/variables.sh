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
MUXSCRIBE_OPT_AI="@muxscribe-ai"
MUXSCRIBE_OPT_AI_MODEL="@muxscribe-ai-model"
MUXSCRIBE_OPT_AI_INTERVAL="@muxscribe-ai-interval"
MUXSCRIBE_OPT_STATUS="@muxscribe-status"
MUXSCRIBE_OPT_EXCLUDE_COMMANDS="@muxscribe-exclude-commands"

# Defaults
MUXSCRIBE_DEFAULT_KEY="M"
MUXSCRIBE_DEFAULT_STATUS_KEY="M-m"
MUXSCRIBE_DEFAULT_LOG_DIR=""  # empty = use XDG
MUXSCRIBE_DEFAULT_RECORDING="off"
MUXSCRIBE_DEFAULT_DEBOUNCE="5"
MUXSCRIBE_DEFAULT_AI="off"
MUXSCRIBE_DEFAULT_AI_MODEL="sonnet"
MUXSCRIBE_DEFAULT_AI_INTERVAL="10"
MUXSCRIBE_DEFAULT_EXCLUDE_COMMANDS="ssh,pass,gpg,sudo,su,doas,openssl,vault,ansible-vault"

# Hook array index — high number to avoid collisions with other plugins
MUXSCRIBE_HOOK_INDEX=100
