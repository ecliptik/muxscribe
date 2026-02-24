# CLAUDE.md — muxscribe project conventions

## Project

muxscribe is a pure-Bash tmux plugin that records session activity to structured markdown logs. It uses TPM (Tmux Plugin Manager) for installation.

## Structure

```
muxscribe.tmux         — TPM entry point (registers keybindings)
scripts/
  variables.sh         — option names, defaults, constants
  helpers.sh           — utility functions (get_tmux_option, path resolution)
  toggle.sh            — start/stop recording (keybinding handler)
  hooks.sh             — register/unregister tmux hooks
  capture.sh           — snapshot pane content on events
  writer.sh            — format events as markdown and write to log files
  summarizer.sh        — AI summarizer daemon (polls event queue, feeds claude CLI)
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
- **XDG**: Logs go to `$XDG_STATE_HOME/muxscribe/`, config to `$XDG_CONFIG_HOME/muxscribe/`
- **Testing**: Test by running scripts directly: `bash scripts/toggle.sh start`

## Commands

- Load plugin: `bash muxscribe.tmux`
- Start recording: `bash scripts/toggle.sh start`
- Stop recording: `bash scripts/toggle.sh stop`
- Check status: `bash scripts/toggle.sh status`
- View hooks: `tmux show-hooks -g | grep '\[100\]'`
- View log: `cat ~/.local/state/muxscribe/<session>/$(date +%Y-%m-%d).md`
- View AI summary: `cat ~/.local/state/muxscribe/<session>/summary-$(date +%Y-%m-%d).md`
- Start summarizer manually: `bash scripts/summarizer.sh start <session>`
- Stop summarizer manually: `bash scripts/summarizer.sh stop <session>`
- Flush pending events: `bash scripts/summarizer.sh flush <session>`

## Key design decisions

- Every tmux hook event triggers a full pane snapshot (debounced for high-frequency events)
- High-frequency events (`after-send-keys`, `after-select-pane`, `after-resize-pane`) are debounced with a configurable interval (default 5s)
- Output is daily-rotated markdown files with YAML frontmatter for Obsidian compatibility
- Manual toggle only — no auto-start (user presses `prefix + M`)
- AI summarization uses a background daemon that polls an event queue and calls `claude` CLI with `--resume` for conversation continuity
- `CLAUDECODE` env var must be unset before spawning `claude` CLI from within a Claude Code session
- Event queue uses condensed one-line-per-event format to minimize token usage
