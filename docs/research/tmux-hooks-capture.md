# Tmux Hooks, Events, and Capture-Pane Capabilities

Research reference for building event-driven session logging in a pure-Bash tmux plugin.

**Tested against:** tmux 3.5a

## Table of Contents

- [Hooks Overview](#hooks-overview)
- [Complete Hook List (tmux 3.5a)](#complete-hook-list-tmux-35a)
- [Hook Syntax and Management](#hook-syntax-and-management)
- [Hook Format Variables](#hook-format-variables)
- [Capture-Pane Command](#capture-pane-command)
- [Pipe-Pane Command](#pipe-pane-command)
- [Useful Format Variables](#useful-format-variables)
- [Monitoring Options](#monitoring-options)
- [Design Considerations for muxscribe](#design-considerations-for-muxscribe)

---

## Hooks Overview

Tmux hooks are event-triggered commands that execute automatically when specific conditions occur. There are two categories:

1. **Command hooks** — Fire after a tmux command completes (named `after-<command>`)
2. **Non-command hooks** — Fire on specific events (sessions, windows, panes, clients)

Hooks are **array options** (since tmux 3.0), meaning multiple commands can be attached to the same hook using indices.

### Key Properties

- Hooks run in the context of the triggering event
- A command's after hook is NOT run when the command is called from within a hook (prevents infinite loops)
- Hooks can be set globally (`-g`), per-session, or per-window/pane (`-w`/`-p`)
- Session hooks inherit from global hooks
- Hook commands can use tmux format variables for context

---

## Complete Hook List (tmux 3.5a)

Obtained via `tmux show-hooks -g` on tmux 3.5a:

### Command Hooks (after-*)

These fire after the corresponding tmux command completes:

| Hook | Fires After |
|------|-------------|
| `after-bind-key` | A key binding is added |
| `after-capture-pane` | Pane content is captured |
| `after-copy-mode` | Copy mode is entered/exited |
| `after-display-message` | A message is displayed |
| `after-display-panes` | Pane indicators are shown |
| `after-kill-pane` | A pane is killed |
| `after-list-buffers` | Buffers are listed |
| `after-list-clients` | Clients are listed |
| `after-list-keys` | Key bindings are listed |
| `after-list-panes` | Panes are listed |
| `after-list-sessions` | Sessions are listed |
| `after-list-windows` | Windows are listed |
| `after-load-buffer` | A buffer is loaded |
| `after-lock-server` | Server is locked |
| `after-new-session` | A new session is created |
| `after-new-window` | A new window is created |
| `after-paste-buffer` | Buffer content is pasted |
| `after-pipe-pane` | pipe-pane is set up |
| `after-queue` | A command is queued |
| `after-refresh-client` | Client display is refreshed |
| `after-rename-session` | A session is renamed |
| `after-rename-window` | A window is renamed |
| `after-resize-pane` | A pane is resized |
| `after-resize-window` | A window is resized |
| `after-save-buffer` | A buffer is saved |
| `after-select-layout` | A layout is selected |
| `after-select-pane` | A pane is selected |
| `after-select-window` | A window is selected |
| `after-send-keys` | Keys are sent to a pane |
| `after-set-buffer` | A buffer is set |
| `after-set-environment` | An env variable is set |
| `after-set-hook` | A hook is modified |
| `after-set-option` | An option is set |
| `after-show-environment` | Env variables are shown |
| `after-show-messages` | Messages are shown |
| `after-show-options` | Options are shown |
| `after-split-window` | A window is split (new pane) |
| `after-unbind-key` | A key binding is removed |

### Non-Command Hooks (Events)

| Hook | Description | Scope |
|------|-------------|-------|
| `session-created` | A new session is created | Global/Session |
| `session-closed` | A session is destroyed | Global/Session |
| `session-renamed` | A session is renamed | Global/Session |
| `session-window-changed` | The current window in a session changes | Global/Session |
| `window-linked` | A window is linked into a session | Global/Session |
| `window-unlinked` | A window is unlinked from a session | Global/Session |
| `client-active` | A client becomes active (tmux 3.2+) | Global |
| `client-attached` | A client attaches to a session | Global |
| `client-detached` | A client detaches from a session | Global |
| `client-focus-in` | A client receives focus | Global |
| `client-focus-out` | A client loses focus | Global |
| `client-resized` | A client terminal is resized | Global |
| `client-session-changed` | A client switches sessions | Global |
| `command-error` | A command fails (tmux 3.5a+) | Global |
| `alert-activity` | Activity detected in a window | Global |
| `alert-bell` | Bell triggered in a window | Global |
| `alert-silence` | A window has been silent | Global |

### Pane/Window-Level Hooks (set with -w or -p flags)

These hooks are window/pane options (since tmux 3.5):

| Hook | Description | Flag |
|------|-------------|------|
| `pane-died` | The program in a pane exits (remain-on-exit is on) | `-p` |
| `pane-exited` | The program in a pane exits | `-p` |
| `pane-focus-in` | A pane receives focus (requires `focus-events on`) | `-p` |
| `pane-focus-out` | A pane loses focus (requires `focus-events on`) | `-p` |
| `pane-mode-changed` | A pane enters/exits a mode (copy, etc.) | `-p` |
| `pane-set-clipboard` | The terminal clipboard is set via escape sequence | `-p` |
| `window-layout-changed` | Window layout changes | `-w` |
| `window-pane-changed` | The active pane in a window changes | `-w` |
| `window-renamed` | A window is renamed | `-w` |

**Note:** `pane-focus-in`/`pane-focus-out` require the `focus-events` option to be on:
```bash
tmux set-option -g focus-events on
```

---

## Hook Syntax and Management

### Setting Hooks

```bash
# Global hook (applies to all sessions)
tmux set-hook -g session-created 'display-message "New session: #{session_name}"'

# Session-specific hook
tmux set-hook -t mysession session-renamed 'run-shell "/path/to/script.sh"'

# Window/pane hook
tmux set-hook -w window-renamed 'run-shell "/path/to/script.sh"'
tmux set-hook -p pane-focus-in 'run-shell "/path/to/script.sh"'

# Run a hook immediately (useful for testing)
tmux set-hook -R session-created
```

### Array Indices (Multiple Commands Per Hook)

```bash
# Set multiple commands on the same hook
tmux set-hook -g 'after-new-window[0]' 'display-message "hook 0"'
tmux set-hook -g 'after-new-window[1]' 'display-message "hook 1"'
tmux set-hook -g 'after-new-window[42]' 'display-message "hook 42"'
```

- Indices can have gaps (e.g., 0, 1, 42)
- Hooks run in index order (0, then 1, then 42)
- Without an index, `set-hook` replaces the entire hook
- With `-a` flag, appends to the next available index (proposed feature)

### Removing Hooks

```bash
# Remove a specific hook
tmux set-hook -gu session-created

# Remove a specific index
tmux set-hook -gu 'after-new-window[1]'

# Self-cleaning hook (runs once then removes itself)
tmux set-hook client-attached 'display-message "hi" \; set-hook -u client-attached'
```

### Viewing Hooks

```bash
# Show all global hooks
tmux show-hooks -g

# Show session hooks
tmux show-hooks

# Show window/pane hooks
tmux show-hooks -w
tmux show-hooks -p
```

### Running External Scripts from Hooks

```bash
tmux set-hook -g session-created 'run-shell "/path/to/script.sh #{session_name}"'
```

**Important:** `run-shell` executes the script in the background. The script cannot interact with the terminal. Use tmux commands (`display-message`, `set-option`, etc.) for feedback.

---

## Hook Format Variables

When a hook fires, these format variables are available:

| Variable | Description |
|----------|-------------|
| `#{hook}` | Name of the currently running hook |
| `#{hook_pane}` | ID of pane where hook was triggered (if any) |
| `#{hook_window}` | ID of window where hook was triggered (if any) |
| `#{hook_session}` | ID of session where hook was triggered (if any) |
| `#{hook_session_name}` | Name of session where hook was triggered (if any) |
| `#{hook_window_name}` | Name of window where hook was triggered (if any) |
| `#{hook_client}` | Name of client where hook was triggered (if any) |

**Known issue (tmux 3.5a):** Some hooks (notably `after-new-window`) may have these variables unset even when context exists. In such cases, standard variables like `#{window_id}`, `#{session_name}` may still work.

---

## Capture-Pane Command

`capture-pane` captures the content of a pane into a paste buffer or stdout.

### Full Syntax

```
capture-pane [-aCeJNpPqT] [-b buffer-name] [-E end-line] [-S start-line] [-t target-pane]
```

### Flags

| Flag | Description |
|------|-------------|
| `-p` | Print to stdout (instead of paste buffer) |
| `-e` | Include escape sequences (colors, formatting) |
| `-J` | Join wrapped lines |
| `-N` | Preserve trailing spaces at line ends |
| `-T` | Stop at last used cell (ignore trailing empty cells) |
| `-C` | Escape non-printable characters as octal |
| `-a` | Use alternate screen (for programs like vim/less) |
| `-P` | Capture pending (not yet displayed) output |
| `-q` | Silence errors (don't report if pane doesn't exist) |
| `-S` | Starting line number (negative = above visible area, `-` = start of history) |
| `-E` | Ending line number (negative = above current, `-` = end of visible area) |
| `-b` | Target buffer name |
| `-t` | Target pane |

### Common Usage Patterns

```bash
# Capture entire scrollback history to stdout
tmux capture-pane -p -S - -t %0

# Capture only visible area
tmux capture-pane -p -t %0

# Capture last 50 lines
tmux capture-pane -p -S -50 -t %0

# Capture with colors preserved
tmux capture-pane -p -e -S - -t %0

# Capture to a named buffer, then save to file
tmux capture-pane -b mylog -S - -t %0
tmux save-buffer -b mylog ~/capture.txt
tmux delete-buffer -b mylog

# Capture with joined wrapped lines (cleaner output)
tmux capture-pane -p -J -S - -t %0
```

### Line Number Reference

- `0` = first visible line
- Negative numbers = lines above visible area (scrollback)
- `-S -` = start of history (earliest available line)
- `-E -` = end of visible pane

### Limitations

- **History limit:** Capture is bounded by `history-limit` option (default: 2000 lines)
- **No real-time streaming:** capture-pane is a snapshot, not continuous
- **Alternate screen:** Programs like vim use alternate screen; use `-a` to capture that instead
- **Performance:** Large history captures are fast but should be done sparingly

---

## Pipe-Pane Command

`pipe-pane` connects a pane's output to an external command in real-time. This is the **primary mechanism for continuous logging**.

### Syntax

```
pipe-pane [-IOo] [-t target-pane] [shell-command]
```

### Flags

| Flag | Description |
|------|-------------|
| `-O` | Connect pane output (stdout) to the command's stdin (default) |
| `-I` | Connect the command's stdout to the pane's input |
| `-o` | Toggle: only open pipe if not already open |

### Usage

```bash
# Start logging pane output to a file
tmux pipe-pane -t %0 "cat >> ~/tmux-log.txt"

# Stop logging (run without command)
tmux pipe-pane -t %0

# Toggle logging (only start if not already piping)
tmux pipe-pane -o -t %0 "cat >> ~/tmux-log.txt"

# Log with timestamps
tmux pipe-pane -o -t %0 'while IFS= read -r line; do echo "$(date +%Y-%m-%dT%H:%M:%S) $line"; done >> ~/tmux-log.txt'

# Filter for specific patterns
tmux pipe-pane -o -t %0 "grep --line-buffered 'ERROR\|WARN' >> ~/errors.log"

# Bidirectional: inject input AND capture output
tmux pipe-pane -IO -t %0 "my-filter-script"
```

### Key Properties

- Only ONE pipe can be active per pane at a time
- Running `pipe-pane` without a command disconnects the current pipe
- The `-o` flag is useful for toggle behavior (won't create duplicate pipes)
- Output includes ANSI escape sequences (colors, cursor movement)
- For clean logs, pipe through `ansifilter` or `sed` to strip escape codes

### Pipe-Pane vs Capture-Pane

| Feature | pipe-pane | capture-pane |
|---------|-----------|--------------|
| Real-time | Yes (streaming) | No (snapshot) |
| Historical data | No (only new output) | Yes (scrollback) |
| Multiple per pane | No (one at a time) | N/A |
| Performance impact | Minimal (output stream tap) | Low (one-time read) |
| Format control | Raw output | Flags for formatting |
| Use case | Continuous logging | One-time capture |

---

## Useful Format Variables

For a logging plugin, these tmux format variables are essential:

### Session Context

| Variable | Description | Example |
|----------|-------------|---------|
| `#{session_name}` | Session name | `myproject` |
| `#{session_id}` | Unique session ID | `$0` |
| `#{session_created}` | Session creation timestamp (epoch) | `1708700000` |
| `#{session_windows}` | Number of windows | `3` |

### Window Context

| Variable | Description | Example |
|----------|-------------|---------|
| `#{window_name}` | Window name | `editor` |
| `#{window_index}` | Window index | `0` |
| `#{window_id}` | Unique window ID | `@0` |
| `#{window_panes}` | Number of panes | `2` |
| `#{window_active}` | Whether window is active | `1` / `0` |

### Pane Context

| Variable | Description | Example |
|----------|-------------|---------|
| `#{pane_id}` | Unique pane ID | `%0` |
| `#{pane_index}` | Pane index in window | `0` |
| `#{pane_pid}` | PID of command in pane | `12345` |
| `#{pane_current_command}` | Current command running | `vim` |
| `#{pane_current_path}` | Current working directory | `/home/user/project` |
| `#{pane_title}` | Pane title | `user@host` |
| `#{pane_width}` | Pane width in columns | `80` |
| `#{pane_height}` | Pane height in lines | `24` |
| `#{pane_active}` | Whether pane is active | `1` / `0` |
| `#{pane_dead}` | Whether pane process has exited | `1` / `0` |

### Using Format Variables in Scripts

```bash
# In hook commands — tmux expands these before running the command
tmux set-hook -g after-new-window \
    'run-shell "/path/to/script.sh \"#{session_name}\" \"#{window_name}\" \"#{window_index}\""'

# In scripts — query tmux directly
session_name=$(tmux display-message -p '#{session_name}')
window_name=$(tmux display-message -p '#{window_name}')
pane_cmd=$(tmux display-message -p -t "$target_pane" '#{pane_current_command}')

# List all panes with specific format
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}'
```

---

## Monitoring Options

These built-in options complement hooks for event detection:

| Option | Description | Default |
|--------|-------------|---------|
| `monitor-activity` | Watch for activity (output) in windows | `off` |
| `monitor-bell` | Watch for bell in windows | `on` |
| `monitor-silence` | Watch for silence (seconds, 0=off) | `0` |
| `activity-action` | What to do on activity | `other` |
| `bell-action` | What to do on bell | `any` |
| `silence-action` | What to do on silence | `none` |
| `visual-activity` | Show visual message for activity | `off` |
| `visual-bell` | Show visual message for bell | `off` |
| `visual-silence` | Show visual message for silence | `off` |
| `focus-events` | Pass focus events to applications | `off` |

**For muxscribe:** `focus-events on` is needed for `pane-focus-in`/`pane-focus-out` hooks.

---

## Design Considerations for muxscribe

### Recommended Hooks for Session Logging

**Essential hooks (high value for logging):**

| Hook | What to Log | Priority |
|------|-------------|----------|
| `session-created` | "Session X created" | High |
| `session-closed` | "Session X ended" | High |
| `session-renamed` | "Session renamed from X to Y" | Medium |
| `after-new-window` | "Window X created in session Y" | High |
| `after-kill-pane` | "Pane closed" | Medium |
| `after-split-window` | "Pane split in window X" | Medium |
| `after-rename-window` | "Window renamed to X" | Medium |
| `session-window-changed` | "Switched to window X" | Low-Medium |
| `client-session-changed` | "Client switched to session X" | Low |
| `pane-exited` | "Command exited in pane X" | Medium |

### Hook Registration Strategy

```bash
# Use unique array indices to avoid conflicts with other plugins
# Convention: use high indices (100+) to reduce collision risk
tmux set-hook -g 'session-created[100]' 'run-shell "$SCRIPT_DIR/on_session_created.sh #{session_name}"'
tmux set-hook -g 'after-new-window[100]' 'run-shell "$SCRIPT_DIR/on_new_window.sh #{session_name} #{window_name}"'
```

### Hook Deregistration (cleanup)

```bash
# Remove our hooks on plugin unload/disable
tmux set-hook -gu 'session-created[100]'
tmux set-hook -gu 'after-new-window[100]'
```

### Performance Considerations

1. **Hook scripts should be fast** — hooks block tmux briefly while running. Use `run-shell` (runs in background) rather than inline commands.
2. **Avoid hooking high-frequency events** unless necessary:
   - `after-send-keys` fires on EVERY keystroke — avoid
   - `after-select-pane` fires on every pane switch — use sparingly
   - `pane-focus-in`/`pane-focus-out` fires on pane changes — moderate frequency
3. **Batch writes** — buffer log entries and flush periodically rather than writing on every event
4. **pipe-pane for content logging** — use for continuous output capture, not hooks
5. **capture-pane for snapshots** — use for periodic state dumps, not per-event

### Capture Strategy Recommendations

For a session logging plugin, the best approach is likely:

1. **Hooks** for structural events (session/window/pane lifecycle)
2. **pipe-pane** for continuous output logging (if desired)
3. **capture-pane** for periodic state snapshots or on-demand captures
4. **Format variables** via `tmux display-message -p` for context metadata

### Stripping ANSI Escape Codes

When capturing pane output for clean logs:

```bash
# Using sed
captured | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'

# Using ansifilter (if available)
captured | ansifilter

# capture-pane without -e flag returns plain text (no escapes)
tmux capture-pane -p -S - -t %0  # Clean text, no ANSI codes
```

---

## Sources

- [tmux man page](https://man7.org/linux/man-pages/man1/tmux.1.html)
- [tmux GitHub: Complete list of hooks (Issue #1083)](https://github.com/tmux/tmux/issues/1083)
- [tmux GitHub: Hook format variables (Issue #3439)](https://github.com/tmux/tmux/issues/3439)
- [tmux GitHub: CHANGES](https://raw.githubusercontent.com/tmux/tmux/3.5a/CHANGES)
- [tmux Wiki: Formats](https://github.com/tmux/tmux/wiki/Formats)
- [tmux Wiki: Advanced Use](https://github.com/tmux/tmux/wiki/Advanced-Use)
- [The Power of tmux Hooks (devel.tech)](https://devel.tech/tips/n/tMuXz2lj/the-power-of-tmux-hooks/)
- [set-hook example (ThomasAdam gist)](https://gist.github.com/ThomasAdam/4007114)
- [tmuxai: capture-pane guide](https://tmuxai.dev/tmux-capture-pane/)
- [tmuxai: pipe-pane guide](https://tmuxai.dev/tmux-pipe-pane/)
- [libtmux: Options and Hooks](https://libtmux.git-pull.com/topics/options_and_hooks.html)
