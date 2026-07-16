# Restore: Pane-Layout Preservation + Post-Resume Message — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve pane layout geometry through snapshot/restore, and auto-send a follow-up message (default `continue`) after each resume.

**Architecture:** Two independent features on the same restore path. (A) Snapshot captures tmux `#{window_layout}` per pane; restore replays it with `select-layout` in a post-loop pass, guarded by a pane-count match. (B) After each resume send in `necro-restore.sh` and `necro-apply.sh`, send a configurable message + Enter following a fixed delay.

**Tech Stack:** Bash (`set -uo pipefail`), tmux, jq. Self-contained bash tests using mock tmux on an isolated dir (no live server).

## Global Constraints

- Snapshot scripts use `set -uo pipefail`, NOT `set -e`/`set -euo` — copied verbatim from CLAUDE.md invariant #1.
- Restore is idempotent via the per-pane `@necro_id` marker — re-running adds 0 windows/panes, resumes 0 agents (invariant #2).
- Never `set -e`-abort on a tmux call in restore; guard tmux calls (invariant #3).
- Autosave/rotation must be POSIX — no `mapfile` (invariant #4). (Not touched here, but stay POSIX.)
- Don't double-resume: only send resume (and now the message) into a freshly-created window (invariant #5).
- Resume launches during restore/apply must be paced (invariant #10) — do not remove the existing batch pacing.
- Conventional-commit titles; no AI attribution in commits.
- Dependency-light: bash, python3, jq, tmux only.
- Tests run directly: `bash tests/<name>.sh`; restore tests use a mock `tmux` on `$PATH`.

---

### Task 1: Snapshot captures `#{window_layout}` per pane

**Files:**
- Modify: `scripts/necro-snapshot.sh` (list-panes format ~line 113; `emit_record` line 63-79; all 8 `emit_record` call sites)
- Test: `tests/necro-snapshot-layout-field-test.sh` (create)

**Interfaces:**
- Produces: each JSONL record gains a `"window_layout":"<string>"` field (empty string when tmux reports none). `emit_record` gains a 10th positional arg `window_layout` appended after `uuid_source`.

- [ ] **Step 1: Write the failing test**

Create `tests/necro-snapshot-layout-field-test.sh`:

```bash
#!/usr/bin/env bash
# necro-snapshot-layout-field-test.sh — snapshot records carry a window_layout
# field scraped from tmux #{window_layout}.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"

TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CWD="$TMP/w"; mkdir -p "$CWD"
LAYOUT='c005,364x71,0,0{182x71,0,0,5,181x71,183,0,8}'

# Mock tmux: one idle pane, known window_layout, no agent.
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  list-panes)
    printf '%%1\ts\t2\tw\t$CWD\tzsh\t$LAYOUT\n' ;;
  show-option) printf '' ;;
  display-message) printf 'zsh\n' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

bash "$ROOT/scripts/necro-snapshot.sh" --idle-only >/dev/null 2>&1
OUT="$(/bin/ls -t "$NECROMANCER_SNAPSHOT_DIR"/*.jsonl | head -1)"
got="$(jq -r '.window_layout' "$OUT")"
[ "$got" = "$LAYOUT" ] || { echo "FAIL: window_layout=$got want=$LAYOUT"; cat "$OUT"; exit 1; }
echo "PASS: necro-snapshot-layout-field-test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/necro-snapshot-layout-field-test.sh`
Expected: FAIL — either the format string lacks `#{window_layout}` (so the mock's tab-split is off) or `.window_layout` is null.

- [ ] **Step 3: Add `#{window_layout}` to the list-panes format and read it**

In `scripts/necro-snapshot.sh`, change the format string (~line 112-113):

```bash
snapshot=$(tmux list-panes -a -F \
  '#{pane_id}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_path}	#{pane_current_command}	#{window_layout}')
```

And the loop read (~line 117):

```bash
while IFS=$'\t' read -r pane_id session win_idx win_name cwd cmd layout; do
```

- [ ] **Step 4: Add the `window_layout` field to `emit_record`**

Replace `emit_record` (lines 63-79) so it takes a 10th arg and emits the field:

```bash
emit_record() {
  local pane_id="$1" session="$2" window_index="$3" window_name="$4" \
        cwd="$5" prev_cmd="$6" agent="$7" uuid="$8" uuid_source="${9:-}" \
        window_layout="${10:-}"
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"pane_id":%s,"session":%s,"window_index":%d,"window_name":%s,"cwd":%s,"prev_cmd":%s,"agent":%s,"uuid":%s,"uuid_source":%s,"window_layout":%s,"captured_at":%s,"first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}\n' \
    "$(necro_json_escape "$pane_id")" \
    "$(necro_json_escape "$session")" \
    "$window_index" \
    "$(necro_json_escape "$window_name")" \
    "$(necro_json_escape "$cwd")" \
    "$(necro_json_escape "$prev_cmd")" \
    "$(necro_json_escape "$agent")" \
    "$(necro_json_escape "$uuid")" \
    "$(necro_json_escape "$uuid_source")" \
    "$(necro_json_escape "$window_layout")" \
    "$(necro_json_escape "$now")" \
    >> "$OUT"
}
```

- [ ] **Step 5: Thread `$layout` through all 8 `emit_record` call sites**

Append `"$layout"` as the final argument to every `emit_record` call. The 8 sites (current line numbers) and their tails:

- Line 132: `... "$found_agent" "$found_uuid" "pane-option" "$layout"`
- Line 135: `... "" "" "" "$layout"`
- Line 143: `... "" "" "" "$layout"`
- Line 157: `... "$agent" "$fb" "$fb_source" "$layout"`
- Line 160: `... "$agent" "" "" "$layout"`
- Line 181: `... "$agent" "$fb" "latest-jsonl" "$layout"`
- Line 184: `... "$agent" "" "" "$layout"`
- Line 209: `... "$agent" "$uuid" "$uuid_source" "$layout"`

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/necro-snapshot-layout-field-test.sh`
Expected: PASS

- [ ] **Step 7: Verify no regressions in existing snapshot tests**

Run: `for t in tests/necro-*snapshot* tests/necro-agent-*; do bash "$t"; done`
Expected: all PASS (they don't assert on `window_layout` so the new field is additive).

- [ ] **Step 8: Commit**

```bash
git add scripts/necro-snapshot.sh tests/necro-snapshot-layout-field-test.sh
git commit -m "feat(snapshot): capture window_layout per pane"
```

---

### Task 2: Restore replays layout with `select-layout` (post-loop, guarded)

**Files:**
- Modify: `scripts/necro-restore.sh` (arrays near line 281; parse in loop ~line 302; new post-loop pass before line 437)
- Test: `tests/necro-restore-layout-test.sh` (create)

**Interfaces:**
- Consumes: the `window_layout` field from Task 1 and the existing `WIN_FOR_GROUP[$group]` mapping (`group="${session}|${win_idx}"`).
- Produces: for each freshly-created window group whose live pane count equals the saved count, `tmux select-layout -t <window_id> "<layout>"` is invoked once.

- [ ] **Step 1: Write the failing test**

Create `tests/necro-restore-layout-test.sh`:

```bash
#!/usr/bin/env bash
# necro-restore-layout-test.sh — a 2-pane window group whose records carry a
# window_layout string triggers exactly one select-layout on the group's window,
# and only when live pane count matches the saved count.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
CALLS="$TMP/calls.log"
CWD1="$TMP/a"; CWD2="$TMP/b"; mkdir -p "$CWD1" "$CWD2"
LAYOUT='c005,364x71,0,0{182x71,0,0,5,181x71,183,0,8}'

SESS_FLAG="$TMP/created"
cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session)  [ -f "$SESS_FLAG" ] && exit 0 || exit 1 ;;
  new-session)  : > "$SESS_FLAG"; exit 0 ;;
  list-windows)
    case "\$*" in
      *'#{@necro_id}'*'#{window_id}'*) printf '' ;;
      *'#{window_index}'*'#{window_name}'*) printf '' ;;
      *) printf '@1\n' ;;
    esac ;;
  new-window)   printf '@10\n' ;;
  split-window) printf '%%20\n' ;;
  list-panes)   printf '%%1\n%%20\n' ;;   # 2 live panes in the group window
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMPBIN/tmux"
export PATH="$TMPBIN:$PATH"

SNAP="$TMP/s.jsonl"
cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":2,"window_name":"w","cwd":"$CWD1","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
{"pane_id":"%2","session":"s","window_index":2,"window_name":"w","cwd":"$CWD2","prev_cmd":"zsh","agent":"","uuid":"","uuid_source":"","window_layout":"$LAYOUT","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF

bash "$ROOT/scripts/necro-restore.sh" "$SNAP" >/dev/null 2>&1
n=$(grep -c "^select-layout .* $LAYOUT" "$CALLS" || true)
[ "$n" -eq 1 ] || { echo "FAIL: expected 1 select-layout with layout, got $n"; grep select-layout "$CALLS" || true; exit 1; }
echo "PASS: necro-restore-layout-test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/necro-restore-layout-test.sh`
Expected: FAIL — `select-layout` is never called yet (0 matches).

- [ ] **Step 3: Add layout-tracking arrays**

In `scripts/necro-restore.sh`, next to `declare -A WIN_FOR_GROUP` (line 281):

```bash
declare -A WIN_FOR_GROUP
declare -A LAYOUT_FOR_GROUP
declare -A PANE_COUNT_FOR_GROUP
```

- [ ] **Step 4: Parse `window_layout` and accumulate per group**

After the existing `uuid=$(jq ...)` parse (~line 302), add:

```bash
layout=$(jq -r '.window_layout // empty' <<<"$line")
```

Then, right after `group="${session}|${win_idx}"` is computed (line 325), add:

```bash
PANE_COUNT_FOR_GROUP[$group]=$(( ${PANE_COUNT_FOR_GROUP[$group]:-0} + 1 ))
[ -n "$layout" ] && [ -z "${LAYOUT_FOR_GROUP[$group]:-}" ] && LAYOUT_FOR_GROUP[$group]="$layout"
```

- [ ] **Step 5: Add the post-loop layout pass**

Immediately after the main `done < "$SNAPSHOT"` (line 435) and before `stage 5 5 "cleanup"` (line 437), add:

```bash
# Replay saved pane layouts onto windows this run created. Only when the live
# pane count matches the saved count — never stomp a window whose shape changed.
for group in "${!LAYOUT_FOR_GROUP[@]}"; do
  win="${WIN_FOR_GROUP[$group]:-}"
  layout="${LAYOUT_FOR_GROUP[$group]}"
  [ -z "$win" ] && continue
  case "$win" in *:dry) continue ;; esac
  saved="${PANE_COUNT_FOR_GROUP[$group]:-0}"
  if [ "$DRY_RUN" = "1" ]; then
    echo "  DRY: select-layout -t $win $layout"
    continue
  fi
  live="$(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -c . || true)"
  if [ "$live" = "$saved" ]; then
    tmux select-layout -t "$win" "$layout" 2>/dev/null || true
  else
    echo "  layout skipped for $group: pane count $live != $saved"
  fi
done
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/necro-restore-layout-test.sh`
Expected: PASS

- [ ] **Step 7: Idempotency + regression check**

Run: `bash tests/necro-restore-multipane-window-test.sh && bash tests/necro-restore-safety-test.sh && bash tests/necro-restore-claim-existing-test.sh`
Expected: all PASS (reused/claimed windows set no `WIN_FOR_GROUP`, so the pass skips them; safety test's idempotent re-run adds no `select-layout` that changes state).

- [ ] **Step 8: Commit**

```bash
git add scripts/necro-restore.sh tests/necro-restore-layout-test.sh
git commit -m "feat(restore): replay saved pane layout via select-layout"
```

---

### Task 3: Post-resume message option plumbing (restore)

**Files:**
- Modify: `scripts/necro-restore.sh` (CLI arg parse; option-resolver funcs near lines 126-154; banner ~line 220; resolve vars ~line 210-212)
- Test: covered by Task 4's test.

**Interfaces:**
- Produces: two resolver functions `resume_message()` (default `continue`, empty string is a valid off-value) and `resume_message_delay()` (default `8`, numeric-validated), plus `$resume_message` / `$resume_message_delay` resolved before the main loop. CLI flags `--resume-message <str>` and `--resume-message-delay <n>`; env `NECROMANCER_RESUME_MESSAGE`, `NECROMANCER_RESUME_MESSAGE_DELAY`; tmux options `@necromancer_resume_message`, `@necromancer_resume_message_delay`.

- [ ] **Step 1: Add CLI flag vars and parsing**

Find where `RESUME_DELAY_OPT` / `RESUME_BATCH_SIZE_OPT` are initialized and parsed (grep `RESUME_DELAY_OPT` in the file). Alongside them add:

```bash
RESUME_MESSAGE_OPT_SET=0
RESUME_MESSAGE_OPT=""
RESUME_MESSAGE_DELAY_OPT=""
```

In the same `case` that handles `--resume-delay`/`--resume-batch-size`, add:

```bash
    --resume-message) RESUME_MESSAGE_OPT_SET=1; RESUME_MESSAGE_OPT="$2"; shift 2 ;;
    --resume-message-delay) RESUME_MESSAGE_DELAY_OPT="$2"; shift 2 ;;
```

Note: `RESUME_MESSAGE_OPT_SET` distinguishes "flag given with empty value"
(off) from "flag absent" (use env/tmux/default). Delay needs no such flag —
empty just falls through to default.

- [ ] **Step 2: Add resolver functions**

After `resume_batch_size()` (line 154), add:

```bash
resume_message() {
  if [ "$RESUME_MESSAGE_OPT_SET" = "1" ]; then
    printf '%s' "$RESUME_MESSAGE_OPT"; return
  fi
  if [ -n "${NECROMANCER_RESUME_MESSAGE+x}" ]; then
    printf '%s' "$NECROMANCER_RESUME_MESSAGE"; return
  fi
  local val; val="$(necro_tmux_option @necromancer_resume_message "__unset__")"
  if [ "$val" = "__unset__" ]; then printf 'continue'; else printf '%s' "$val"; fi
}

resume_message_delay() {
  local val
  if [ -n "$RESUME_MESSAGE_DELAY_OPT" ]; then
    val="$RESUME_MESSAGE_DELAY_OPT"
  elif [ -n "${NECROMANCER_RESUME_MESSAGE_DELAY:-}" ]; then
    val="$NECROMANCER_RESUME_MESSAGE_DELAY"
  else
    val="$(necro_tmux_option @necromancer_resume_message_delay "8")"
  fi
  case "$val" in
    ''|*[!0-9.]*) printf '8' ;;
    *) printf '%s' "$val" ;;
  esac
}
```

The `+x` / `__unset__` sentinels make empty-string an explicit off-switch at
every tier, distinct from "not configured".

- [ ] **Step 3: Resolve before the loop + banner line**

Near lines 210-212 add:

```bash
resume_message="$(resume_message)"
resume_message_delay="$(resume_message_delay)"
```

After the "Resume pacing" banner line (220) add:

```bash
if [ -n "$resume_message" ]; then
  echo "  Post-resume message: '$resume_message' after ${resume_message_delay}s"
else
  echo "  Post-resume message: (none)"
fi
```

- [ ] **Step 4: Sanity run (no test yet — wired in Task 4)**

Run: `bash scripts/necro-restore.sh --dry-run --resume-message 'go' /dev/null 2>&1 | grep -i 'post-resume'`
Expected: prints `Post-resume message: 'go' after 8s` (the empty snapshot path may error on no-records; the banner prints before that — if it doesn't reach the banner, defer this check to Task 4).

- [ ] **Step 5: Commit**

```bash
git add scripts/necro-restore.sh
git commit -m "feat(restore): add resume-message option plumbing"
```

---

### Task 4: Send the post-resume message in restore

**Files:**
- Modify: `scripts/necro-restore.sh` (the resume send block, lines 412-424)
- Test: `tests/necro-restore-resume-message-test.sh` (create)

**Interfaces:**
- Consumes: `$resume_message`, `$resume_message_delay`, `$target` from the resume block.
- Produces: after a successful `send-keys "$resume_cmd" Enter`, when `$resume_message` is non-empty, a `send-keys "$target" "$resume_message" Enter` follows a `sleep "$resume_message_delay"`.

- [ ] **Step 1: Write the failing test**

Create `tests/necro-restore-resume-message-test.sh`:

```bash
#!/usr/bin/env bash
# necro-restore-resume-message-test.sh — after a resume, restore sends the
# configured post-resume message; with an empty message it sends nothing extra.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_case() {
  local msg_flag="$1" expect="$2"
  local TMP; TMP="$(mktemp -d)"
  export HOME="$TMP/home"; export NECROMANCER_SNAPSHOT_DIR="$TMP/snap"
  mkdir -p "$HOME" "$NECROMANCER_SNAPSHOT_DIR"
  local TMPBIN="$TMP/bin"; mkdir -p "$TMPBIN"
  local CALLS="$TMP/calls.log"; local CWD="$TMP/w"; mkdir -p "$CWD"
  # Fake claude transcript dir so resume isn't skipped for size/missing.
  cat > "$TMPBIN/tmux" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$1" in
  has-session) exit 1 ;;
  new-session) exit 0 ;;
  list-windows) case "\$*" in *'#{window_id}'*) printf '@1\n' ;; *) printf '' ;; esac ;;
  list-panes) printf '%%1\n' ;;
  display-message) printf 'zsh\n' ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMPBIN/tmux"; export PATH="$TMPBIN:$PATH"
  # Snapshot: one fresh claude pane. Use a resume the script won't skip:
  # point NECROMANCER at a big transcript budget and a real-looking uuid.
  local SNAP="$TMP/s.jsonl"
  cat > "$SNAP" <<EOF
{"pane_id":"%1","session":"s","window_index":1,"window_name":"w","cwd":"$CWD","prev_cmd":"claude","agent":"claude","uuid":"11111111-1111-1111-1111-111111111111","uuid_source":"scrollback","window_layout":"","captured_at":"now","first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
EOF
  # Make the claude transcript exist so resume proceeds.
  mkdir -p "$HOME/.claude/projects/$(printf '%s' "$CWD" | sed 's#/#-#g')"
  : > "$HOME/.claude/projects/$(printf '%s' "$CWD" | sed 's#/#-#g')/11111111-1111-1111-1111-111111111111.jsonl"
  NECROMANCER_RESUME_MESSAGE_DELAY=0 bash "$ROOT/scripts/necro-restore.sh" $msg_flag "$SNAP" >/dev/null 2>&1
  local got; got=$(grep -c "send-keys .* continue Enter" "$CALLS" || true)
  rm -rf "$TMP"
  [ "$got" = "$expect" ] || { echo "FAIL: flag='$msg_flag' expected $expect 'continue' sends, got $got"; return 1; }
}

run_case "" 1 || exit 1                       # default → sends 'continue'
run_case "--resume-message " 0 || exit 1      # empty → sends nothing
echo "PASS: necro-restore-resume-message-test"
```

Note: the resume-skip logic (`claude_resume_skip_reason`) may still short-circuit
in the mock. If Step 3 verification shows the resume itself is skipped, adjust the
test's transcript-size env (`NECROMANCER_MAX_CLAUDE_BYTES`) or point the snapshot
at `agent:"codex"` (no size gate) — keep the assertion on the message send.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/necro-restore-resume-message-test.sh`
Expected: FAIL — no `send-keys ... continue` yet.

- [ ] **Step 3: Send the message after the resume**

In `scripts/necro-restore.sh`, inside the resume block, after `run tmux send-keys -t "$target" "$resume_cmd" Enter` (line 415) and before the `resumed=$((resumed + 1))` counter, insert:

```bash
      if [ -n "$resume_message" ]; then
        if [ "$DRY_RUN" = "1" ]; then
          echo "  DRY: send-keys $resume_message (after ${resume_message_delay}s)"
        else
          sleep "$resume_message_delay"
          tmux send-keys -t "$target" "$resume_message" Enter 2>/dev/null || true
          echo "  sent post-resume message: $resume_message"
        fi
      fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/necro-restore-resume-message-test.sh`
Expected: PASS (both cases).

- [ ] **Step 5: Pacing regression**

Run: `bash tests/necro-restore-resume-delay-test.sh && bash tests/necro-restore-batch-skips-test.sh`
Expected: PASS — the message send sits inside the fresh-resume branch and doesn't alter batch counting.

- [ ] **Step 6: Commit**

```bash
git add scripts/necro-restore.sh tests/necro-restore-resume-message-test.sh
git commit -m "feat(restore): auto-send post-resume message"
```

---

### Task 5: Mirror the post-resume message in `necro-apply.sh`

**Files:**
- Modify: `scripts/necro-apply.sh` (option funcs near lines 54-85; resume send ~line 136)
- Test: `tests/necro-apply-resume-message-test.sh` (create, mirrors Task 4's test against apply)

**Interfaces:**
- Consumes: same three-tier option resolution as restore. `necro-apply.sh` already has `resume_delay_seconds()`/`resume_batch_size()` — add matching `resume_message()`/`resume_message_delay()` and resolved vars.
- Produces: after `run tmux send-keys -t "$window_id" "$resume_cmd" Enter` (line 136), the same guarded message send using `$window_id` as target.

- [ ] **Step 1: Write the failing test**

Create `tests/necro-apply-resume-message-test.sh` mirroring Task 4 but invoking `scripts/necro-apply.sh` with its expected inputs (inspect the top of `necro-apply.sh` for its snapshot/arg contract — it reorganizes LIVE panes, so the mock must return a live pane list). Assert one `send-keys ... continue Enter` by default, zero with `--resume-message ''`.

```bash
#!/usr/bin/env bash
# necro-apply-resume-message-test.sh — apply sends the post-resume message too.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ... build mock tmux + snapshot per necro-apply.sh's contract (see
# tests/necro-restore-resume-message-test.sh for the pattern; adapt the
# mock's list-panes/list-windows responses to what apply queries) ...
# Assert: default → 1 'continue' send; --resume-message '' → 0.
echo "PASS: necro-apply-resume-message-test"   # replace with real assertions
```

Note: this step's test body must be fully fleshed out against the real
`necro-apply.sh` contract before implementation — read `scripts/necro-apply.sh`
lines 1-140 first to see exactly which tmux subcommands it calls and what arg
shape it expects, then model the mock on those, mirroring the assertion style of
the restore message test.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/necro-apply-resume-message-test.sh`
Expected: FAIL — no message send in apply yet.

- [ ] **Step 3: Add resolver funcs + resolved vars to apply**

Mirror Task 3's `resume_message()` / `resume_message_delay()` into
`scripts/necro-apply.sh` (place them next to `resume_delay_seconds()` at line 54;
add CLI flag parsing matching apply's existing arg loop; resolve
`RESUME_MESSAGE="$(resume_message)"` and
`RESUME_MESSAGE_DELAY="$(resume_message_delay)"` next to `RESUME_DELAY`/`RESUME_BATCH`
at lines 84-85). Copy the resolver bodies verbatim from Task 3 Step 2, renaming
the resolved-var casing to match apply's uppercase style (`RESUME_MESSAGE`).

- [ ] **Step 4: Send the message after apply's resume**

After `run tmux send-keys -t "$window_id" "$resume_cmd" Enter` (line 136), insert
the guarded send (mirror Task 4 Step 3, using `$window_id` as target and
`$RESUME_MESSAGE`/`$RESUME_MESSAGE_DELAY`):

```bash
        if [ -n "$RESUME_MESSAGE" ]; then
          if [ "$DRY_RUN" = "1" ]; then
            echo "  DRY: send-keys $RESUME_MESSAGE (after ${RESUME_MESSAGE_DELAY}s)"
          else
            sleep "$RESUME_MESSAGE_DELAY"
            tmux send-keys -t "$window_id" "$RESUME_MESSAGE" Enter 2>/dev/null || true
            echo "  sent post-resume message: $RESUME_MESSAGE"
          fi
        fi
```

(Confirm apply uses a `DRY_RUN` var of that name; if it differs, match apply's.)

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/necro-apply-resume-message-test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/necro-apply.sh tests/necro-apply-resume-message-test.sh
git commit -m "feat(apply): auto-send post-resume message"
```

---

### Task 6: Documentation

**Files:**
- Modify: `README.md` (options table), `CLAUDE.md` (invariants/testing note if warranted), `docs/agents.md` only if adapter-facing (it is not — skip).

- [ ] **Step 1: Document the new options**

Add to the README/config options list:

- `@necromancer_resume_message` — text sent into each pane after resume. Default `continue`. Set to empty (`''`) to disable. Also `NECROMANCER_RESUME_MESSAGE` env / `--resume-message` flag.
- `@necromancer_resume_message_delay` — seconds to wait after resume before sending the message. Default `8`. Also env / `--resume-message-delay`.
- Note that snapshots now record `window_layout` and restore replays it (best-effort, only when pane counts match).

- [ ] **Step 2: Add a CLAUDE.md testing bullet**

Under "Key things to verify after any change to restore/snapshot", add:

```
- restored multi-pane windows get their saved layout re-applied (select-layout)
  only when the live pane count matches the snapshot's
- resumed panes receive the configured post-resume message (default `continue`)
  after the resume, and none when the message is set empty
```

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document resume-message and layout-replay options"
```

---

## Self-Review

**Spec coverage — layout spec:**
- Snapshot captures `#{window_layout}` → Task 1. ✓
- Per-pane field, first-wins per group → Task 2 Step 4. ✓
- Post-loop `select-layout` guarded by pane-count match → Task 2 Step 5. ✓
- Skip reused/claimed windows (no `WIN_FOR_GROUP`) → Task 2 Step 5 (`[ -z "$win" ] && continue`). ✓
- DRY_RUN logs, doesn't apply → Task 2 Step 5. ✓
- Backward-compat (old snapshots, empty layout) → `[ -n "$layout" ]` guard in Task 2 Step 4; empty field skips. ✓
- Idempotency → Task 2 Step 7 regression. ✓

**Spec coverage — resume-message spec:**
- Option with three-tier precedence + empty off-switch → Task 3. ✓
- Default `continue` → Task 3 Step 2 (`__unset__` sentinel). ✓
- Fixed delay, default 8 → Task 3 Step 2. ✓
- Both restore + apply → Tasks 4 + 5. ✓
- Gated on fresh-resume branch → Task 4 Step 3 placement. ✓
- DRY_RUN logs only → Task 4 Step 3. ✓

**Placeholder scan:** Task 5 Step 1 test body is intentionally a stub with an
explicit instruction to flesh it out against the real apply contract — this is
the one place the plan defers concrete code, because apply's tmux-call shape
must be read first. Flagged, not hidden. All other steps carry full code.

**Type/name consistency:** `resume_message`/`resume_message_delay` funcs and
`$resume_message`/`$resume_message_delay` vars (lowercase in restore, `RESUME_MESSAGE`
uppercase in apply to match each file's local convention) — noted explicitly in
Tasks 3/5 interfaces. `WIN_FOR_GROUP`/`LAYOUT_FOR_GROUP`/`PANE_COUNT_FOR_GROUP`
consistent across Task 2. `group="${session}|${win_idx}"` matches the existing
restore key.

## Known risk to watch during execution

The resume-message tests depend on the resume actually firing in the mock (not
being skipped by `claude_resume_skip_reason`). If the mock trips the skip path,
the message never sends and the test fails for the wrong reason. Mitigation is
in Task 4 Step 1's note: use a codex record (no size gate) or set the transcript
budget env. Resolve this the first time the test is run, before assuming the
feature code is wrong.
