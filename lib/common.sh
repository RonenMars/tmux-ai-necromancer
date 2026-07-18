#!/usr/bin/env bash
# lib/common.sh — shared helpers for tmux-ai-necromancer scripts.
#
# Sourced, never executed. Provides:
#   - PLUGIN_ROOT resolution (path-agnostic; works wherever the repo is cloned)
#   - snapshot dir resolution (honors @necromancer_snapshot_dir / env / default)
#   - debug log resolution (honors @necromancer_log_dir / env / default)
#   - opt-in debug tracing helpers
#   - JSON string escaping
#   - tmux option getters
#
# No `set -e` here — callers decide. This file must be side-effect-free beyond
# defining functions and a few readonly-ish globals.

# --- Path resolution --------------------------------------------------------
# Resolve the plugin root from this file's location: lib/common.sh -> repo root.
_necro_common_src="${BASH_SOURCE[0]}"
# Follow symlinks (TPM may symlink the plugin dir).
while [ -h "$_necro_common_src" ]; do
  _necro_dir="$(cd -P "$(dirname "$_necro_common_src")" && pwd)"
  _necro_common_src="$(readlink "$_necro_common_src")"
  case "$_necro_common_src" in
    /*) ;;
    *) _necro_common_src="$_necro_dir/$_necro_common_src" ;;
  esac
done
PLUGIN_ROOT="$(cd -P "$(dirname "$_necro_common_src")/.." && pwd)"
LIB_DIR="$PLUGIN_ROOT/lib"
SCRIPTS_DIR="$PLUGIN_ROOT/scripts"
unset _necro_common_src _necro_dir

# --- tmux option helpers ----------------------------------------------------
# Read a global tmux option, falling back to a default. Safe when no server.
necro_tmux_option() {
  local option="$1" default="${2:-}"
  local val
  val="$(tmux show-option -gqv "$option" 2>/dev/null)" || true
  printf '%s' "${val:-$default}"
}

# --- Snapshot dir -----------------------------------------------------------
# Precedence: explicit env var > tmux option > legacy default.
# The legacy default (~/.claude/tmux-snapshots) is kept so existing snapshots
# and the dotfiles history remain readable after migration.
necro_snapshot_dir() {
  if [ -n "${NECROMANCER_SNAPSHOT_DIR:-}" ]; then
    printf '%s' "$NECROMANCER_SNAPSHOT_DIR"
    return
  fi
  local opt
  opt="$(necro_tmux_option @necromancer_snapshot_dir "")"
  if [ -n "$opt" ]; then
    # Expand a leading ~ since tmux options store it literally.
    case "$opt" in
      "~"|"~/"*) opt="$HOME${opt#\~}" ;;
    esac
    printf '%s' "$opt"
    return
  fi
  printf '%s' "$HOME/.claude/tmux-snapshots"
}

# --- Log dir ----------------------------------------------------------------
# Precedence: explicit env var > tmux option > default local dir.
necro_log_dir() {
  if [ -n "${NECROMANCER_LOG_DIR:-}" ]; then
    printf '%s' "$NECROMANCER_LOG_DIR"
    return
  fi
  local opt
  opt="$(necro_tmux_option @necromancer_log_dir "")"
  if [ -n "$opt" ]; then
    case "$opt" in
      "~"|"~/"*) opt="$HOME${opt#\~}" ;;
    esac
    printf '%s' "$opt"
    return
  fi
  printf '%s' "$HOME/.tmux-ai-necromancer-logs"
}

# --- Debug logging ----------------------------------------------------------
# Precedence: explicit env var > tmux option > disabled. When enabled, every
# command after initialization is traced to the script's log file.
necro_debug_enabled() {
  local value
  if [ -n "${NECROMANCER_DEBUG+x}" ]; then
    value="$NECROMANCER_DEBUG"
  else
    value="$(necro_tmux_option @necromancer_debug "off")"
  fi
  case "$value" in
    1|on|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Write a single shell-command trace line. A DEBUG trap works on macOS's
# Bash 3.2, unlike BASH_XTRACEFD, and does not alter a status hook's stdout.
necro_debug_trace() {
  local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  printf '[%s] %s:%s: %s\n' \
    "$(necro_ts)" "${source##*/}" "$LINENO" "$BASH_COMMAND" >&3
}

# Initialize opt-in per-script debug tracing. Stdout and stderr remain
# untouched; the DEBUG trap writes commands directly to the debug log.
necro_init_log() {
  necro_debug_enabled || return 0

  local script="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
  local name log_dir
  name="$(basename "$script")"
  name="${name%.*}"
  log_dir="$(necro_log_dir)"
  mkdir -p "$log_dir" || {
    necro_warn "could not create debug log directory: $log_dir"
    return 0
  }
  NECRO_LOG_FILE="$log_dir/$name.log"
  export NECRO_LOG_FILE
  exec 3>> "$NECRO_LOG_FILE"
  set -o functrace
  trap 'necro_debug_trace' DEBUG
}

# --- Logging ----------------------------------------------------------------
necro_say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
necro_ok()   { printf '\033[0;32m✓\033[0m %s\n' "$*"; }
necro_warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
necro_err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
necro_hr()   { printf '\n\033[2m─────────────────────────────────────────────\033[0m\n\n'; }

# Timestamp for log lines.
necro_ts() { date '+%Y-%m-%d %H:%M:%S'; }

# --- JSON ------------------------------------------------------------------
# JSON-encode a string safely (handles unicode + control chars) via python3.
necro_json_escape() {
  printf '%s' "$1" | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

# --- Watcher cursor dir -----------------------------------------------------
# Persistent cursor dir for the watcher (lives next to snapshots, not in /tmp).
necro_watch_cursor_dir() {
  local d
  d="$(necro_snapshot_dir)/.watcher-cursors"
  mkdir -p "$d"
  printf '%s' "$d"
}

# --- Idle-shell test --------------------------------------------------------
necro_is_idle_shell() {
  case "$1" in
    zsh|bash|fish|sh) return 0 ;;
    *) return 1 ;;
  esac
}
