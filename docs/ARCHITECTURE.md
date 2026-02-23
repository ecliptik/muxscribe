# muxscribe — Architecture

## Overview

muxscribe is a pure-Bash tmux plugin that records session activity and writes structured markdown logs. It captures tmux events via hooks, snapshots pane content via `capture-pane`, and writes daily-rotated markdown files organized by session — designed for Obsidian import and later AI summarization.

## Design Principles

1. **Zero dependencies** — pure Bash + tmux commands only
2. **Event-driven** — every tmux hook triggers a snapshot
3. **Non-intrusive** — must not slow tmux; all capture work happens in background
4. **Structured output** — markdown with YAML frontmatter, Obsidian-compatible
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
        │      │  capture.sh  │  ← snapshot all panes
        │      └──────┬───────┘
        │             │
        │             ▼
        │      ┌──────────────┐
        └─────▶│  writer.sh   │  ← format & write markdown
               └──────┬───────┘
                      │
                      ▼
           ┌─────────────────────┐
           │ $XDG_STATE_HOME/    │
           │   muxscribe/        │
           │     <session>/      │
           │       YYYY-MM-DD.md │
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
│   ├── capture.sh              # Snapshot pane content for all panes
│   └── writer.sh               # Format events and write markdown
├── docs/
│   ├── ARCHITECTURE.md         # This file
│   └── research/               # Research documents
├── README.md
└── LICENSE                     # MIT
```

## Data Flow

### 1. Activation (User presses `prefix + M`)

```
toggle.sh
  ├── Check if already recording (via @muxscribe-recording option)
  ├── If not recording:
  │   ├── Set @muxscribe-recording "on"
  │   ├── Call hooks.sh register
  │   ├── Call writer.sh init (create session dir, write frontmatter)
  │   ├── Call capture.sh snapshot (initial state)
  │   └── Display "muxscribe: recording started"
  └── If recording:
      ├── Set @muxscribe-recording "off"
      ├── Call hooks.sh unregister
      ├── Call writer.sh close (write session end marker)
      └── Display "muxscribe: recording stopped"
```

### 2. Event Capture (Hook fires)

```
tmux hook fires → run-shell "capture.sh <event_type> <context...>"
  ├── Collect metadata (timestamp, session, window, pane, event type)
  ├── For each pane in session:
  │   └── tmux capture-pane -p -J -t <pane_id>
  ├── Call writer.sh append <event_type> <metadata> <pane_content>
  └── Exit
```

### 3. Markdown Output

```
writer.sh append
  ├── Resolve log file path (XDG_STATE_HOME/muxscribe/<session>/YYYY-MM-DD.md)
  ├── If new day → create new file with frontmatter
  ├── Format entry:
  │   ├── Timestamp header
  │   ├── Event type + context
  │   └── Pane content in code blocks (only changed panes)
  └── Append to file
```

## Hook Registration

All hooks use array index `[100]` to avoid conflicts with other plugins.

### Registered Hooks

| Hook | Category | What We Log |
|------|----------|-------------|
| `after-new-window[100]` | Structure | Window created |
| `after-split-window[100]` | Structure | Pane split |
| `after-kill-pane[100]` | Structure | Pane closed |
| `after-rename-window[100]` | Context | Window renamed |
| `after-rename-session[100]` | Context | Session renamed |
| `after-select-window[100]` | Navigation | Window switched |
| `after-select-pane[100]` | Navigation | Pane switched |
| `after-resize-pane[100]` | Layout | Pane resized |
| `after-resize-window[100]` | Layout | Window resized |
| `after-select-layout[100]` | Layout | Layout changed |
| `after-copy-mode[100]` | Activity | Copy mode entered/exited |
| `after-send-keys[100]` | Activity | Keys sent (debounced) |
| `pane-exited` | Lifecycle | Pane command exited |
| `session-window-changed` | Navigation | Active window changed |
| `window-pane-changed` | Navigation | Active pane changed |
| `session-closed` | Lifecycle | Session ending |
| `alert-activity` | Activity | Activity in monitored window |

**Note on `after-send-keys`**: This fires on every keystroke. We handle this by recording only the fact that keys were sent, not capturing on every keystroke. The capture.sh script implements timestamp-based debouncing — it skips snapshots for `after-send-keys` events if less than 5 seconds have elapsed since the last snapshot.

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `@muxscribe-key` | `M` | Toggle key (prefix + key) |
| `@muxscribe-status-key` | `M-m` | Status key (prefix + key) |
| `@muxscribe-log-dir` | (XDG_STATE_HOME) | Override log directory |
| `@muxscribe-recording` | `off` | Internal: current recording state |
| `@muxscribe-debounce` | `5` | Seconds to debounce high-frequency events |

## Markdown Output Format

### File Path

```
$XDG_STATE_HOME/muxscribe/<session-name>/YYYY-MM-DD.md
```

### File Structure

```markdown
---
session: my-project
date: 2026-02-23
started: "2026-02-23T10:30:00"
host: hostname
tags: [muxscribe, dev-log]
---

# Session: my-project — 2026-02-23

## 10:30:00 — session-start

Recording started. 2 windows, 3 panes.

### Window 0: editor (2 panes)

**Pane 0** — `nvim` in `/home/user/project`
```text
  1  src/main.rs
  2  src/lib.rs
~ ...
`` `

**Pane 1** — `bash` in `/home/user/project`
```text
$ cargo build
   Compiling project v0.1.0
`` `

---

## 10:32:15 — after-new-window

New window created: `terminal`

### Window 1: terminal (1 pane)

**Pane 0** — `bash` in `/home/user/project`
```text
$
`` `

---

## 10:35:42 — after-select-window

Switched to window 0: `editor`

### Window 0: editor — active pane 0

**Pane 0** — `nvim` in `/home/user/project`
```text
fn main() {
    println!("Hello, world!");
}
`` `
```

### Design Choices for Output

1. **Timestamp as H2** — easy to scan, collapsible in Obsidian
2. **Event type in header** — machine-parseable for AI summarization
3. **Only capture active window's panes by default** — reduces noise while keeping context
4. **Code blocks for terminal content** — renders cleanly in markdown
5. **YAML frontmatter** — Obsidian metadata compatibility
6. **Horizontal rules between entries** — visual separation

## Sprint Plan

### Sprint 1: Core Plugin Skeleton (Foundation)

**Deliverables:**
- `muxscribe.tmux` — TPM entry point
- `scripts/helpers.sh` — `get_tmux_option`, `set_tmux_option`, `display_message`
- `scripts/variables.sh` — all option names, defaults, constants
- `scripts/toggle.sh` — start/stop recording with status display
- XDG path resolution
- Toggle keybinding (`prefix + M`)
- Status display keybinding (`prefix + Alt-m`)
- Initial README.md

### Sprint 2: Hook Registration & Event Capture (Engine)

**Deliverables:**
- `scripts/hooks.sh` — register/unregister all hooks
- `scripts/capture.sh` — snapshot pane content
- Hook → capture.sh dispatch pipeline
- Debouncing for high-frequency events (`after-send-keys`)
- All-panes iteration and content capture
- Event metadata collection

### Sprint 3: Markdown Log Writer (Output)

**Deliverables:**
- `scripts/writer.sh` — format and write markdown
- Session directory creation
- Daily file rotation with YAML frontmatter
- Event formatting (timestamp, type, context)
- Pane content formatting (code blocks)
- Diff-awareness: only log panes whose content changed
- Session start/stop markers

### Sprint 4: Integration Testing & Polish

**Deliverables:**
- End-to-end testing with live tmux session
- Edge cases: session rename, window close, pane respawn, detach/reattach
- Performance verification
- Cleanup on session destroy
- Complete README with install/usage/config docs
- LICENSE (MIT)
- CLAUDE.md project conventions
