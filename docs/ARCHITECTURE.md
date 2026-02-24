# muxscribe — Architecture

## Overview

muxscribe is a pure-Bash tmux plugin that watches terminal activity and produces AI-generated session summaries via Claude CLI. It captures tmux events via hooks, snapshots the active pane's visible content, and feeds batches to a Claude-powered background daemon that maintains a live-updating summary file.

## Design Principles

1. **Zero dependencies** — pure Bash + tmux commands + Claude CLI
2. **Event-driven** — every tmux hook triggers a snapshot
3. **Non-intrusive** — must not slow tmux; all capture work happens in background
4. **AI-first** — only output is Claude-generated summaries, no raw logs
5. **XDG-compliant** — follows XDG Base Directory Specification

## Component Architecture

```
┌─────────────────────────────────────────────────────┐
│                   tmux server                        │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  pane %0  │  │  pane %1  │  │  pane %2  │  ...    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │              │              │                 │
│  ─────┴──────────────┴──────────────┴─────           │
│                  tmux hooks                           │
│  ────────────────────┬───────────────────            │
└──────────────────────┼───────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │  muxscribe.tmux │  ← TPM entry point
              │  (plugin init)  │
              └───────┬────────┘
                      │
         ┌────────────┼────────────┐
         ▼            ▼            ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ toggle.sh│ │ hooks.sh │ │helpers.sh│
   │(start/   │ │(register/│ │(options, │
   │ stop)    │ │ dispatch)│ │ utils)   │
   └────┬─────┘ └────┬─────┘ └──────────┘
        │             │
        │             ▼
        │      ┌──────────────┐
        │      │  capture.sh  │  ← snapshot active pane
        │      └──────┬───────┘
        │             │
        │             ▼
        │      ┌──────────────┐     ┌──────────────────────┐
        │      │  event queue │────▶│  summarizer.sh       │
        │      │  (runtime)   │     │  (background daemon)  │
        └─────▶└──────────────┘     └──────────┬───────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  claude CLI  │
                                        │  (--resume)  │
                                        └──────┬──────┘
                                               │
                                               ▼
                                  ┌─────────────────────┐
                                  │ $XDG_STATE_HOME/    │
                                  │   muxscribe/        │
                                  │     <session>/      │
                                  │  summary-YYYY-MM-DD │
                                  └─────────────────────┘
```

## File Structure

```
muxscribe/
├── muxscribe.tmux              # TPM entry point (executable)
├── scripts/
│   ├── helpers.sh              # get_tmux_option, path resolution, utilities
│   ├── variables.sh            # Option names, defaults, constants
│   ├── toggle.sh               # Start/stop recording (keybinding handler)
│   ├── hooks.sh                # Register/unregister all tmux hooks
│   ├── capture.sh              # Snapshot active pane, build event queue entries
│   ├── summarizer.sh           # AI daemon (polls queue, feeds claude CLI)
│   └── status.sh               # Blinking status bar indicator
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   └── research/               # Research documents
├── README.md
└── LICENSE                     # MIT
```

## Data Flow

### 1. Activation (User presses `prefix + M`)

```
toggle.sh start
  ├── Set @muxscribe-recording "on"
  ├── Set @muxscribe-status "● REC"
  ├── Call hooks.sh register
  ├── Call capture.sh "session-start" (initial snapshot → event queue)
  ├── Start summarizer.sh daemon (if @muxscribe-ai is on)
  └── Display "recording started"
```

### 2. Deactivation (User presses `prefix + M` again)

```
toggle.sh stop
  ├── Stop summarizer.sh daemon (flushes remaining events to Claude)
  ├── Call hooks.sh unregister
  ├── Set @muxscribe-recording "off"
  ├── Clear @muxscribe-status
  └── Display "recording stopped"
```

### 3. Event Capture (Hook fires)

```
tmux hook fires → run-shell "capture.sh <event_type> <session>"
  ├── Check debounce (skip if < N seconds since last capture for this event type)
  ├── Collect window/pane metadata for all panes in session
  ├── Capture visible content of each pane via tmux capture-pane -p -J
  ├── Build event queue entry:
  │   ├── Metadata line: [HH:MM:SS] event_type | Window X: name | Y pane(s): cmd in path
  │   ├── Active pane content (from active window + active pane):
  │   │   ├── --- active pane content ---
  │   │   ├── <visible terminal lines>
  │   │   └── --- end ---
  │   └── Append to event queue (locked)
  └── Cleanup temp event file
```

### 4. AI Summarization (Daemon loop)

```
summarizer.sh daemon
  ├── Send initial context prompt to claude (receives session ID for --resume)
  └── Loop every N seconds:
      ├── Acquire exclusive lock on queue file
      ├── Read all queued events atomically
      ├── Clear queue
      ├── Send batch to claude --resume with: "New events:\n<batch>\nUpdate summary file"
      └── Claude reads existing summary, writes updated version
```

## Event Queue Format

Events are stored in `$XDG_RUNTIME_DIR/muxscribe/<session>/event-queue`, one entry per event:

```
[17:31:13] after-select-window | Window 3: claude | 4 pane(s): zsh in /home/user
--- active pane content ---
$ git status
On branch main
Changes not staged for commit:
  modified:   src/main.rs
--- end ---
[17:31:45] after-send-keys | Window 3: claude | 4 pane(s): zsh in /home/user
--- active pane content ---
$ cargo test
running 3 tests
test test_parse ... ok
test test_format ... ok
test test_output ... ok
--- end ---
```

The active pane is identified by both `pane_active == 1` AND `win_active == 1` (the active pane of the active window only).

## Hook Registration

All hooks use array index `[100]` to avoid conflicts with other plugins.

| Hook | Category | Debounced |
|------|----------|-----------|
| `after-new-window[100]` | Structure | No |
| `after-split-window[100]` | Structure | No |
| `after-kill-pane[100]` | Structure | No |
| `after-rename-window[100]` | Context | No |
| `after-rename-session[100]` | Context | No |
| `after-select-window[100]` | Navigation | No |
| `after-select-pane[100]` | Navigation | Yes |
| `after-resize-pane[100]` | Layout | Yes |
| `after-resize-window[100]` | Layout | No |
| `after-select-layout[100]` | Layout | No |
| `after-copy-mode[100]` | Activity | No |
| `after-send-keys[100]` | Activity | Yes |
| `pane-exited` | Lifecycle | No |
| `session-window-changed` | Navigation | No |
| `window-pane-changed` | Navigation | No |
| `session-closed` | Lifecycle | No |
| `alert-activity` | Activity | No |

Debounced events skip capture if less than N seconds (default 5, configurable via `@muxscribe-debounce`) have elapsed since the last snapshot for that event type.

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `@muxscribe-key` | `M` | Toggle key (prefix + key) |
| `@muxscribe-status-key` | `M-m` | Status key (prefix + key) |
| `@muxscribe-log-dir` | (XDG_STATE_HOME) | Override output directory |
| `@muxscribe-debounce` | `5` | Seconds to debounce high-frequency events |
| `@muxscribe-ai` | `off` | Enable AI summarization |
| `@muxscribe-ai-model` | `sonnet` | Claude model for summarization |
| `@muxscribe-ai-interval` | `10` | Seconds between daemon poll cycles |
| `@muxscribe-recording` | `off` | Internal: current recording state |
| `@muxscribe-status` | (empty) | Internal: status bar indicator text |

## Output

### Summary File

```
$XDG_STATE_HOME/muxscribe/<session>/summary-YYYY-MM-DD.md
```

Daily-rotated, YAML frontmatter, maintained by Claude:

```markdown
---
session: "0"
date: 2026-02-23
type: summary
tags: [muxscribe, dev-log, ai-summary]
---

## 10:30–11:15 — Debugging Authentication Bug

- Investigated failing login flow in `src/auth.rs`
- Root cause: token expiry check off by one hour (timezone)
- Applied fix, added regression test
- All tests passing

## 11:15–11:45 — Code Review and PR

- Reviewed PR #42 feedback
- Addressed nit about error message wording
- Pushed updated branch
```

### Runtime Files

```
$XDG_RUNTIME_DIR/muxscribe/<session>/
├── event-queue              — Pending events for summarizer
├── ai-session-id            — Claude --resume session ID
├── summarizer.pid           — Daemon PID
├── summarizer.lock          — Exclusive lock for batch processing
├── last_capture_<event>     — Debounce timestamps
└── event_XXXXXX             — Temporary event files (cleaned up)
```
