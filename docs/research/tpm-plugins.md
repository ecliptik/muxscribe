# TPM Plugin Structure and Conventions

Research reference for building a pure-Bash tmux plugin compatible with TPM (Tmux Plugin Manager).

## Table of Contents

- [Plugin Directory Structure](#plugin-directory-structure)
- [How TPM Discovers and Loads Plugins](#how-tpm-discovers-and-loads-plugins)
- [Plugin Initialization](#plugin-initialization)
- [Plugin Options Convention](#plugin-options-convention)
- [Keybinding Registration](#keybinding-registration)
- [Common Helper Functions](#common-helper-functions)
- [Reference Plugin Analysis](#reference-plugin-analysis)
- [Patterns for muxscribe](#patterns-for-muxscribe)

---

## Plugin Directory Structure

### Required Files

```
plugin-name/
├── plugin-name.tmux          # Main entry point (MUST be executable)
├── scripts/                   # Supporting scripts
│   ├── helpers.sh             # Common helper functions
│   ├── variables.sh           # Option defaults and variable declarations
│   └── <feature>.sh           # Feature-specific scripts
├── README.md
└── LICENSE
```

### Key Rules

1. **The `.tmux` file is the entry point.** TPM executes all `*.tmux` files in the plugin's root directory. Convention is to have exactly one, named after the plugin.
2. **The `.tmux` file MUST be executable.** `chmod u+x plugin-name.tmux` is required.
3. **Scripts in `scripts/` should also be executable** when called via `run-shell`.
4. **Use `#!/usr/bin/env bash` shebang** for portability.
5. **Keep logic in `scripts/`**, not in the main `.tmux` file. The `.tmux` file should only source helpers/variables and register keybindings.

### Optional Directories

Some plugins also include:
- `docs/` — additional documentation
- `lib/` — library modules (tmux-resurrect)
- `tests/` — test suites
- `strategies/` — pluggable strategy scripts (tmux-resurrect)

### File Permissions

```bash
chmod u+x plugin-name.tmux
chmod u+x scripts/*.sh
```

---

## How TPM Discovers and Loads Plugins

### Plugin Declaration (user's .tmux.conf)

```tmux
# Shorthand (GitHub)
set -g @plugin 'username/plugin-name'

# Full git URL
set -g @plugin 'git@github.com:username/plugin-name'
```

### Plugin Install Location

- **Default:** `~/.tmux/plugins/`
- **XDG-aware:** If `$XDG_CONFIG_HOME/tmux/tmux.conf` exists, plugins go to `$XDG_CONFIG_HOME/tmux/plugins/`
- **Custom:** `set-environment -g TMUX_PLUGIN_MANAGER_PATH '/custom/path/'`

### Loading Mechanism (source_plugins.sh)

TPM's `source_plugins.sh` does the following:

1. Reads the list of declared plugins from `@plugin` options
2. For each plugin, resolves the plugin directory path
3. Calls `silently_source_all_tmux_files()` which:
   - Globs for `*.tmux` files in the plugin root
   - Checks directory exists (`[ -d "$plugin_path" ]`)
   - Executes each `.tmux` file as a subprocess
   - Redirects stdout/stderr to `/dev/null`

**Key detail:** Plugins are **executed** (not sourced). Each `*.tmux` file runs as a separate bash process. This means:
- Plugins cannot share shell variables with each other
- Communication happens through tmux options (`set-option`/`show-option`)
- The working directory is NOT the plugin directory (you must calculate it)

### TPM Initialization Line

```tmux
# Must be the LAST line in .tmux.conf
run '~/.tmux/plugins/tpm/tpm'
# Or background variant:
run -b '~/.tmux/plugins/tpm/tpm'
```

---

## Plugin Initialization

### Standard Initialization Pattern

Every plugin follows this pattern in its main `.tmux` file:

```bash
#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/variables.sh"
source "$CURRENT_DIR/scripts/helpers.sh"

main() {
    # Register keybindings
    # Set default options
    # Initialize hooks/watchers
}
main
```

### Getting the Plugin Directory

Since the working directory is not guaranteed, plugins MUST resolve their own path:

```bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
```

This is the single most important line — every plugin uses it. Scripts in `scripts/` use it too:

```bash
# Inside scripts/some_feature.sh
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/helpers.sh"
```

### Execution Environment

- **Working directory:** Not the plugin dir (must be calculated)
- **PATH:** Inherited from tmux server process
- **Environment:** tmux server environment (access via `tmux show-environment`)
- **Plugin path:** Available via `tmux show-env -g TMUX_PLUGIN_MANAGER_PATH`

### Setting Default Options

Plugins use `set-option -gq` to register defaults quietly:

```bash
tmux set-option -gq "@plugin-name-some-option" "default-value"
```

The `-q` flag suppresses errors if the option already exists (user has overridden it in .tmux.conf).

---

## Plugin Options Convention

### Naming Pattern

All plugin options use the `@` prefix with the plugin name:

```
@plugin-name-option-name
```

Examples from real plugins:
```
@resurrect-save          # tmux-resurrect: save keybinding
@resurrect-restore       # tmux-resurrect: restore keybinding
@resurrect-processes     # tmux-resurrect: process list
@continuum-save-interval # tmux-continuum: save interval in minutes
@continuum-restore       # tmux-continuum: auto-restore toggle
@logging-path            # tmux-logging: log file path
@logging-filename        # tmux-logging: log filename template
@logging_key             # tmux-logging: toggle logging key
@sessionist-goto         # tmux-sessionist: goto session key
@sessionist-new          # tmux-sessionist: new session key
```

**Note:** Some plugins use hyphens (`@logging-path`), some use underscores (`@logging_key`). Pick one convention and stick with it. Hyphens are more common.

### How Users Set Options

In `.tmux.conf`, before the TPM `run` line:

```tmux
set -g @resurrect-save 'S'
set -g @continuum-save-interval '60'
set -g @logging-path '#{pane_current_path}'
```

### Reading Options with Defaults

**Pattern 1: Direct inline (tmux-logging style)**

```bash
default_logging_key="P"
logging_key=$(tmux show-option -gqv "@logging_key")
logging_key=${logging_key:-$default_logging_key}
```

**Pattern 2: Helper function (tmux-resurrect / tmux-sessionist style)**

```bash
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Usage:
local key=$(get_tmux_option "@resurrect-save" "C-s")
```

**Pattern 2 is preferred** — it's cleaner, reusable, and used by most plugins.

### Common Option Types

| Type | Example | Notes |
|------|---------|-------|
| Key binding | `@plugin-key "C-s"` | Single key or key combo |
| Path | `@plugin-path "$HOME"` | Supports tmux format strings |
| Toggle | `@plugin-restore 'on'` | Check with string comparison |
| Integer | `@plugin-interval '15'` | Minutes, seconds, etc. |
| List | `@plugin-processes 'vi vim nvim'` | Space-separated |
| Filename template | `@plugin-filename 'tmux-#{session_name}.log'` | Tmux format vars |

### Setting Options from Plugin Code

```bash
# Quietly set (won't override user's setting if already set)
tmux set-option -gq "@plugin-name-option" "value"

# The -q flag: suppresses errors for unknown options
# The -g flag: sets globally
```

**Important:** `set-option -gq` does NOT respect "don't override if set". It always sets. To avoid overriding user settings, use the read-with-default pattern instead — don't set defaults, just fall back in code.

---

## Keybinding Registration

### Basic Pattern

```bash
tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/my_action.sh"
```

### Configurable Keybinding Pattern (recommended)

```bash
#!/usr/bin/env bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/scripts/helpers.sh"

# Default key, overridable via @plugin-name-key option
default_key="T"
option_name="@plugin-name-key"

set_keybinding() {
    local key_bindings
    key_bindings=$(get_tmux_option "$option_name" "$default_key")
    local key
    for key in $key_bindings; do
        tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/action.sh"
    done
}

main() {
    set_keybinding
}
main
```

### Key Conventions

- **Prefix table (default):** `tmux bind-key KEY ...` binds to `prefix + KEY`
- **Root table:** `tmux bind-key -n KEY ...` (no prefix needed — use sparingly)
- **Custom key tables:** `tmux bind-key -T mytable KEY ...`
- **Multiple keys:** Space-separated in option value (tmux-sessionist supports this)

### Key Naming

| Key | tmux name |
|-----|-----------|
| Ctrl+s | `C-s` |
| Alt+p | `M-p` |
| Shift+P | `P` (uppercase) |
| Alt+Shift+P | `M-P` |
| F5 | `F5` |

### Passing Tmux Variables to Scripts

```bash
tmux bind-key "$key" run-shell \
    "$CURRENT_DIR/scripts/action.sh '#{session_name}' '#{pane_id}' '#{pane_current_path}'"
```

Tmux format variables (e.g., `#{session_name}`) are expanded by tmux before the script runs.

### Avoid Overriding Native Bindings

Check the tmux man page KEY BINDINGS section. Commonly used native keys to avoid:
- `c` (new window), `n`/`p` (next/prev window), `l` (last window)
- `0-9` (select window), `d` (detach), `w` (window list)
- `"` / `%` (split panes), `x` (kill pane), `z` (zoom)

### Disabling a Binding via Option

tmux-resurrect supports setting a key to `'off'` to disable:

```bash
set_save_bindings() {
    local key_bindings=$(get_tmux_option "$save_option" "$default_save_key")
    local key
    for key in $key_bindings; do
        if [ "$key" != "off" ]; then
            tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/save.sh"
        fi
    done
}
```

---

## Common Helper Functions

### get_tmux_option (most common helper)

```bash
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}
```

### set_tmux_option

```bash
set_tmux_option() {
    local option="$1"
    local value="$2"
    tmux set-option -gq "$option" "$value"
}
```

### Display message to user

```bash
display_message() {
    tmux display-message "$1"
}
```

### Version checking

```bash
# tmux-continuum/tmux-resurrect check tmux version compatibility
supported_tmux_version_ok() {
    "$CURRENT_DIR/scripts/check_tmux_version.sh" "$SUPPORTED_VERSION"
}
```

---

## Reference Plugin Analysis

### tmux-resurrect

```
tmux-resurrect/
├── resurrect.tmux              # Entry point
├── scripts/
│   ├── variables.sh            # Option names and defaults
│   ├── helpers.sh              # get_tmux_option, etc.
│   ├── save.sh                 # Save logic
│   └── restore.sh              # Restore logic
├── lib/                        # Library modules
├── strategies/                 # Pluggable restore strategies
├── save_command_strategies/
├── docs/
│   └── custom_key_bindings.md
└── tests/
```

**Options:** `@resurrect-save`, `@resurrect-restore`, `@resurrect-processes`, `@resurrect-strategy-*`

**Pattern highlights:**
- Configurable keybindings via `get_tmux_option`
- Stores script paths as tmux options for other plugins to discover:
  ```bash
  tmux set-option -gq "$save_path_option" "$CURRENT_DIR/scripts/save.sh"
  ```
- Strategy pattern for extensible behavior
- `set_default_strategies()` registers process-specific restore strategies

### tmux-logging

```
tmux-logging/
├── logging.tmux                # Entry point
├── scripts/
│   ├── variables.sh            # All defaults and option reads
│   ├── shared.sh               # Shared utilities
│   ├── toggle_logging.sh       # Toggle pane logging
│   ├── screen_capture.sh       # Capture visible text
│   ├── save_complete_history.sh
│   └── clear_history.sh
└── docs/
    └── configuration.md
```

**Options:** `@logging_key`, `@logging-path`, `@logging-filename`, `@screen-capture-key`, `@save-complete-history-key`, `@clear-history-key`

**Pattern highlights:**
- Variables are resolved at source time (in `variables.sh`), not in a function
- Uses inline default pattern: `var=${custom:-$default}`
- Filename templates use tmux format strings: `#{session_name}-#{window_index}-#{pane_index}-%Y%m%dT%H%M%S.log`
- Multiple keybindings for different features
- Sources `variables.sh` and `shared.sh` before binding keys

### tmux-continuum

```
tmux-continuum/
├── continuum.tmux              # Entry point
├── scripts/
│   ├── helpers.sh
│   ├── variables.sh
│   ├── shared.sh
│   ├── check_tmux_version.sh
│   ├── continuum_save.sh       # Background save logic
│   ├── continuum_restore.sh    # Auto-restore
│   └── handle_tmux_automatic_start.sh
└── docs/
    ├── faq.md
    └── continuum_status.md
```

**Options:** `@continuum-save-interval`, `@continuum-restore`, `@continuum-boot`

**Pattern highlights:**
- Injects save command into `status-right` via interpolation for periodic execution:
  ```bash
  save_command_interpolation="#($CURRENT_DIR/scripts/continuum_save.sh)"
  ```
- Uses `#()` tmux command substitution in status line for periodic execution
- Background restore on server start: `"$CURRENT_DIR/scripts/continuum_restore.sh" &`
- Multi-server detection to prevent conflicts
- Status line interpolation: `#{continuum_status}`
- Version checking before initialization

### tmux-sessionist

```
tmux-sessionist/
├── sessionist.tmux             # Entry point
├── scripts/
│   ├── helpers.sh
│   ├── goto_session.sh
│   ├── new_session_prompt.sh
│   ├── promote_pane.sh
│   ├── promote_window.sh
│   ├── join_pane.sh
│   └── kill_session_prompt.sh
└── README.md
```

**Options:** `@sessionist-goto`, `@sessionist-alternate`, `@sessionist-new`, `@sessionist-promote-pane`, `@sessionist-promote-window`, `@sessionist-join-pane`, `@sessionist-kill-session`

**Pattern highlights:**
- One option per keybinding, all configurable
- Default bindings defined as variables at top of file
- Each feature gets its own `set_*_binding()` function
- Passes tmux format variables to scripts:
  ```bash
  tmux bind "$key" run "$CURRENT_DIR/scripts/promote_pane.sh '#{session_name}' '#{pane_id}' '#{pane_current_path}'"
  ```
- Supports custom key tables for multi-key sequences (join-pane)
- All bindings iterate over space-separated key list (supports multiple keys per action)

---

## Patterns for muxscribe

Based on this research, here's the recommended structure for muxscribe:

### Proposed File Structure

```
muxscribe/
├── muxscribe.tmux              # Entry point (executable)
├── scripts/
│   ├── helpers.sh              # get_tmux_option, display_message, etc.
│   ├── variables.sh            # Option names, defaults
│   ├── hooks.sh                # Hook registration/deregistration
│   ├── capture.sh              # Pane/event capture logic
│   ├── writer.sh               # Markdown log writing
│   └── toggle.sh               # Enable/disable logging
├── docs/
├── tests/
├── README.md
└── LICENSE
```

### Proposed Options

```
@muxscribe-key          # Toggle key (default: configurable)
@muxscribe-log-path     # Log output directory
@muxscribe-format       # Log format (markdown)
@muxscribe-auto-start   # Auto-start on session create (on/off)
@muxscribe-verbose      # Verbose mode (on/off)
```

### Initialization Pattern

```bash
#!/usr/bin/env bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/scripts/helpers.sh"
source "$CURRENT_DIR/scripts/variables.sh"

main() {
    set_keybindings
    register_hooks
}
main
```

### Key Takeaways

1. **Always use `CURRENT_DIR` pattern** — never assume working directory
2. **Use `get_tmux_option` helper** — standard across all plugins
3. **Name options `@muxscribe-*`** — consistent hyphenated naming
4. **Keep `.tmux` file minimal** — delegate to scripts/
5. **Use `run-shell` for keybindings** — scripts run in a subshell
6. **Make all keybindings configurable** — follow sessionist pattern
7. **Use `tmux display-message`** — for user feedback
8. **Tmux format variables** — pass context like `#{session_name}` via run-shell args
9. **No interactive input** — `run-shell` scripts can't do interactive I/O
10. **Suppress output** — TPM redirects plugin stdout/stderr to /dev/null during load

---

## Sources

- [TPM: How to Create a Plugin](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md)
- [TPM Repository](https://github.com/tmux-plugins/tpm)
- [TPM source_plugins.sh](https://github.com/tmux-plugins/tpm/blob/master/scripts/source_plugins.sh)
- [TPM: Changing Plugin Install Dir](https://github.com/tmux-plugins/tpm/blob/master/docs/changing_plugins_install_dir.md)
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [tmux-resurrect: Custom Key Bindings](https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/custom_key_bindings.md)
- [tmux-logging](https://github.com/tmux-plugins/tmux-logging)
- [tmux-logging: variables.sh](https://github.com/tmux-plugins/tmux-logging/blob/master/scripts/variables.sh)
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum)
- [tmux-sessionist](https://github.com/tmux-plugins/tmux-sessionist)
- [tmux-example-plugin](https://github.com/tmux-plugins/tmux-example-plugin)
- [Inside a Tmux Plugin Repository (Part One)](https://freddieventura.github.io/2023/10/05/inside-tmux-plugin-partone.html)
- [Setting Options in tmux](https://www.seanh.cc/2020/12/28/setting-options-in-tmux/)
- [Tmux Plugin Development with a Local Repo](https://qmacro.org/blog/posts/2023/11/13/tmux-plugin-development-with-a-local-repo/)
