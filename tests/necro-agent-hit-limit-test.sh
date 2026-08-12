#!/usr/bin/env bash
# agent_*_hit_limit detects Claude session-limit and Codex usage-limit banners
# from pane scrollback (the messages shown when a quota is exhausted).
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TMPBIN="$TMP/bin"
mkdir -p "$TMPBIN"

SCROLLBACK="$TMP/scrollback.txt"
: > "$SCROLLBACK"

cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  capture-pane) cat "$SCROLLBACK"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/agents/claude.sh
. "$ROOT/lib/agents/claude.sh"
# shellcheck source=../lib/agents/codex.sh
. "$ROOT/lib/agents/codex.sh"

fail=0

# --- Claude: session limit banner (screenshot wording) ----------------------
cat > "$SCROLLBACK" <<'EOF'
Worked for 57s
You've hit your session limit · resets 12:40pm (Asia/Jerusalem)
>
EOF
if ! agent_claude_hit_limit '%1'; then
  echo "FAIL: claude should detect 'hit your session limit'" >&2
  fail=1
fi
if agent_codex_hit_limit '%1'; then
  echo "FAIL: codex must NOT match Claude's session-limit banner" >&2
  fail=1
fi

# --- Codex: hard usage-limit banner (screenshot wording) --------------------
cat > "$SCROLLBACK" <<'EOF'
Stop hook (failed) error: hook returned invalid stop hook JSON output
You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Aug 18th, 2026 6:37 AM.
>
EOF
if ! agent_codex_hit_limit '%1'; then
  echo "FAIL: codex should detect 'hit your usage limit'" >&2
  fail=1
fi
if agent_claude_hit_limit '%1'; then
  echo "FAIL: claude must NOT match Codex's usage-limit banner" >&2
  fail=1
fi

# --- Codex: "Approaching rate limits" switch-model dialog -------------------
cat > "$SCROLLBACK" <<'EOF'
You've hit your usage limit. Upgrade to Pro …
Approaching rate limits
Switch to gpt-5.6-luna for lower credit usage?
› 1. Switch to gpt-5.6-luna
  2. Keep current model
  3. Keep current model (never show again)
EOF
if ! agent_codex_hit_limit '%1'; then
  echo "FAIL: codex should detect 'Approaching rate limits' dialog" >&2
  fail=1
fi

# --- Codex: approaching dialog alone (hard banner scrolled off) -------------
cat > "$SCROLLBACK" <<'EOF'
Approaching rate limits
Switch to gpt-5.6-luna for lower credit usage?
› 1. Switch to gpt-5.6-luna
  2. Keep current model
EOF
if ! agent_codex_hit_limit '%1'; then
  echo "FAIL: codex should detect approaching-limits dialog without hard banner" >&2
  fail=1
fi

# --- Normal agent output: neither matches -----------------------------------
cat > "$SCROLLBACK" <<'EOF'
I'll start by reading the necro design skill.
Ran 1 shell command
>
EOF
if agent_claude_hit_limit '%1'; then
  echo "FAIL: claude matched normal scrollback" >&2
  fail=1
fi
if agent_codex_hit_limit '%1'; then
  echo "FAIL: codex matched normal scrollback" >&2
  fail=1
fi

# --- Codex warning only (<10% left) is NOT a hard limit hit -----------------
cat > "$SCROLLBACK" <<'EOF'
⚠ Heads up, you have less than 10% of your weekly limit left. Run /status for a breakdown.
› continue
EOF
if agent_codex_hit_limit '%1'; then
  echo "FAIL: codex must NOT treat 'less than 10% left' warning as a limit hit" >&2
  fail=1
fi

[ "$fail" = 0 ] && echo "PASS: necro-agent-hit-limit-test" || exit 1
