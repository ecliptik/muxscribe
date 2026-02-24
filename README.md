# muxscribe

A tmux plugin that watches your terminal activity and produces AI-generated development logs via Claude CLI.

## Features

- **AI-powered summaries** — Claude reads your actual terminal content and writes structured session summaries
- **Event-driven capture** — hooks into tmux events (window switches, pane splits, keystrokes, etc.)
- **Active pane content** — captures visible terminal output so Claude knows what you're actually doing
- **Live updating** — background daemon polls every 10s, feeding batches to Claude with `--resume` for conversation continuity
- **Debounced** — high-frequency events (keystrokes, pane switches, resizes) are coalesced (default 5s)
- **Status bar indicator** — shows `● REC` in your tmux status bar when recording
- **Daily rotation** — summary files rotate at midnight
- **XDG-compliant** — summaries to `$XDG_STATE_HOME/muxscribe/`, runtime in `$XDG_RUNTIME_DIR/muxscribe/`
- **Manual toggle** — start/stop recording with `prefix + M`

## Requirements

- tmux 3.2+ (tested on 3.5a)
- [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) (must be installed and authenticated)

## Installation

### With TPM

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'yourusername/muxscribe'
set -g @muxscribe-ai 'on'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/yourusername/muxscribe ~/.tmux/plugins/muxscribe
```

Add to your `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/muxscribe/muxscribe.tmux
set -g @muxscribe-ai 'on'
```

## Usage

| Keybinding | Action |
|---|---|
| `prefix + M` | Toggle recording on/off |
| `prefix + Alt-m` | Show recording status |

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
   tail -f ~/.local/state/muxscribe/<session>/summary-$(date +%Y-%m-%d).md
   ```

6. Stop recording when done:

   ```
   prefix + M        # stop recording (flushes remaining events to Claude)
   ```

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

# Enable AI summarization (default: off)
set -g @muxscribe-ai 'on'

# Model for AI summarization (default: sonnet)
set -g @muxscribe-ai-model 'haiku'

# Batch interval in seconds for AI processing (default: 10)
set -g @muxscribe-ai-interval '10'
```

## Status Bar Indicator

### Static indicator

Use `#{@muxscribe-status}` for a simple non-animated indicator:

```tmux
set -g status-right '#{@muxscribe-status} | %H:%M'
```

Shows `● REC` when recording, empty when stopped.

### Blinking indicator

For a blinking effect (alternates between `●` and `○`), use the bundled `status.sh` script:

```tmux
set -g status-interval 2
set -g status-right '#(~/.tmux/plugins/muxscribe/scripts/status.sh) | %H:%M'
```

This works in terminals that don't support ANSI blink (e.g. Ghostty). The `status-interval` controls the blink speed — 2 seconds gives a steady pulse.

## Output

Summaries are written to `$XDG_STATE_HOME/muxscribe/<session>/summary-YYYY-MM-DD.md` (defaults to `~/.local/state/muxscribe/`).

Example summary output:

```markdown
---
session: "0"
date: 2026-02-23
type: summary
tags: [muxscribe, dev-log, ai-summary]
---

## 10:30–11:15 — Debugging Authentication Bug

- Investigated failing login flow in `src/auth.rs`
- Root cause: token expiry check was off by one hour due to timezone handling
- Applied fix, added regression test in `tests/auth_test.rs`
- All tests passing after fix

## 11:15–11:45 — Code Review and PR

- Reviewed PR #42 feedback from teammate
- Addressed nit about error message wording
- Pushed updated branch and re-requested review
```

## How it works

1. **Hooks fire** on tmux activity (window switches, keystrokes, pane splits, etc.)
2. **capture.sh** snapshots the active pane's visible content and appends a condensed event with terminal content to an event queue
3. **Summarizer daemon** polls the queue every N seconds, feeds batches to `claude --resume` maintaining conversation context
4. **Claude reads and updates** the summary file after each batch

### Manual daemon control

```bash
bash scripts/summarizer.sh flush <session>   # process queued events now
bash scripts/summarizer.sh stop <session>    # stop the daemon
```

## License

MIT
