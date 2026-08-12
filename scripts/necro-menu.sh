#!/usr/bin/env bash
# necro-menu.sh — interactive management menu for tmux-ai-necromancer.
#
# Usage: necro-menu.sh
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
necro_init_log "$0"

SNAP_DIR="$(necro_snapshot_dir)"
POINTER="$SNAP_DIR/latest-for-reboot"

# ── helpers ──────────────────────────────────────────────────────────────────

# Fully-resolved path of the snapshot pinned as the reboot target ("" if none).
# Resolve BOTH sides before comparing: on macOS `readlink -f` reports
# /private/var/... while `ls` yields /var/... for the same file, so a raw
# string compare silently fails to recognize the pin.
resolve_path() {
  [ -n "${1:-}" ] || return 0
  readlink -f "$1" 2>/dev/null || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || printf '%s' "$1"
}

pinned_snapshot() {
  [ -e "$POINTER" ] || return 0
  resolve_path "$POINTER"
}

# Drop the pinned reboot snapshot from a newline-separated delete list.
# Autosave rotation already refuses to rotate it away; the menu's cleanup must
# honor the same pin or a later reboot-resume finds a dangling pointer.
filter_pinned() {
  local pinned; pinned="$(pinned_snapshot)"
  if [ -z "$pinned" ]; then cat; return; fi
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(resolve_path "$f")" = "$pinned" ]; then
      necro_warn "keeping pinned reboot snapshot: $(basename "$f")"
      continue
    fi
    printf '%s\n' "$f"
  done
}

list_snapshots() {
  /bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null
}

list_all_snapshots() {
  /bin/ls -t "$SNAP_DIR"/*.jsonl 2>/dev/null
}

snapshot_summary() {
  local f="$1"
  local name records agents kind ts
  name="$(basename "$f" .jsonl)"
  # detect kind from suffix
  case "$name" in
    *.idle-only)    kind="autosave "; ts="${name%.idle-only}" ;;
    *.rate-limited) kind="rate-lim "; ts="${name%.rate-limited}" ;;
    *.enriched)     kind="reboot  "; ts="${name%.enriched}" ;;
    *)              kind="snapshot"; ts="$name" ;;
  esac
  ts="$(printf '%s' "$ts" | sed 's/T/ /' | sed 's/-/:/4' | sed 's/-/:/4')"
  records="$(wc -l < "$f" | tr -d ' ')"
  sessions="$(grep -o '"session":"[^"]*"' "$f" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  agents="$(grep -o '"agent":"[^"]*"' "$f" 2>/dev/null | grep -v '""' | sort | uniq -c | tr '\n' ' ' || echo '')"
  printf '  %-10s  %-24s  %2s sessions  %3s panes  %s\n' "$kind" "$ts" "$sessions" "$records" "$agents"
}

prompt_choice() {
  local prompt="$1"; shift
  local options=("$@")
  local i=1
  echo ""
  for opt in "${options[@]}"; do
    printf '  [%d] %s\n' "$i" "$opt"
    i=$(( i + 1 ))
  done
  printf '  [0] Back\n\n'
  printf '%s ' "$prompt"
  read -r choice
  echo "$choice"
}

# ── actions ──────────────────────────────────────────────────────────────────

action_list_backups() {
  necro_log_event "menu" "list_backups" "snapshot_dir=$SNAP_DIR"
  necro_hr
  necro_say "Existing snapshots"
  local snaps pointer="$SNAP_DIR/latest-for-reboot"
  snaps="$(list_all_snapshots)"
  if [ -z "$snaps" ]; then
    echo "  No snapshots found in $SNAP_DIR"
    return
  fi
  local i=1
  while IFS= read -r f; do
    local marker="   "
    [ -e "$pointer" ] && [ "$(readlink -f "$pointer" 2>/dev/null || cat "$pointer")" = "$f" ] && marker="(*)"
    printf '  [%2d]%s ' "$i" "$marker"
    snapshot_summary "$f"
    i=$(( i + 1 ))
  done <<< "$snaps"
  echo ""
  echo "  Total: $(echo "$snaps" | wc -l | tr -d ' ') snapshots in $SNAP_DIR"
  [ -e "$pointer" ] && echo "  (*) = pinned reboot target"
}

action_resume_backup() {
  necro_log_event "menu" "resume_backup" "snapshot_dir=$SNAP_DIR"
  necro_hr
  necro_say "Resume a specific snapshot"
  local snaps
  snaps="$(list_all_snapshots)"
  if [ -z "$snaps" ]; then
    echo "  No snapshots found."; return
  fi

  local i=1
  local snap_arr=()
  while IFS= read -r f; do
    snap_arr+=("$f")
    printf '  [%2d] ' "$i"
    snapshot_summary "$f"
    i=$(( i + 1 ))
  done <<< "$snaps"
  printf '  [0]  Back\n\n'
  printf 'Pick snapshot number: '
  read -r pick
  [ "$pick" = "0" ] || [ -z "$pick" ] && return
  [[ "$pick" =~ ^[0-9]+$ ]] || { necro_warn "Invalid number."; return; }
  local idx=$(( pick - 1 ))
  local chosen="${snap_arr[$idx]:-}"
  [ -z "$chosen" ] && { necro_warn "Invalid choice."; return; }

  echo ""
  necro_say "Dry-run preview:"
  "$SELF_DIR/necro-restore.sh" --dry-run "$chosen"

  # Show current tmux state and offer to clean up before restoring.
  echo ""
  necro_say "Current tmux sessions:"
  tmux list-sessions 2>/dev/null | while IFS= read -r sess_line; do
    local sess_name
    sess_name="$(printf '%s' "$sess_line" | cut -d: -f1)"
    printf '  %-30s\n' "$sess_line"
    tmux list-windows -t "=$sess_name" -F "      #{window_index}: #{window_name}" 2>/dev/null
  done
  echo ""
  printf 'Kill ALL current tmux sessions before restoring? [y/N] '
  read -r kill_confirm
  case "$kill_confirm" in
    y|Y)
      necro_say "Killing all sessions..."
      tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
        tmux kill-session -t "=$s" 2>/dev/null && echo "  killed: $s"
      done
      necro_ok "All sessions killed."
      ;;
    *) necro_say "Keeping existing sessions — restore will add windows alongside them." ;;
  esac

  echo ""
  printf 'Restore this snapshot? [y/N] '
  read -r confirm
  case "$confirm" in
    y|Y) "$SELF_DIR/necro-restore.sh" "$chosen" ;;
    *) necro_say "Cancelled." ;;
  esac
}

action_cleanup_backups() {
  necro_log_event "menu" "cleanup_backups" "snapshot_dir=$SNAP_DIR"
  necro_hr
  necro_say "Cleanup snapshots"
  local snaps
  snaps="$(list_snapshots)"
  if [ -z "$snaps" ]; then
    echo "  No snapshots found."; return
  fi

  local total
  total="$(echo "$snaps" | wc -l | tr -d ' ')"
  echo "  $total snapshots in $SNAP_DIR"
  echo ""
  echo "  [1] Keep newest N (enter count)"
  echo "  [2] Delete older than N days"
  echo "  [3] Delete all except newest"
  echo "  [0] Back"
  echo ""
  printf 'Choice: '
  read -r mode

  case "$mode" in
    1)
      printf 'Keep how many newest snapshots? '
      read -r keep
      [[ "$keep" =~ ^[0-9]+$ ]] || { necro_warn "Invalid number."; return; }
      local to_delete
      to_delete="$(echo "$snaps" | tail -n "+$(( keep + 1 ))" | filter_pinned)"
      if [ -z "$to_delete" ]; then
        echo "  Nothing to delete (have $total, keeping $keep)."; return
      fi
      echo ""
      echo "  Will delete:"
      echo "$to_delete" | while IFS= read -r f; do echo "    $(basename "$f")"; done
      echo ""
      printf 'Confirm delete? [y/N] '
      read -r confirm
      case "$confirm" in
        y|Y)
          echo "$to_delete" | while IFS= read -r f; do rm -f "$f" && echo "  deleted: $(basename "$f")"; done
          necro_ok "Done."
          ;;
        *) necro_say "Cancelled." ;;
      esac
      ;;
    2)
      printf 'Delete snapshots older than how many days? '
      read -r days
      [[ "$days" =~ ^[0-9]+$ ]] || { necro_warn "Invalid number."; return; }
      local cutoff=$(( $(date +%s) - days * 86400 ))
      local to_delete=()
      while IFS= read -r f; do
        local mtime
        mtime="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
        [ -n "$mtime" ] && [ "$mtime" -lt "$cutoff" ] && to_delete+=("$f")
      done <<< "$(echo "$snaps" | filter_pinned)"
      if [ "${#to_delete[@]}" -eq 0 ]; then
        echo "  No snapshots older than $days days."; return
      fi
      echo ""
      echo "  Will delete ${#to_delete[@]} snapshot(s):"
      for f in "${to_delete[@]}"; do echo "    $(basename "$f")"; done
      echo ""
      printf 'Confirm delete? [y/N] '
      read -r confirm
      case "$confirm" in
        y|Y) for f in "${to_delete[@]}"; do rm -f "$f" && echo "  deleted: $(basename "$f")"; done; necro_ok "Done." ;;
        *) necro_say "Cancelled." ;;
      esac
      ;;
    3)
      local newest
      newest="$(echo "$snaps" | head -1)"
      local to_delete
      to_delete="$(echo "$snaps" | tail -n +2 | filter_pinned)"
      if [ -z "$to_delete" ]; then
        echo "  Only one snapshot exists — nothing to delete."; return
      fi
      echo ""
      echo "  Keeping: $(basename "$newest")"
      echo "  Will delete $(echo "$to_delete" | wc -l | tr -d ' ') snapshot(s)."
      echo ""
      printf 'Confirm delete? [y/N] '
      read -r confirm
      case "$confirm" in
        y|Y)
          echo "$to_delete" | while IFS= read -r f; do rm -f "$f" && echo "  deleted: $(basename "$f")"; done
          necro_ok "Done."
          ;;
        *) necro_say "Cancelled." ;;
      esac
      ;;
    0|"") return ;;
    *) necro_warn "Invalid choice." ;;
  esac
}

action_reboot_prep() {
  necro_log_event "menu" "reboot_prep" "snapshot_dir=$SNAP_DIR"
  necro_hr
  necro_say "Reboot / shutdown prep"
  echo ""
  echo "  [1] Prep + reboot    (snapshot all sessions → sudo reboot)"
  echo "  [2] Prep + shutdown  (snapshot all sessions → sudo shutdown -h now)"
  echo "  [3] Prep only        (snapshot, no OS action)"
  echo "  [0] Back"
  echo ""
  printf 'Choice: '
  read -r choice

  case "$choice" in
    1)
      printf 'Reboot after snapshot? [y/N] '
      read -r confirm
      case "$confirm" in
        y|Y) "$SELF_DIR/necro-reboot-prep.sh" && sudo reboot ;;
        *) necro_say "Cancelled." ;;
      esac
      ;;
    2)
      printf 'Shutdown after snapshot? [y/N] '
      read -r confirm
      case "$confirm" in
        y|Y) "$SELF_DIR/necro-reboot-prep.sh" && sudo shutdown -h now ;;
        *) necro_say "Cancelled." ;;
      esac
      ;;
    3) "$SELF_DIR/necro-reboot-prep.sh" ;;
    0|"") return ;;
    *) necro_warn "Invalid choice." ;;
  esac
}

action_save_rate_limited() {
  necro_log_event "menu" "save_rate_limited" "snapshot_dir=$SNAP_DIR"
  necro_hr
  necro_say "Save rate-limited sessions"
  echo ""
  echo "  Captures only panes whose scrollback shows a Claude session-limit"
  echo "  or Codex usage-limit banner. Idle-only — no exit keys sent."
  echo ""
  "$SELF_DIR/necro-snapshot.sh" --rate-limited || true
}

# ── main loop ─────────────────────────────────────────────────────────────────

while true; do
  necro_hr
  necro_say "tmux-ai-necromancer"
  echo "  Snapshot dir: $SNAP_DIR"
  local_count="$(list_all_snapshots | wc -l | tr -d ' ')"
  echo "  Snapshots:    $local_count"
  echo ""
  echo "  [1] List backups"
  echo "  [2] Resume a specific backup"
  echo "  [3] Cleanup backups"
  echo "  [4] Reboot / shutdown prep"
  echo "  [5] Diagnose (health check)"
  echo "  [6] Save rate-limited sessions"
  echo "  [0] Exit"
  necro_hr
  printf 'Choice: '
  read -r main_choice

  case "$main_choice" in
    1) action_list_backups ;;
    2) action_resume_backup ;;
    3) action_cleanup_backups ;;
    4) action_reboot_prep ;;
    5) "$SELF_DIR/necro-doctor.sh" || true ;;
    6) action_save_rate_limited ;;
    0|"") echo ""; break ;;
    *) necro_warn "Invalid choice." ;;
  esac
done
