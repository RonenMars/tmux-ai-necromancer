#!/usr/bin/env bash
# Snapshot has sessions "1" and "dotfiles"; a hook renames the new "1" to
# "dotfiles". The snapshot's real "dotfiles" must NOT merge into it (it gets
# its own session), and a failed tag must warn instead of failing silently.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" NECROMANCER_RESUME_MESSAGE="" NECROMANCER_RESUME_START_DELAY=0
mkdir -p "$HOME" "$TMP/bin" "$TMP/a" "$TMP/b"
CALLS="$TMP/calls.log"; SESS="$TMP/sessions"; : > "$SESS"   # lines: id<TAB>name<TAB>tag
U1="11111111-1111-1111-1111-111111111111"; U2="22222222-2222-2222-2222-222222222222"

# Fake tmux with real session state. new-session -s 1 is "renamed" to dotfiles
# by the hook; a duplicate name fails like the real thing.
cat > "$TMP/bin/tmux" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
S="$SESS"
name_of_arg() { while [ \$# -gt 0 ]; do [ "\$1" = -s ] && { echo "\$2"; return; }; shift; done; }
case "\$1" in
  has-session) n="\${3#=}"; cut -f2 "\$S" | grep -qxF "\$n" ;;
  new-session)
    n="\$(name_of_arg "\$@")"; cut -f2 "\$S" | grep -qxF "\$n" && { echo "duplicate session: \$n" >&2; exit 1; }
    id="\\\$\$(( \$(wc -l < "\$S") + 1 ))"
    [ "\$n" = 1 ] && n=dotfiles
    printf '%s\t%s\t\n' "\$id" "\$n" >> "\$S"; echo "\$id" ;;
  set-option)
    [ -n "\${TAGFAIL:-}" ] && exit 1
    awk -F'\t' -v OFS='\t' -v id="\$3" -v tag="\$5" '\$1==id{\$3=tag}1' "\$S" > "\$S.n" && mv "\$S.n" "\$S" ;;
  list-sessions) awk -F'\t' '{print \$3 "\t" \$2}' "\$S" ;;
  list-windows) printf '@30\n' ;;
  list-panes)
    case " \$* " in
      *' -t =dotfiles: '*) printf '%%30\n' ;;
      *' -t =dotfiles-restored: '*) printf '%%31\n' ;;
      *) exit 1 ;;
    esac ;;
  display-message) printf 'zsh\n' ;;
esac
exit \$?
EOS
chmod +x "$TMP/bin/tmux"; export PATH="$TMP/bin:$PATH"

SNAP="$TMP/s.jsonl"
rec() { printf '{"pane_id":"%%%s","session":"%s","window_index":1,"window_name":"w","cwd":"%s","prev_cmd":"codex","agent":"codex","uuid":"%s","uuid_source":"x","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' "$1" "$2" "$3" "$4"; }
{ rec 1 1 "$TMP/a" "$U1"; rec 2 dotfiles "$TMP/b" "$U2"; } > "$SNAP"

fails=0
bad() { echo "FAIL: $1" >&2; fails=$((fails+1)); }
bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
[ "$(wc -l < "$SESS" | tr -d ' ')" = 2 ] || bad "expected 2 sessions, got: $(cat "$SESS")"
grep -qF 'new-session -d -s dotfiles-restored' "$CALLS" || bad "real dotfiles session not created under a free name"
grep -qF "send-keys -t %30 codex resume $U1" "$CALLS" || bad "first resume not sent to the renamed session"
grep -qF "send-keys -t %31 codex resume $U2" "$CALLS" || bad "second resume merged into the renamed session"
n="$(grep -c '^new-session' "$CALLS")"
bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
[ "$(grep -c '^new-session' "$CALLS")" = "$n" ] || bad "rerun created another session"

# A failed tag is reported, not swallowed.
: > "$SESS"; : > "$CALLS"
out="$(TAGFAIL=1 bash "$ROOT/scripts/necro-restore.sh" "$SNAP" 2>&1)"
echo "$out" | grep -q "could not tag session" || bad "failed tag produced no warning"

[ "$fails" -eq 0 ] || { cat "$CALLS" >&2; exit 1; }
echo "PASS: renamed-session collision and tag failure"
