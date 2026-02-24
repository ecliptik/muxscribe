#!/usr/bin/env bash
# muxscribe — status bar indicator with blink effect
# Called from tmux status-right via #(path/to/status.sh)

rec=$(tmux show-option -qv "@muxscribe-recording" 2>/dev/null)
if [ "$rec" = "on" ]; then
    if [ $(( $(date +%S) % 4 )) -lt 2 ]; then
        printf '● REC'
    else
        printf '○ REC'
    fi
fi
