# muxscribe

A tmux plugin that records session activity and writes structured markdown development logs. Designed for Obsidian import and later AI summarization into blog posts.

## Features

- **Event-driven capture** — hooks into tmux events (window creation, pane splits, navigation, etc.)
- **Full pane snapshots** — captures visible terminal content on every event
- **Structured markdown output** — YAML frontmatter, timestamped entries, code blocks
- **Daily log rotation** — one markdown file per day, organized by session
- **XDG-compliant** — logs to `$XDG_STATE_HOME/muxscribe/` by default
- **Manual toggle** — start/stop recording with a keybinding
- **Debounced** — high-frequency events (keystrokes, pane switches) are coalesced

## Requirements

- tmux 3.2+ (tested on 3.5a)
- [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)

## Installation

### With TPM

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'yourusername/muxscribe'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/yourusername/muxscribe ~/.tmux/plugins/muxscribe
```

Add to your `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/muxscribe/muxscribe.tmux
```

## Usage

| Keybinding | Action |
|---|---|
| `prefix + M` | Toggle recording on/off |
| `prefix + Alt-m` | Show recording status |

## Configuration

All options are set in `~/.tmux.conf` before the TPM run line:

```tmux
# Change toggle key (default: M)
set -g @muxscribe-key 'R'

# Change status key (default: M-m)
set -g @muxscribe-status-key 'M-r'

# Override log directory (default: $XDG_STATE_HOME/muxscribe)
set -g @muxscribe-log-dir '~/my-dev-logs'

# Debounce interval in seconds for high-frequency events (default: 5)
set -g @muxscribe-debounce '3'
```

## Output

Logs are written to `$XDG_STATE_HOME/muxscribe/<session-name>/YYYY-MM-DD.md` (defaults to `~/.local/state/muxscribe/`).

Each file has YAML frontmatter for Obsidian and timestamped entries with terminal snapshots:

```markdown
---
session: my-project
date: 2026-02-23
started: "2026-02-23T10:30:00"
host: myhost
tags: [muxscribe, dev-log]
---

# Session: my-project — 2026-02-23

## 10:30:00 — session-start

Recording started

### Window 0: editor (active)

**Pane 0** * — `nvim` in `/home/user/project`
\```text
  1  src/main.rs
  2  src/lib.rs
\```
```

## License

MIT
