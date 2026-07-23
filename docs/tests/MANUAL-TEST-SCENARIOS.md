# Manual test scenarios

Real-world exercises for a developer running multiple tmux sessions, windows,
and panes with live AI agents (Claude Code / Codex). Run these by hand against
your actual sessions — no test harness, no fake data.

## Capture the current state on command (no 15-min wait)

The autosave daemon runs the one-shot job every `@necromancer_autosave_tick`
seconds; the job itself captures only when `@necromancer_interval` minutes have
elapsed. To capture manually, run exactly this:

```bash
scripts/necro-snapshot.sh --idle-only
```

Run it yourself any time to capture the live tmux + agent state immediately. It
writes `<snapshot-dir>/<timestamp>.idle-only.jsonl` (same file the autosave
produces) and prints the path + record count. This never disturbs a live agent
— identity is captured via the watcher pin / filesystem fallback.

Handy aliases used below:

```bash
NECRO=scripts                              # path to the scripts dir
SNAP="$HOME/.claude/tmux-snapshots"        # or your @necromancer_snapshot_dir
cap()  { bash "$NECRO/necro-snapshot.sh" --idle-only; }   # capture now
last() { /bin/ls -t "$SNAP"/*.idle-only.jsonl | head -1; }# newest snapshot
show() { cat "$(last)" | python3 -m json.tool --json-lines 2>/dev/null || cat "$(last)"; }
```

Before each scenario, drop a divider into the logs so the repro is easy to find:

```bash
tmux set-option -g @necromancer_debug on
bash scripts/necro-log-divider.sh "scenario N"
```

---

## Scenario 1 — Single agent, single pane, baseline capture

1. Open one tmux session, one window, one pane. Start `claude` in a project dir.
2. Send it a message so it has a real transcript.
3. `cap` — capture now.
4. `show` — assert one record with `agent=claude`, a non-empty `uuid`, and the
   correct `cwd`.

**Pass:** exactly one record, agent + uuid + cwd all populated.

## Scenario 2 — Two agents split in one window

1. In one window, split into two panes. Run `claude` (project A) in the left,
   `codex` (project B) in the right. Message both.
2. `cap`.
3. `show` — two records, same `session` + `window_index`, distinct `pane_id`,
   distinct `uuid`, correct per-pane `cwd`, agents `claude` and `codex`.

**Pass:** both agents captured with the right cwd; they share window_index but
differ by pane. (Regression guard for pane-level, not window-level, keying.)

## Scenario 3 — Restore rebuilds a multi-pane window as splits, not flat windows

1. Use the Scenario 2 snapshot.
2. Kill the session: `tmux kill-session -t <name>`.
3. Restore: `bash $NECRO/necro-restore.sh "$(last)"`.
4. Inspect: `tmux list-panes -t <name> -F '#{window_index}.#{pane_index} #{pane_current_path}'`.

**Pass:** the two agents come back as **two panes in one window**, not two
separate windows. Both agents resume.

## Scenario 4 — Restore is idempotent (run it twice)

1. Right after Scenario 3, run the same restore command again.
2. Watch the summary line: `windows added / reused / agents resumed`.

**Pass:** second run reports **0 windows added, 0 agents resumed** (all reused
via the `@necro_id` marker). No duplicate windows or panes appear.

## Scenario 5 — Three sessions restore with paced resumes (no CPU stall)

1. Have 3+ sessions each with a live agent. `cap`.
2. Kill all of them.
3. Restore and watch timing: `bash $NECRO/necro-restore.sh "$(last)"`.

**Pass:** resumes fire in batches — after each `@necromancer_resume_batch_size`
(default 1) launches there is a `@necromancer_resume_delay` (default 5s) pause.
The machine does not stall. Override to see the effect:
`bash $NECRO/necro-restore.sh "$(last)" --resume-delay 0`.

## Scenario 6 — Idle shell captured but not resumed

1. One window with two panes: `claude` in one, a plain `zsh` (no child process)
   in the other. `cap`.
2. `show` — the shell pane records `agent=""`, empty uuid.
3. Kill + restore. Watch the log.

**Pass:** the idle pane is recreated but shows `skip resume: missing agent or
uuid`. Only the real agent resumes.

## Scenario 7 — Watcher pins the correct UUID from process argv

1. Start `claude --resume <known-uuid>` in a pane so the uuid is visible in
   `ps` argv.
2. Let the watcher run one tick (or wait a status interval).
3. Check the pin: `tmux show-option -pqv -t <pane> @necro_uuid`.

**Pass:** the pinned uuid equals the one you passed to `--resume` — resolved
from argv, not a stale filesystem transcript.

## Scenario 8 — Fresh session (no --resume yet) still gets a plausible id

1. Start a brand-new `claude` (no `--resume`) in a fresh project dir. Message it
   once so a transcript file exists.
2. Wait a watcher tick, then `cap`.
3. `show` — the record for that pane.

**Pass:** the captured uuid corresponds to *this* session's transcript (created
after the pane's first-seen stamp), not an old/subagent transcript. `uuid_source`
indicates the fallback path.

## Scenario 9 — Agent exits mid-session is logged, not resumed as a ghost

1. With a live agent captured, quit it (`/exit` or Ctrl-C twice) so the pane
   drops to a shell.
2. `cap`, then check `$SNAP/autosave.log` (or run a capture and read the log).

**Pass:** the closed agent is noted (`closed: pane=... agent=... uuid=...`) and
the new capture records that pane as an idle shell — a later restore won't
resurrect a dead agent.

## Scenario 10 — Full reboot round-trip

1. With several live agents, run `bash $NECRO/necro-reboot-prep.sh` (snapshots +
   enriches + pins the reboot pointer). Confirm `$SNAP/latest-for-reboot` exists.
2. Reboot the machine (use your `safe-reboot` alias).
3. After login, once the tmux server is up, run
   `bash $NECRO/necro-reboot-resume.sh`.

**Pass:** every session/window/pane from before the reboot comes back, agents
resume from their pinned uuids, and re-running the resume adds nothing (idempotent).

---

## Where the logs are

With `@necromancer_debug` enabled, every script writes structured lifecycle and action events to
`~/.tmux-ai-necromancer-logs/<script>.log` (override with
`NECROMANCER_LOG_DIR` or the `@necromancer_log_dir` tmux option). The autosave
summary log is `<snapshot-dir>/autosave.log`. Use
`scripts/necro-log-divider.sh "<label>"` to separate one repro from the next,
then `scripts/necro-clean-debug-logs.sh` when the investigation is complete.
