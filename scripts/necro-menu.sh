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

SNAP_DIR="$(necro_snapshot_dir)"

# ── helpers ──────────────────────────────────────────────────────────────────

list_snapshots() {
  /bin/ls -t "$SNAP_DIR"/*.idle-only.jsonl 2>/dev/null
}

snapshot_summary() {
  local f="$1"
  local ts records agents
  ts="$(basename "$f" .idle-only.jsonl | sed 's/T/ /' | sed 's/-/:/4' | sed 's/-/:/4')"
  records="$(wc -l < "$f" | tr -d ' ')"
  agents="$(grep -o '"agent":"[^"]*"' "$f" 2>/dev/null | grep -v '""' | sort | uniq -c | tr '\n' ' ' || echo '')"
  printf '  %-28s  %3s records  %s\n' "$ts" "$records" "$agents"
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
  necro_hr
  necro_say "Existing snapshots"
  local snaps
  snaps="$(list_snapshots)"
  if [ -z "$snaps" ]; then
    echo "  No snapshots found in $SNAP_DIR"
    return
  fi
  local i=1
  while IFS= read -r f; do
    printf '  [%2d] ' "$i"
    snapshot_summary "$f"
    i=$(( i + 1 ))
  done <<< "$snaps"
  echo ""
  echo "  Total: $(echo "$snaps" | wc -l | tr -d ' ') snapshots in $SNAP_DIR"
}

action_resume_backup() {
  necro_hr
  necro_say "Resume a specific snapshot"
  local snaps
  snaps="$(list_snapshots)"
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
  local idx=$(( pick - 1 ))
  local chosen="${snap_arr[$idx]:-}"
  [ -z "$chosen" ] && { necro_warn "Invalid choice."; return; }

  echo ""
  necro_say "Dry-run preview:"
  "$SELF_DIR/necro-restore.sh" --dry-run "$chosen"
  echo ""
  printf 'Restore this snapshot? [y/N] '
  read -r confirm
  case "$confirm" in
    y|Y)
      if [ -n "${TMUX:-}" ]; then
        necro_warn "You're inside tmux — restore will add windows to existing sessions."
      fi
      "$SELF_DIR/necro-restore.sh" "$chosen"
      ;;
    *) necro_say "Cancelled." ;;
  esac
}

action_cleanup_backups() {
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
      to_delete="$(echo "$snaps" | tail -n "+$(( keep + 1 ))")"
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
      done <<< "$snaps"
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
      to_delete="$(echo "$snaps" | tail -n +2)"
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

# ── main loop ─────────────────────────────────────────────────────────────────

while true; do
  necro_hr
  necro_say "tmux-ai-necromancer"
  echo "  Snapshot dir: $SNAP_DIR"
  local_count="$(list_snapshots | wc -l | tr -d ' ')"
  echo "  Snapshots:    $local_count"
  echo ""
  echo "  [1] List backups"
  echo "  [2] Resume a specific backup"
  echo "  [3] Cleanup backups"
  echo "  [4] Reboot / shutdown prep"
  echo "  [0] Exit"
  necro_hr
  printf 'Choice: '
  read -r main_choice

  case "$main_choice" in
    1) action_list_backups ;;
    2) action_resume_backup ;;
    3) action_cleanup_backups ;;
    4) action_reboot_prep ;;
    0|"") echo ""; break ;;
    *) necro_warn "Invalid choice." ;;
  esac
done
