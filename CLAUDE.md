# CLAUDE.md — muxscribe project conventions

## Project

muxscribe is a pure-Bash tmux plugin that watches terminal activity and produces AI-generated session summaries via Claude CLI. It uses TPM (Tmux Plugin Manager) for installation.

## Structure

```
muxscribe.tmux         — TPM entry point (registers keybindings)
scripts/
  variables.sh         — option names, defaults, constants
  helpers.sh           — utility functions (get_tmux_option, path resolution)
  toggle.sh            — start/stop recording (keybinding handler)
  hooks.sh             — register/unregister tmux hooks
  capture.sh           — snapshot pane content, build AI event queue entries
  summarizer.sh        — AI summarizer daemon (polls event queue, feeds claude CLI)
  status.sh            — blinking status bar indicator
docs/
  ARCHITECTURE.md      — full architecture and sprint plan
  research/            — research documents on tmux, TPM, XDG
```

## Conventions

- **Language**: Pure Bash. No Python, Go, or other dependencies.
- **Shebang**: `#!/usr/bin/env bash` on all scripts
- **Executable**: All `.sh` files and `muxscribe.tmux` must have `chmod u+x`
- **Plugin dir**: Always resolve via `CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- **Options**: Named `@muxscribe-*` with hyphens (not underscores)
- **Hook index**: Use array index `[100]` to avoid conflicts with other plugins
- **XDG**: Summaries go to `$XDG_STATE_HOME/muxscribe/`, runtime to `$XDG_RUNTIME_DIR/muxscribe/`
- **Testing**: Test by running scripts directly: `bash scripts/toggle.sh start`

## Commands

- Load plugin: `bash muxscribe.tmux`
- Start recording: `bash scripts/toggle.sh start`
- Stop recording: `bash scripts/toggle.sh stop`
- Check status: `bash scripts/toggle.sh status`
- View hooks: `tmux show-hooks -g | grep '\[100\]'`
- View AI summary: `cat ~/.local/state/muxscribe/<session>/summary-$(date +%Y-%m-%d).md`
- Start summarizer manually: `bash scripts/summarizer.sh start <session>`
- Stop summarizer manually: `bash scripts/summarizer.sh stop <session>`
- Flush pending events: `bash scripts/summarizer.sh flush <session>`
- View event queue: `cat /run/user/$(id -u)/muxscribe/<session>/event-queue`

## Key design decisions

- Every tmux hook event triggers a snapshot of the active pane (debounced for high-frequency events)
- High-frequency events (`after-send-keys`, `after-select-pane`, `after-resize-pane`) are debounced with a configurable interval (default 5s)
- Event queue entries include full visible content of the active pane (active window + active pane) between `--- active pane content ---` / `--- end ---` delimiters
- Only AI summaries are produced — no raw markdown logs are written
- Output is daily-rotated summary files with YAML frontmatter for Obsidian compatibility
- Manual toggle only — no auto-start (user presses `prefix + M`)
- AI summarization uses a background daemon that polls an event queue and calls `claude` CLI with `--resume` for conversation continuity
- `CLAUDECODE` env var must be unset before spawning `claude` CLI from within a Claude Code session
