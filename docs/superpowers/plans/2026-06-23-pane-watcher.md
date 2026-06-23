# Pane Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-tick pane watcher that pins a UUID to each agent pane the moment it's detected, so autosave no longer relies on mtime-ordering heuristics for multi-session cwds.

**Architecture:** A new `necro-watch.sh` runs every status-interval (5s) via `status-right`. It walks panes, pins `@necro_uuid` + `@necro_cmd` on newly-detected agent panes, detects exits (command changed away from agent), and scrapes the farewell UUID from scrollback on exit. `necro-snapshot.sh` reads `@necro_uuid` first and only falls back to the cursor when unset. `agent_<name>_matches` is extended to accept a configurable command list so aliases like `cc` work.

**Tech Stack:** bash, tmux pane/window options, existing `lib/agents.sh` + `lib/common.sh`

## Global Constraints

- `set -uo pipefail` — NOT `set -euo`. Pipelines legitimately exit non-zero on no-match; guard with `|| true`.
- No new runtime dependencies (bash, tmux, python3, jq only).
- All scripts must be path-agnostic (resolve via `${BASH_SOURCE[0]}` + symlink follow).
- Pane options (`-p`) not window options (`-w`) — they die with the pane.
- `@necromancer_claude_commands` tmux option: space-separated list of command names that count as Claude Code (default `claude`).
- POSIX rotation loops (no `mapfile`) — tmux evaluates `status-right` via `/bin/sh`.
- Every new tmux option must have a `set_default` call in `tmux-ai-necromancer.tmux`.

---

### Task 1: Configurable command matching in `agent_claude_matches`

Fixes the `cc` alias problem. `agent_claude_matches` currently hardcodes `[ "$1" = "claude" ]`. We replace it with a check against a tmux option list.

**Files:**
- Modify: `lib/agents/claude.sh`
- Modify: `tmux-ai-necromancer.tmux`

**Interfaces:**
- Produces: `agent_claude_matches "$cmd"` — returns 0 if `$cmd` is in the space-separated `@necromancer_claude_commands` tmux option (default `claude`)

- [ ] **Step 1: Add `set_default` for the new option in the TPM entrypoint**

In `tmux-ai-necromancer.tmux`, after the existing `set_default` block:

```bash
set_default "@necromancer_claude_commands" "claude"
```

- [ ] **Step 2: Replace `agent_claude_matches` in `lib/agents/claude.sh`**

```bash
# Does this pane's foreground command belong to Claude Code?
# Checks against @necromancer_claude_commands (space-separated, default "claude").
agent_claude_matches() {
  local cmd="$1" name
  local cmds
  cmds="$(tmux show-option -gqv @necromancer_claude_commands 2>/dev/null)"
  cmds="${cmds:-claude}"
  for name in $cmds; do
    [ "$cmd" = "$name" ] && return 0
  done
  return 1
}
```

- [ ] **Step 3: Verify manually**

```bash
# In a shell (not inside tmux-ai-necromancer scripts):
source lib/common.sh
source lib/agents/claude.sh

# Should pass:
agent_claude_matches "claude" && echo "PASS: claude" || echo "FAIL"

# Set a custom option in tmux then test:
tmux set-option -gq @necromancer_claude_commands "claude cc"
agent_claude_matches "cc" && echo "PASS: cc" || echo "FAIL"
agent_claude_matches "vim" && echo "FAIL: vim matched" || echo "PASS: vim rejected"

# Restore:
tmux set-option -gq @necromancer_claude_commands "claude"
```

- [ ] **Step 4: Commit**

```bash
git add lib/agents/claude.sh tmux-ai-necromancer.tmux
git commit -m "feat(agents): configurable claude command names via @necromancer_claude_commands"
```

---

### Task 2: Add `agent_claude_scrape_resume_cmd` — detect `--resume <uuid>` in scrollback

Fixes edge case 5: when tmux-resurrect restores a pane running `claude --resume <uuid>`, the command itself is visible in scrollback. We scrape it before falling back to the cursor.

This is a new scrape strategy, separate from the existing `agent_claude_scrape_session_id` (which scrapes the farewell line after exit). This one scrapes the *startup command*.

**Files:**
- Modify: `lib/agents/claude.sh`
- Modify: `lib/agents.sh` (add dispatcher)

**Interfaces:**
- Produces: `agent_claude_scrape_resume_cmd "$pane_id"` — returns UUID if `claude --resume <uuid>` appears in the last 50 lines of scrollback, else ""
- Produces: `necro_agent_scrape_resume_cmd "$agent" "$pane_id"` dispatcher in `agents.sh`

- [ ] **Step 1: Add `agent_claude_scrape_resume_cmd` to `lib/agents/claude.sh`**

Add after `agent_claude_scrape_session_id`:

```bash
# Scrape a UUID from a startup "--resume <uuid>" line in scrollback.
# Used by the watcher when a pane is first detected (resurrect edge case).
agent_claude_scrape_resume_cmd() {
  local pane="$1"
  tmux capture-pane -p -t "$pane" -S -50 2>/dev/null \
    | grep -oE -- "--resume $CLAUDE_UUID_RE" \
    | tail -1 \
    | grep -oE "$CLAUDE_UUID_RE" \
    | head -1
}
```

- [ ] **Step 2: Add dispatcher to `lib/agents.sh`**

Add after `necro_agent_scrape_session_id`:

```bash
necro_agent_scrape_resume_cmd() {
  local agent="$1"; shift
  declare -f "agent_${agent}_scrape_resume_cmd" >/dev/null 2>&1 || return 0
  "agent_${agent}_scrape_resume_cmd" "$@"
}
```

- [ ] **Step 3: Verify manually**

```bash
# In a pane that was started with claude --resume <some-uuid>:
source lib/common.sh
source lib/agents/claude.sh
agent_claude_scrape_resume_cmd "%<your-pane-id>"
# Should print the UUID, or empty if the pane wasn't started with --resume
```

- [ ] **Step 4: Commit**

```bash
git add lib/agents/claude.sh lib/agents.sh
git commit -m "feat(agents): scrape --resume uuid from pane startup scrollback"
```

---

### Task 3: `necro-watch.sh` — the pane watcher

The core new script. Runs every 5s via `status-right`. For each pane:
- **New agent detected** (`_matches` true, `@necro_uuid` unset): scrape for `--resume` hint first (edge case 5), then pop from cursor. Pin `@necro_uuid` + `@necro_cmd` as pane options.
- **Agent exited** (`@necro_cmd` set but current cmd no longer matches): scrape farewell UUID from scrollback, update `@necro_uuid` with confirmed value, set `@necro_agent_exited=1`. Clear `@necro_cmd`.
- **Agent restarted** (`_matches` true, `@necro_agent_exited=1`): clear all three options and re-pin fresh UUID (edge case 1).

Cursor dir for `necro_agent_pop_session_id` must persist across watcher ticks (unlike snapshot which creates a fresh tmpdir). We use a fixed path under the snapshot dir.

**Files:**
- Create: `scripts/necro-watch.sh`
- Modify: `tmux-ai-necromancer.tmux` (wire into status-right)
- Modify: `lib/agents.sh` (expose persistent cursor dir path helper)

**Interfaces:**
- Consumes: `necro_agent_pop_session_id` (Task 0 — already exists), `necro_agent_scrape_resume_cmd` (Task 2), `necro_agent_scrape_session_id` (existing), `necro_agent_for_cmd` (existing)
- Produces: tmux pane options `@necro_uuid`, `@necro_cmd`, `@necro_agent_exited` on each agent pane

- [ ] **Step 1: Add `necro_watch_cursor_dir` helper to `lib/common.sh`**

This gives a stable cursor dir that persists across watcher ticks (reuses snapshot dir):

```bash
# Persistent cursor dir for the watcher (lives next to snapshots, not in /tmp).
necro_watch_cursor_dir() {
  local d
  d="$(necro_snapshot_dir)/.watcher-cursors"
  mkdir -p "$d"
  printf '%s' "$d"
}
```

- [ ] **Step 2: Create `scripts/necro-watch.sh`**

```bash
#!/usr/bin/env bash
# necro-watch.sh — per-tick pane watcher; pins @necro_uuid on agent panes.
#
# Runs every status-interval seconds via status-right. Self-throttles to
# avoid running more than once per second. Zero pane disruption.
#
# Pane options set:
#   @necro_uuid         — confirmed UUID for this pane's agent session
#   @necro_cmd          — the command name that matched (e.g. "claude", "cc")
#   @necro_agent_exited — "1" when the agent has exited cleanly
set -uo pipefail

_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
SELF_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
. "$SELF_DIR/../lib/common.sh"
. "$SELF_DIR/../lib/agents.sh"
necro_load_agents

# Self-throttle: run at most once per second regardless of status-interval.
LAST_WATCH_OPT="@necromancer_last_watch"
now="$(date +%s)"
last="$(necro_tmux_option "$LAST_WATCH_OPT" 0)"
[ "$(( now - last ))" -lt 1 ] && exit 0
tmux set-option -gq "$LAST_WATCH_OPT" "$now"

# Persistent cursor dir (survives across ticks).
export NECRO_CURSOR_DIR
NECRO_CURSOR_DIR="$(necro_watch_cursor_dir)"

# Walk every pane.
while IFS=$'\t' read -r pane_id cmd cwd; do
  [ -z "$pane_id" ] && continue

  pinned_uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
  pinned_cmd="$(tmux show-option -pqv  -t "$pane_id" @necro_cmd  2>/dev/null || true)"
  exited="$(tmux show-option -pqv      -t "$pane_id" @necro_agent_exited 2>/dev/null || true)"

  agent="$(necro_agent_for_cmd "$cmd")"

  # ── Case 1: agent restarted in a pane that previously exited ──────────────
  if [ -n "$agent" ] && [ "$exited" = "1" ]; then
    tmux set-option -pu -t "$pane_id" @necro_uuid          2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd           2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_agent_exited  2>/dev/null || true
    pinned_uuid=""; pinned_cmd=""; exited=""
    # Falls through to Case 2 (pin fresh UUID).
  fi

  # ── Case 2: new agent pane detected, not yet pinned ───────────────────────
  if [ -n "$agent" ] && [ -z "$pinned_uuid" ]; then
    # Try scrollback first (resurrect edge case: pane started with --resume).
    uuid="$(necro_agent_scrape_resume_cmd "$agent" "$pane_id" 2>/dev/null || true)"
    uuid_source="scrollback-resume"
    # Fall back to cursor pop.
    if [ -z "$uuid" ]; then
      uuid="$(necro_agent_pop_session_id "$agent" "$cwd" 2>/dev/null || true)"
      uuid_source="latest-jsonl"
    fi
    if [ -n "$uuid" ]; then
      tmux set-option -p -t "$pane_id" @necro_uuid "$uuid" 2>/dev/null || true
      tmux set-option -p -t "$pane_id" @necro_cmd  "$cmd"  2>/dev/null || true
    fi
    continue
  fi

  # ── Case 3: agent exited (had @necro_cmd set, current cmd no longer matches) ─
  if [ -n "$pinned_cmd" ] && [ -z "$agent" ] && [ "$exited" != "1" ]; then
    # Scrape farewell UUID from scrollback — more reliable than what we popped.
    farewell="$(necro_agent_scrape_session_id "$pinned_cmd" "$pane_id" 2>/dev/null || true)"
    if [ -n "$farewell" ] && [ "$farewell" != "$pinned_uuid" ]; then
      tmux set-option -p -t "$pane_id" @necro_uuid "$farewell" 2>/dev/null || true
    fi
    tmux set-option -p -t "$pane_id" @necro_agent_exited "1" 2>/dev/null || true
    tmux set-option -pu -t "$pane_id" @necro_cmd              2>/dev/null || true
    continue
  fi

done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null)

exit 0
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x scripts/necro-watch.sh
```

- [ ] **Step 4: Wire into `status-right` in `tmux-ai-necromancer.tmux`**

After the existing autosave wiring block, add:

```bash
WATCHER="$CURRENT_DIR/scripts/necro-watch.sh"

status_right="$(tmux show-option -gqv status-right 2>/dev/null)"
case "$status_right" in
  *necro-watch.sh*) : ;;  # already wired
  *) tmux set-option -gq status-right "#($WATCHER)$status_right" ;;
esac
```

- [ ] **Step 5: Verify watcher runs and pins options**

```bash
# Reload tmux conf:
tmux source ~/.tmux.conf

# Wait ~5 seconds (one status tick), then check a live Claude pane:
tmux show-option -p -t %<your-claude-pane-id> @necro_uuid
tmux show-option -p -t %<your-claude-pane-id> @necro_cmd
# Should print a UUID and "claude" (or your alias)
```

- [ ] **Step 6: Commit**

```bash
git add scripts/necro-watch.sh tmux-ai-necromancer.tmux lib/common.sh
git commit -m "feat(watcher): add necro-watch.sh — pin UUID to agent panes on detection"
```

---

### Task 4: `necro-snapshot.sh` reads `@necro_uuid` first

The snapshot now has a reliable source: the pane option pinned by the watcher. Read it before falling back to the cursor.

**Files:**
- Modify: `scripts/necro-snapshot.sh`

**Interfaces:**
- Consumes: `@necro_uuid` pane option (set by watcher, Task 3)
- No interface changes — `emit_record` signature unchanged, `uuid_source` gains new value `"pane-option"`

- [ ] **Step 1: Add pane-option read at the top of the `--idle-only` live-agent branch**

In `necro-snapshot.sh`, replace the `--idle-only` branch:

```bash
  # Live agent + --idle-only: read watcher-pinned UUID first, then cursor pop.
  if [ "$IDLE_ONLY" = "1" ]; then
    fb="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    fb_source="pane-option"
    if [ -z "$fb" ]; then
      fb="$(resolve_fallback_id "$agent" "$cwd" 1)"
      fb_source="latest-jsonl"
    fi
    if [ -n "$fb" ]; then
      echo "  --idle-only ($agent) — ${fb_source}: $fb"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "$fb" "$fb_source"
    else
      echo "  --idle-only ($agent) — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$agent" "" ""
    fi
    continue
  fi
```

- [ ] **Step 2: Also read pane option in idle-shell branch (agent just exited)**

In the idle-shell branch, after the per-agent fallback loop, add a pane-option check first:

```bash
  if necro_is_idle_shell "$cmd"; then
    # Watcher may have pinned a UUID before the agent exited.
    found_uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    found_agent="$(tmux show-option -pqv -t "$pane_id" @necro_cmd  2>/dev/null || true)"
    found_source="pane-option"
    if [ -z "$found_uuid" ]; then
      found_uuid=""; found_agent=""
      for a in $(necro_enabled_agents); do
        fb="$(resolve_fallback_id "$a" "$cwd")"
        if [ -n "$fb" ]; then found_uuid="$fb"; found_agent="$a"; found_source="latest-jsonl"; break; fi
      done
    fi
    if [ -n "$found_uuid" ]; then
      echo "  idle shell — ${found_source} id ($found_agent): $found_uuid"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "$found_agent" "$found_uuid" "$found_source"
    else
      echo "  idle shell — no session found, recording without id"
      emit_record "$pane_id" "$session" "$win_idx" "$win_name" "$cwd" "$cmd" "" "" ""
    fi
    continue
  fi
```

- [ ] **Step 3: Run a live autosave and check the log**

```bash
# Trigger an immediate snapshot:
~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-snapshot.sh --idle-only

# Check the output — lines for Claude panes should show "pane-option":
tail -1 ~/.claude/tmux-snapshots/*.idle-only.jsonl | python3 -m json.tool | grep uuid_source
# Expected: "pane-option" for panes the watcher has visited
```

- [ ] **Step 4: Commit**

```bash
git add scripts/necro-snapshot.sh
git commit -m "feat(snapshot): prefer watcher-pinned @necro_uuid over cursor fallback"
```

---

### Task 5: Watcher handles closed-session cleanup for autosave

The autosave's job is now: write the snapshot AND log which sessions closed since the last save. The watcher already sets `@necro_agent_exited=1` on exit. Autosave reads that and logs it.

**Files:**
- Modify: `scripts/necro-autosave.sh`

**Interfaces:**
- Consumes: `@necro_agent_exited` pane option (set by watcher, Task 3)
- Produces: log lines `[ts] closed: pane=<id> agent=<name> uuid=<uuid> cwd=<cwd>`

- [ ] **Step 1: Add closed-session log to the autosave block**

In `necro-autosave.sh`, inside the `{ ... } >> "$LOG" 2>&1 &` block, after the snapshot call:

```bash
  # Log panes whose agents exited since the last autosave.
  while IFS=$'\t' read -r pane_id cwd; do
    [ -z "$pane_id" ] && continue
    exited="$(tmux show-option -pqv -t "$pane_id" @necro_agent_exited 2>/dev/null || true)"
    [ "$exited" != "1" ] && continue
    uuid="$(tmux show-option -pqv -t "$pane_id" @necro_uuid 2>/dev/null || true)"
    cmd="$(tmux show-option -pqv  -t "$pane_id" @necro_cmd  2>/dev/null || true)"
    echo "[$(necro_ts)] closed: pane=$pane_id agent=${cmd:-unknown} uuid=${uuid:-none} cwd=$cwd"
  done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}' 2>/dev/null)
```

- [ ] **Step 2: Verify**

```bash
# Exit a Claude session, wait for next autosave tick (up to 5 min),
# or trigger manually:
~/.tmux/plugins/tmux-ai-necromancer/scripts/necro-autosave.sh
sleep 2
grep "closed:" ~/.claude/tmux-snapshots/autosave.log | tail -5
# Should show a line for the exited pane
```

- [ ] **Step 3: Commit**

```bash
git add scripts/necro-autosave.sh
git commit -m "feat(autosave): log closed agent sessions detected by watcher"
```

---

### Task 6: Update `docs/agents.md` — document new adapter functions and options

**Files:**
- Modify: `docs/agents.md`

- [ ] **Step 1: Add `agent_<name>_scrape_resume_cmd` to the contract table**

In the contract section, add after `agent_<name>_scrape_session_id`:

```markdown
| `agent_<name>_scrape_resume_cmd "$pane_id"` | Optional: scrape a `--resume <uuid>` startup line from scrollback. Used by the watcher on first detection to handle resurrect-restored panes. Return "" if N/A. |
```

- [ ] **Step 2: Document `@necromancer_claude_commands`**

In a new "Configuration" section or inline in the adapter guide:

```markdown
## Command name matching

`agent_<name>_matches` is called with `pane_current_command` — the process
name the kernel sees. For Claude Code, this is `claude` by default, but if
you run it via an alias or wrapper script named differently (e.g. `cc`), add
your command name to `@necromancer_claude_commands`:

\```tmux
set -g @necromancer_claude_commands 'claude cc'
\```

Other agents: implement `agent_<name>_matches` to match however your binary
appears in `pane_current_command`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/agents.md
git commit -m "docs(agents): document scrape_resume_cmd and @necromancer_claude_commands"
```

---

## Self-Review

**Spec coverage:**
- ✅ Alias support (`cc`) — Task 1
- ✅ Watcher pins UUID at pane startup — Task 3
- ✅ Watcher detects exits and scrapes farewell UUID — Task 3 Case 3
- ✅ Watcher + autosave work together — Tasks 3+4+5
- ✅ Edge case 1: agent restarts in same pane — Task 3 Case 1
- ✅ Edge case 2: pane splits (watcher ignores non-agent panes naturally) — handled implicitly
- ✅ Edge case 3: ungraceful kill (pane option dies with pane, snapshot still has last good UUID in JSONL) — acceptable, no code needed
- ✅ Edge case 4: agent running before plugin loaded (watcher pins on first tick) — Task 3 Case 2
- ✅ Edge case 5: resurrect restores `claude --resume <uuid>` pane — Task 2 + Task 3 Case 2

**Placeholder scan:** None found — all steps have concrete code.

**Type consistency:** `necro_agent_scrape_resume_cmd "$agent" "$pane_id"` dispatcher signature matches call site in `necro-watch.sh`. `@necro_uuid`, `@necro_cmd`, `@necro_agent_exited` option names consistent across Tasks 3, 4, 5.

**One gap found and fixed:** The watcher's Case 3 calls `necro_agent_scrape_session_id "$pinned_cmd" "$pane_id"` — but the dispatcher signature is `necro_agent_scrape_session_id "$agent" "$pane_id"`. Since `$pinned_cmd` is the command name (e.g. `claude`, `cc`), and the dispatcher looks up `agent_${agent}_scrape_session_id`, we need the *agent name* not the *command name*. Fixed: store `@necro_agent` (the resolved agent name like `claude`) separately from `@necro_cmd` (the actual command like `cc`).

**Fix for above gap — add `@necro_agent` pane option in Task 3 Step 2:**

In the pin block (Case 2), also set:
```bash
tmux set-option -p -t "$pane_id" @necro_agent "$agent" 2>/dev/null || true
```

And in Case 3, read it:
```bash
pinned_agent="$(tmux show-option -pqv -t "$pane_id" @necro_agent 2>/dev/null || true)"
farewell="$(necro_agent_scrape_session_id "$pinned_agent" "$pane_id" 2>/dev/null || true)"
```

Clear it on restart (Case 1) and on exit (Case 3). Also read `@necro_agent` in `necro-snapshot.sh` idle-shell branch for the `found_agent` value.
