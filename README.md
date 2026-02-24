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
- **AI summarization** — optional real-time log summarization via Claude CLI

## Requirements

- tmux 3.2+ (tested on 3.5a)
- [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) (optional, for AI summarization)

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

# Enable AI summarization (default: off, requires claude CLI)
set -g @muxscribe-ai 'on'

# Model for AI summarization (default: sonnet)
set -g @muxscribe-ai-model 'haiku'

# Batch interval in seconds for AI processing (default: 10)
set -g @muxscribe-ai-interval '10'
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

## AI Summarization

When enabled, muxscribe runs a background daemon that feeds terminal events to Claude CLI in batches. Claude maintains a concise development log summary alongside the raw event logs.

The summary file is written to `$XDG_STATE_HOME/muxscribe/<session>/summary-YYYY-MM-DD.md` and uses the same YAML frontmatter format for Obsidian compatibility.

**How it works:**
1. Each captured event appends a condensed one-line description to an event queue
2. A background daemon polls the queue every N seconds (configurable)
3. Batched events are sent to `claude` CLI with `--resume` to maintain conversation context
4. Claude reads and updates the summary file after each batch

**Requirements:** The `claude` CLI must be installed and authenticated. AI summarization is opt-in — set `@muxscribe-ai on` in your `.tmux.conf`.

### Quickstart

1. Install the [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) and authenticate:

   ```bash
   claude  # follow the login prompts
   ```

2. Enable AI summarization in `~/.tmux.conf`:

   ```tmux
   set -g @muxscribe-ai 'on'
   ```

3. Reload tmux config and start recording:

   ```
   prefix + I        # install/reload plugins
   prefix + M        # start recording
   ```

4. Work in your terminal as usual. The summarizer daemon polls events every 10 seconds and streams updates to a summary file.

5. View the live summary:

   ```bash
   # tail the summary as Claude updates it
   tail -f ~/.local/state/muxscribe/<session>/summary-$(date +%Y-%m-%d).md
   ```

6. Stop recording when done:

   ```
   prefix + M        # stop recording (flushes remaining events to Claude)
   ```

You can tune the behavior with these options:

```tmux
set -g @muxscribe-ai-model 'haiku'    # faster/cheaper model (default: sonnet)
set -g @muxscribe-ai-interval '30'    # poll less frequently (default: 10s)
```

To manually flush pending events or control the daemon:

```bash
bash scripts/summarizer.sh flush <session>   # process queued events now
bash scripts/summarizer.sh stop <session>    # stop the daemon
```

## License

MIT
