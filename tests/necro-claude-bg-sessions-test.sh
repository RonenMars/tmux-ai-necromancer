#!/usr/bin/env bash
# Claude background sessions (`claude --bg`) have no pane, so the pane walk
# never saw them (#73). The snapshot records each LIVE one as a pane-less
# `"kind":"bg"` record, and restore relaunches only those whose process is
# gone, via `claude --bg --resume <id>` in the record's cwd. A rerun after the
# relaunch starts nothing.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NECROMANCER_SNAPSHOT_DIR="$TMP/snap" NECROMANCER_RESUME_MESSAGE="" \
  NECROMANCER_RESUME_START_DELAY=0 NECROMANCER_RESUME_DELAY=0
S="$HOME/.claude/sessions"
mkdir -p "$S" "$NECROMANCER_SNAPSHOT_DIR" "$TMP/bin" "$TMP/live" "$TMP/dead" "$TMP/inter"
CALLS="$TMP/claude.calls"; : > "$CALLS"
LIVE=11111111-aaaa-4bbb-8ccc-000000000001
DEAD=22222222-aaaa-4bbb-8ccc-000000000002
INTER=33333333-aaaa-4bbb-8ccc-000000000003
sleep 0 & DEAD_PID=$!; wait "$DEAD_PID"

session_file() { # pid id kind cwd name [parkedJobId tmux]
  printf '{"pid":%s,"sessionId":"%s","kind":"%s","cwd":"%s","name":"%s","jobId":"%s","parkedJobId":"%s","tmux":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "${2:0:8}" "${6:-}" "${7:-}" > "$S/$1.json"
}
session_file "$$"        "$LIVE"  bg          "$TMP/live"  "live job"
session_file "$DEAD_PID" "$DEAD"  bg          "$TMP/dead"  "dead job"
session_file 1           "$INTER" interactive "$TMP/inter" "pane" "${LIVE:0:8}" "s:@1.%7"

cat > "$TMP/bin/tmux" <<'EOF'
#!/usr/bin/env bash
# LIMITED=1 serves one claude pane showing the limit banner, so a
# --rate-limited capture really writes its file.
case "$1" in
  has-session) exit 1 ;;
  list-panes) [ "${LIMITED:-}" = 1 ] && printf '%%1\ts\t1\tw\t%s\tclaude\tL\t0\t1\t1\t1\n' "$PWD" ;;
  capture-pane) [ "${LIMITED:-}" = 1 ] && printf "You've hit your session limit\n" ;;
esac
exit 0
EOF
# The stub claude logs its cwd and argv, then registers the woken session as
# live, the way the real one writes ~/.claude/sessions/<pid>.json.
cat > "$TMP/bin/claude" <<EOF
#!/usr/bin/env bash
echo "\$PWD \$*" >> "$CALLS"
printf '{"pid":$$,"sessionId":"%s","kind":"bg","cwd":"%s"}\n' "\$3" "\$PWD" > "$S/woken.json"
EOF
chmod +x "$TMP/bin/"*; export PATH="$TMP/bin:$PATH"

fail=0
check() { [ "$2" = "$3" ] && echo "  ok: $1" || { echo "  FAIL: $1 (want '$2' got '$3')"; fail=1; }; }

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >"$TMP/snap.out" 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl 2>/dev/null | head -1)"
check "snapshot: one bg record per live bg session" 1 "$(jq -s '[.[] | select(.kind=="bg")] | length' "$OUT" 2>/dev/null)"
check "snapshot: bg record carries the session id" "$LIVE" "$(jq -r 'select(.kind=="bg") | .uuid' "$OUT" 2>/dev/null)"
check "snapshot: bg record carries agent, cwd, name" "claude $TMP/live live job" \
  "$(jq -r 'select(.kind=="bg") | "\(.agent) \(.cwd) \(.window_name)"' "$OUT" 2>/dev/null)"
check "snapshot: bg record names the parked parent pane" "%7" "$(jq -r 'select(.kind=="bg") | .parent_pane' "$OUT" 2>/dev/null)"

check "doctor: bg records are not counted as pane agents" 1 \
  "$(bash "$ROOT/scripts/necro-doctor.sh" 2>&1 | grep -c '1 record(s), 0 with an agent, 0 with a UUID')"

# Restore from a snapshot holding both: the live one must be left alone.
cat > "$TMP/s.jsonl" <<EOF
{"kind":"bg","pane_id":"","session":"","window_index":0,"window_name":"live job","cwd":"$TMP/live","agent":"claude","uuid":"$LIVE","uuid_source":"claude-bg"}
{"kind":"bg","pane_id":"","session":"","window_index":0,"window_name":"dead job","cwd":"$TMP/dead","agent":"claude","uuid":"$DEAD","uuid_source":"claude-bg"}
EOF
bash "$ROOT/scripts/necro-restore.sh" --dry-run "$TMP/s.jsonl" >"$TMP/dry.out" 2>&1
check "dry-run: launches nothing" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
check "dry-run: prints the dead session's relaunch" 1 "$(grep -c "DRY: .*claude --bg --resume $DEAD" "$TMP/dry.out")"

bash "$ROOT/scripts/necro-restore.sh" --only '/nowhere/*' "$TMP/s.jsonl" >/dev/null 2>&1
check "--only: a non-matching selector launches nothing" 0 "$(wc -l < "$CALLS" | tr -d ' ')"

bash "$ROOT/scripts/necro-restore.sh" "$TMP/s.jsonl" >"$TMP/r1.out" 2>&1
check "restore: relaunches only the dead session, in its cwd" "$TMP/dead --bg --resume $DEAD" "$(cat "$CALLS")"
check "restore: summary counts the relaunch" 1 "$(grep -c 'agents resumed: 1' "$TMP/r1.out")"

: > "$CALLS"
bash "$ROOT/scripts/necro-restore.sh" "$TMP/s.jsonl" >"$TMP/r2.out" 2>&1
check "rerun: relaunches nothing" 0 "$(wc -l < "$CALLS" | tr -d ' ')"

# --rate-limited captures only limited panes; it must not add bg records.
LIMITED=1 bash "$ROOT/scripts/necro-snapshot.sh" --rate-limited >/dev/null 2>&1
RL="$(/bin/ls "$NECROMANCER_SNAPSHOT_DIR"/*.rate-limited.jsonl 2>/dev/null | head -1)"
check "rate-limited: capture written" 1 "$(grep -c '"pane_id":"%1"' "$RL" 2>/dev/null)"
check "rate-limited: no bg records" 0 "$(grep -c '"kind":"bg"' "$RL" 2>/dev/null)"

[ "$fail" = 0 ] && echo PASS || { echo FAILED; cat "$TMP/r1.out"; exit 1; }
