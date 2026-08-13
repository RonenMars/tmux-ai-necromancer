#!/usr/bin/env bash
# necro-restore-only-filter-test.sh — `--only <selectors>` restores exactly the
# named records and leaves the rest of the snapshot alone.
#
# Restore was all-or-nothing: you took the whole snapshot or nothing. --only
# narrows it to a subset so "bring back just these panes" is expressible.
#
# Selectors dispatch on shape, which is unambiguous because the three forms are
# syntactically disjoint:
#   %14                                     -> pane_id
#   1ec9e206-5619-418f-8556-72433fb60181    -> uuid
#   /path or *glob*                         -> cwd
#
# The filter must run BEFORE the group bookkeeping, so an unselected record
# contributes nothing at all: no window, no resume, and no entry in the pane
# counts the layout replay is guarded by.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"
CWD1="$TMP/alpha"; CWD2="$TMP/beta"; CWD3="$TMP/gamma"
mkdir -p "$CWD1" "$CWD2" "$CWD3"

U1="11111111-1111-4111-8111-111111111111"
U2="22222222-2222-4222-8222-222222222222"
U3="33333333-3333-4333-8333-333333333333"

SESS_FLAG="$TMP/created"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session)  [ -f "$SESS_FLAG" ] && exit 0 || exit 1 ;;
  new-session)  : > "$SESS_FLAG"; exit 0 ;;
  list-windows) printf '' ;;
  list-panes)   printf '' ;;
  new-window)   printf '@10\n' ;;
  split-window) printf '%%20\n' ;;
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w1","cwd":"$CWD1","prev_cmd":"claude","agent":"claude","uuid":"$U1","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w2","cwd":"$CWD2","prev_cmd":"claude","agent":"claude","uuid":"$U2","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%3","session":"s","window_index":3,"window_name":"w3","cwd":"$CWD3","prev_cmd":"claude","agent":"claude","uuid":"$U3","uuid_source":"pane-option","window_layout":"","zoomed":0,"pane_active":0,"window_active":0,"captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

fails=0

# run_only <selectors> — restore with that filter, return the resumed uuid list.
run_only() {
  : > "$CALLS"; rm -f "$SESS_FLAG"
  bash "$ROOT/scripts/necro-restore.sh" "$SNAP" \
    --only "$1" --resume-delay 0 --resume-message '' >/dev/null 2>&1
  grep '^send-keys ' "$CALLS" | grep -o '[0-9a-f]\{8\}-[0-9a-f-]*' | sort | tr '\n' ' '
}

expect() { # expect <label> <selectors> <want resumed uuids, space-separated+trailing>
  local label="$1" sel="$2" want="$3" got
  got="$(run_only "$sel")"
  if [ "$got" = "$want" ]; then
    echo "  ok: $label"
  else
    echo "  FAIL: $label"
    echo "        selectors: $sel"
    echo "        want resumed: '$want'"
    echo "        got  resumed: '$got'"
    fails=$((fails + 1))
  fi
}

echo "selector shapes"
expect "pane_id selects one record"      "%2"          "$U2 "
expect "uuid selects one record"         "$U3"         "$U3 "
expect "cwd selects one record"          "$CWD1"       "$U1 "
expect "cwd glob selects one record"     '*/beta'      "$U2 "

echo
echo "lists and misses"
expect "comma-separated list, mixed shapes" "%1,$U3"   "$U1 $U3 "
expect "no match resumes nothing"           "%99"      ""

echo
echo "no --only restores everything (unchanged behaviour)"
: > "$CALLS"; rm -f "$SESS_FLAG"
bash "$ROOT/scripts/necro-restore.sh" "$SNAP" \
  --resume-delay 0 --resume-message '' >/dev/null 2>&1
got="$(grep '^send-keys ' "$CALLS" | grep -o '[0-9a-f]\{8\}-[0-9a-f-]*' | sort | tr '\n' ' ')"
if [ "$got" = "$U1 $U2 $U3 " ]; then
  echo "  ok: all three resumed"
else
  echo "  FAIL: bare run should resume all three"
  echo "        want: '$U1 $U2 $U3 '"
  echo "        got : '$got'"
  fails=$((fails + 1))
fi

echo
echo "an unselected record builds nothing"
# Comparative, so it can't pass vacuously when the run dies early: a 1-record
# selection must build strictly fewer panes than the unfiltered 3-record run.
# Sets BUILT and RC as globals — a $( ) capture would run this in a subshell
# and RC would never make it back out.
BUILT=0; RC=0
panes_built() {
  : > "$CALLS"; rm -f "$SESS_FLAG"
  bash "$ROOT/scripts/necro-restore.sh" "$SNAP" "$@" \
    --resume-delay 0 --resume-message '' >/dev/null 2>&1
  RC=$?
  BUILT=$(grep -c -e '^new-window' -e '^split-window' "$CALLS" || true)
}
panes_built;              full="$BUILT"
panes_built --only "%2";  one="$BUILT"; one_rc="$RC"
if [ "$one_rc" -ne 0 ]; then
  echo "  FAIL: --only run exited $one_rc (flag rejected?)"
  fails=$((fails + 1))
elif [ "$full" -gt 0 ] && [ "$one" -lt "$full" ]; then
  echo "  ok: 1-record selection built $one pane(s) vs $full unfiltered"
else
  echo "  FAIL: selection did not reduce what was built"
  echo "        unfiltered built: $full   --only %2 built: $one"
  fails=$((fails + 1))
fi

[ "$fails" -gt 0 ] && { echo "FAILED ($fails)"; exit 1; }
echo "PASS: necro-restore-only-filter-test"
