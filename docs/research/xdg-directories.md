# XDG Base Directory Specification — Research for muxscribe

## Specification Overview

The [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/)
defines standard locations for user-specific files. All paths must be absolute.
If a variable is unset or empty, the documented default applies.

| Variable | Default | Purpose |
|---|---|---|
| `XDG_CONFIG_HOME` | `~/.config` | User-specific configuration files |
| `XDG_DATA_HOME` | `~/.local/share` | User-specific persistent data |
| `XDG_STATE_HOME` | `~/.local/state` | State data: logs, history, undo, recent files |
| `XDG_CACHE_HOME` | `~/.cache` | Non-essential cached data (safe to delete) |
| `XDG_RUNTIME_DIR` | `/run/user/$UID` | Ephemeral runtime files (sockets, PIDs, locks); 0700 permissions; no default fallback — set by `pam_systemd` |

### Key Distinctions

- **DATA vs STATE**: `XDG_DATA_HOME` is for portable, important user data.
  `XDG_STATE_HOME` is for data that persists across restarts but is
  machine-specific and not worth backing up or syncing.
- **STATE vs CACHE**: State data should survive between restarts. Cache data
  can be deleted without functional loss.
- **RUNTIME**: Ephemeral files that must not survive reboot. No guaranteed
  fallback if `XDG_RUNTIME_DIR` is unset — apps must handle this themselves.

## Where Logs Belong: XDG_STATE_HOME

Per the spec, `XDG_STATE_HOME` explicitly covers "actions history (logs,
history, recently used files, ...)". Session logs are:

- **Machine-specific** — not portable across systems
- **Persistent** — should survive restarts (unlike cache or runtime)
- **Not user data** — not important enough for `XDG_DATA_HOME`

Real-world precedent: `less` stores history in `XDG_STATE_HOME/lesshst`,
Python stores REPL history in `XDG_STATE_HOME/python_history`, PostgreSQL
history goes to `XDG_STATE_HOME/psql_history`.

**Recommendation: muxscribe logs go in `XDG_STATE_HOME`.**

## Recommendations for muxscribe

### Directory Layout

```
$XDG_STATE_HOME/muxscribe/          # Session logs (daily markdown files)
    logs/
        2025-01-15.md
        2025-01-16.md

$XDG_CONFIG_HOME/muxscribe/         # Config (future)
    config                           # or muxscribe.conf

$XDG_RUNTIME_DIR/muxscribe/         # Ephemeral runtime (PID files, locks)
    muxscribe.pid
    session-locks/
```

**Naming convention**: lowercase app name as subdirectory, consistent with
the ecosystem (e.g., `~/.local/state/bash/`, `~/.config/git/`).

### Why This Layout

| Data | Directory | Rationale |
|---|---|---|
| Daily log `.md` files | `XDG_STATE_HOME/muxscribe/logs/` | Logs are state — machine-specific, persistent, not portable |
| Configuration | `XDG_CONFIG_HOME/muxscribe/` | Standard config location; user may want to sync/backup |
| PID files, lock files | `XDG_RUNTIME_DIR/muxscribe/` | Ephemeral; must not survive reboot |
| (None currently) | `XDG_DATA_HOME` | No portable user data to store |
| (None currently) | `XDG_CACHE_HOME` | No cached/regenerable data |

### Alternative Considered

Putting logs in `XDG_DATA_HOME` — rejected because session logs are
machine-specific operational records, not user-curated data. The spec
explicitly lists logs under `XDG_STATE_HOME`.

## Bash Implementation

### Path Resolution with Fallbacks

```bash
# Resolve XDG paths with spec-defined defaults
MUXSCRIBE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/muxscribe"
MUXSCRIBE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/muxscribe"
MUXSCRIBE_LOG_DIR="${MUXSCRIBE_STATE_DIR}/logs"

# Runtime dir has no default — requires fallback strategy
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    MUXSCRIBE_RUNTIME_DIR="${XDG_RUNTIME_DIR}/muxscribe"
else
    # Fallback: use a temp directory with restrictive permissions
    MUXSCRIBE_RUNTIME_DIR="/tmp/muxscribe-$(id -u)"
fi
```

### Safe Directory Creation

```bash
# Create directories only when needed, with appropriate permissions
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# State/log directories — standard permissions (user default umask)
ensure_dir "$MUXSCRIBE_STATE_DIR"
ensure_dir "$MUXSCRIBE_LOG_DIR"

# Runtime directory — restrictive permissions (contains PIDs/locks)
ensure_dir "$MUXSCRIBE_RUNTIME_DIR"
chmod 700 "$MUXSCRIBE_RUNTIME_DIR"
```

### Complete Path Resolution Function

```bash
# Full initialization — call once at plugin startup
muxscribe_init_paths() {
    local state_base="${XDG_STATE_HOME:-$HOME/.local/state}"
    local config_base="${XDG_CONFIG_HOME:-$HOME/.config}"

    MUXSCRIBE_LOG_DIR="${state_base}/muxscribe/logs"
    MUXSCRIBE_CONFIG_DIR="${config_base}/muxscribe"

    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        MUXSCRIBE_RUNTIME_DIR="${XDG_RUNTIME_DIR}/muxscribe"
    else
        MUXSCRIBE_RUNTIME_DIR="/tmp/muxscribe-$(id -u)"
    fi

    # Ensure directories exist
    mkdir -p "$MUXSCRIBE_LOG_DIR"
    mkdir -p "$MUXSCRIBE_RUNTIME_DIR" && chmod 700 "$MUXSCRIBE_RUNTIME_DIR"
}

# Resolve today's log file path
muxscribe_log_file() {
    printf '%s/%s.md' "$MUXSCRIBE_LOG_DIR" "$(date +%Y-%m-%d)"
}
```

### User Override Pattern

Allow users to override the log directory via tmux option or env var:

```bash
# Check for user override first, then XDG, then fallback
resolve_log_dir() {
    local user_override
    user_override="$(tmux show-option -gqv @muxscribe-log-dir 2>/dev/null)"

    if [[ -n "$user_override" ]]; then
        printf '%s' "$user_override"
    else
        printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/muxscribe/logs"
    fi
}
```

## Permission Considerations

- **Log directory**: Default umask is fine (typically 0755 for dirs, 0644 for
  files). Session logs are not sensitive secrets, but they're user-private.
- **Runtime directory**: Must be 0700 (user-only). PID files and locks should
  not be readable by other users.
- **Config directory**: Default umask. If config later includes secrets (API
  keys), those specific files should be 0600.

## Edge Cases

1. **`$HOME` unset**: Extremely rare, but `$HOME` could theoretically be unset.
   Not worth guarding against — if `$HOME` is unset, the system is broken.
2. **`XDG_RUNTIME_DIR` unset**: Common on non-systemd systems or in containers.
   Fallback to `/tmp/muxscribe-$UID` with 0700 permissions.
3. **Read-only filesystem**: `mkdir -p` will fail. The plugin should detect this
   and emit a warning rather than silently failing.
4. **Symlinked XDG dirs**: Works fine — `mkdir -p` follows symlinks.

## Sources

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/)
- [Arch Wiki — XDG Base Directory](https://wiki.archlinux.org/title/XDG_Base_Directory)
- [XDG Base Directory Specification advocacy site](https://xdgbasedirectoryspecification.com/)
