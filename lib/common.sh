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
# Global options are read via a single batched `tmux show-options -g` call,
# cached for the life of the process, instead of one `tmux show-option`
# subprocess per lookup. A script like necro-watch.sh reads 5-8 global options
# per invocation and status-right can invoke it dozens of times per second
# across several attached clients; forking a `tmux show-option` per read
# multiplies that into hundreds of processes for the exact same data. The
# cache is a newline-delimited "name<TAB>value" blob parsed once with a shell
# loop (no bash-4 assoc arrays — invariant 13).
_NECRO_TMUX_OPTS_G_CACHE=""
_NECRO_TMUX_OPTS_G_LOADED=""

_necro_load_tmux_options_g() {
  [ -n "$_NECRO_TMUX_OPTS_G_LOADED" ] && return 0
  _NECRO_TMUX_OPTS_G_LOADED=1
  local line name value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%% *}"
    value="${line#* }"
    # tmux quotes values containing spaces; strip one layer of matching quotes.
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
    esac
    _NECRO_TMUX_OPTS_G_CACHE="$_NECRO_TMUX_OPTS_G_CACHE
$name	$value"
  done < <(tmux show-options -g 2>/dev/null)
}

# Read a global tmux option, falling back to a default. Safe when no server.
necro_tmux_option() {
  local option="$1" default="${2:-}"
  _necro_load_tmux_options_g
  local line val found=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "$option"$'\t'*)
        val="${line#*$'\t'}"
        found=1
        break
        ;;
    esac
  done <<< "$_NECRO_TMUX_OPTS_G_CACHE"
  if [ -n "$found" ]; then
    printf '%s' "${val:-$default}"
  else
    printf '%s' "$default"
  fi
}

# --- Pane-scoped tmux option helpers -----------------------------------------
# necro-watch.sh reads 4-5 @necro_* options per pane, every pane, every tick.
# One `tmux show-options -p -t <pane>` call replaces 4-5 `tmux show-option`
# subprocesses for that pane. The cache is scoped to the current pane only
# (set via necro_load_tmux_options_p before reading); a script walking many
# panes calls it once per pane, right before reading that pane's options.
_NECRO_TMUX_OPTS_P_CACHE=""

necro_load_tmux_options_p() {
  local pane_id="$1"
  _NECRO_TMUX_OPTS_P_CACHE=""
  local line name value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%% *}"
    value="${line#* }"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
    esac
    _NECRO_TMUX_OPTS_P_CACHE="$_NECRO_TMUX_OPTS_P_CACHE
$name	$value"
  done < <(tmux show-options -p -t "$pane_id" 2>/dev/null)
}

# Read a pane-scoped option from the cache loaded by necro_load_tmux_options_p.
# Caller must load the pane's cache first; this never shells out itself.
necro_tmux_option_p() {
  local option="$1" default="${2:-}"
  local line val found=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "$option"$'\t'*)
        val="${line#*$'\t'}"
        found=1
        break
        ;;
    esac
  done <<< "$_NECRO_TMUX_OPTS_P_CACHE"
  if [ -n "$found" ]; then
    printf '%s' "${val:-$default}"
  else
    printf '%s' "$default"
  fi
}

# --- Snapshot dir -----------------------------------------------------------
# Precedence: explicit env var > tmux option > legacy default.
# The legacy default (~/.claude/tmux-snapshots) is kept so existing snapshots
# and the dotfiles history remain readable after migration.
necro_snapshot_dir() {
  if [ -n "${NECROMANCER_SNAPSHOT_DIR:-}" ]; then
    case "$NECROMANCER_SNAPSHOT_DIR" in
      "\\~"|"\\~/"*) printf '%s%s' "$HOME" "${NECROMANCER_SNAPSHOT_DIR#\\~}" ;;
      *) printf '%s' "$NECROMANCER_SNAPSHOT_DIR" ;;
    esac
    return
  fi
  local opt
  opt="$(necro_tmux_option @necromancer_snapshot_dir "")"
  if [ -n "$opt" ]; then
    # Expand a leading ~ since tmux options store it literally.
    case "$opt" in
      "~"|"~/"*) opt="$HOME${opt#\~}" ;;
      "\\~"|"\\~/"*) opt="$HOME${opt#\\~}" ;;
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
    case "$NECROMANCER_LOG_DIR" in
      "\\~"|"\\~/"*) printf '%s%s' "$HOME" "${NECROMANCER_LOG_DIR#\\~}" ;;
      *) printf '%s' "$NECROMANCER_LOG_DIR" ;;
    esac
    return
  fi
  local opt
  opt="$(necro_tmux_option @necromancer_log_dir "")"
  if [ -n "$opt" ]; then
    case "$opt" in
      "~"|"~/"*) opt="$HOME${opt#\~}" ;;
      "\\~"|"\\~/"*) opt="$HOME${opt#\\~}" ;;
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

# Emit a machine-searchable lifecycle/action record. Callers should use stable
# phase and action names and pass only key=value fields (never transcript or
# scrollback contents).
necro_log_event() {
  [ -n "${NECRO_LOG_FILE:-}" ] || return 0
  local phase="$1" action="$2"
  shift 2
  printf '[%s] event phase=%s action=%s' "$(necro_ts)" "$phase" "$action" >&3
  local field
  for field in "$@"; do
    printf ' %s' "$field" >&3
  done
  printf '\n' >&3
}

# Initialize opt-in per-script structured logging. Stdout and stderr remain
# untouched; callers emit lifecycle and action events via necro_log_event.
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
  necro_log_event "run" "start" "script=$name"
}

# --- Logging ----------------------------------------------------------------
necro_say()  { necro_log_event "message" "info" "text=$*"; printf '\033[1;36m▸\033[0m %s\n' "$*"; }
necro_ok()   { necro_log_event "message" "success" "text=$*"; printf '\033[0;32m✓\033[0m %s\n' "$*"; }
necro_warn() { necro_log_event "message" "warning" "text=$*"; printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
necro_err()  { necro_log_event "message" "error" "text=$*"; printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
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
