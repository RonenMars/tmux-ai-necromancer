# CLAUDE.md

Operating manual for AI agents (and humans) working in this repository.

## What this repo is

`tmux-ai-necromancer` is a TPM-compatible tmux plugin that snapshots running AI
coding-agent sessions (Claude Code, Codex, …) and resurrects them after a crash
or reboot. Pure bash + a small Go TUI. No build step for the plugin itself.

## Architecture (read before editing)

```
tmux-ai-necromancer.tmux   TPM entrypoint — starts autosave + watcher daemons, binds restore key
scripts/                   the executables (all source lib/*.sh)
  necro-snapshot.sh        walk panes → JSONL snapshot (per-agent id capture)
  necro-autosave.sh        one-shot throttled background snapshot + rotation
  necro-autosave-daemon.sh autosave scheduler, independent of status-right
  necro-watch.sh           one-tick pane watcher — pins @necro_uuid/@necro_agent to panes
  necro-watch-daemon.sh    watcher scheduler, independent of status-right
  necro-restore.sh         rebuild sessions/windows from a snapshot (IDEMPOTENT)
  necro-apply.sh           reorganize LIVE panes into dest sessions + resume
  necro-context.sh         enrich a snapshot with conversation previews
  necro-reboot-prep.sh     pre-reboot: snapshot + enrich + resurrect save + pin pointer
  necro-reboot-resume.sh   post-reboot: ensure server up → necro-restore.sh
  necro-prune.sh           kill windows whose panes are all idle shells (no child procs)
  necro-menu.sh            interactive menu: list/resume/cleanup snapshots, reboot prep
  necro-log-divider.sh     stamp a labelled separator into every debug log
  necro-clean-debug-logs.sh   remove debug logs (needs tmux)
  necro-clean-debug-logs.py   same, standalone — no tmux/shell needed (Windows/Linux)
lib/
  common.sh                PLUGIN_ROOT resolution, snapshot dir, logging, json escape
  agents.sh                adapter registry + dispatch
  agents/<name>.sh         one file per agent (the contract)
tui/                       Go + Bubble Tea read-only session viewer
docs/agents.md             how to add an agent adapter
```

## The agent adapter contract

This is the core abstraction. Every agent is a file `lib/agents/<name>.sh`
defining these functions (all prefixed `agent_<name>_`):

| Function | Returns |
|---|---|
| `agent_<name>_matches "$cmd"` | exit 0 if the pane's foreground command is this agent |
| `agent_<name>_latest_session_id "$cwd"` | most-recent resumable id for a cwd (filesystem fallback), or "" |
| `agent_<name>_scrape_session_id "$pane"` | id scraped from pane scrollback, or "" |
| `agent_<name>_scrape_resume_cmd "$pane"` | `--resume <uuid>` scraped from startup scrollback, or "" |
| `agent_<name>_resume_cmd "$id"` | the shell command that resumes that id |
| `agent_<name>_exit_keys` | keys to send for a clean exit (interactive capture) |

Scripts NEVER hardcode an agent. They call the dispatchers in `lib/agents.sh`
(`necro_agent_for_cmd`, `necro_agent_resume_cmd`, …). To add an agent: write the
adapter, add its name to `@necromancer_agents`. Nothing else changes.

## Hard-won invariants — do not regress these

1. **Snapshot scripts use `set -uo pipefail`, NOT `set -e`/`set -euo`.** The
   pane loop has pipelines (`grep | tail | grep`) that legitimately exit
   non-zero on no-match. With `pipefail` + `-e`, the first no-match silently
   kills the loop mid-walk. This bit the original tooling for real.

2. **Restore is idempotent via a stable per-PANE marker (`@necro_id` =
   `<cwd>|<uuid>`).** The marker is set on the *pane*, not the window, so that
   several records sharing one `(session, window_index)` restore as splits in a
   single window while each pane stays independently idempotent. Do NOT key
   idempotency on window name (auto-renamed by the shell after first prompt) or
   `pane_current_path` (unset right after creation). Re-running restore must add
   zero windows/panes and re-resume zero agents.

   Multi-pane grouping: within a single restore run, the first record for a
   `(session, window_index)` creates/claims the window; later records with the
   same key `split-window` into it (tracked via the `group_get`/`group_set`
   scalar map — see invariant 13 for why it isn't a `declare -A`). This
   reconstructs multi-pane windows instead of flattening each pane into its own
   window.

3. **Never `set -e`-abort on a tmux call in restore.** The predecessor died with
   `duplicate session: <name>` the moment a target already existed. Guard tmux
   calls; reuse existing sessions.

4. **Autosave rotation must be POSIX** (no `mapfile`). tmux runs status-right
   `#(...)` via `/bin/sh`; `mapfile` is bash-4-only and errors there.

5. **Don't double-resume.** Only send a resume command into a *freshly created*
   window. A reused window already has its agent (one-client-per-conversation).

6. **Path-agnostic.** Scripts resolve `PLUGIN_ROOT` from `${BASH_SOURCE[0]}`
   (following symlinks, since TPM symlinks). Never hardcode an install path.

7. **Autosave uses an atomic `mkdir` lock** (`$SNAP_DIR/.autosave.lock`). Two
   concurrent status-right evaluations can both pass the timestamp throttle
   before either writes the new `@necromancer_last_saved` value (TOCTOU).
   `mkdir` is the only POSIX-safe atomic primitive here.

   **The `trap ... EXIT` MUST live inside the backgrounded `{ ... } &` work
   subshell, not in the parent.** The parent returns immediately (status-right
   must never block), so a parent-level trap releases the lock within
   milliseconds while the snapshot is still running — measured at 17ms of
   protection for 3000ms of work, i.e. the lock guarded setup and nothing else.
   `necro-watch.sh` works in the FOREGROUND, so a plain top-level trap is
   correct there; it also breaks a >60s-old lock, since a SIGKILLed watcher
   would otherwise wedge UUID pinning forever with no error anywhere.

8. **Prune keys on child processes, not agent match, and operates per-window.**
   `necro-prune.sh` kills a window only when *every* pane's process has no child
   (`pgrep -P`) — so agents, editors, and builds all survive. Killing at the
   window (not pane) level stops tmux from respawning a fresh shell per dead
   pane. It is manual-only and destructive — never wire it into autosave/reboot.
   Track the busy set as a space-delimited string, not a bash-4 assoc array
   (same `/bin/sh` constraint as autosave rotation).

9. **Pane UUID pinning tries process argv before scrollback before cursor-pop
   — in that order, always.** The watcher (`necro-watch.sh`) resolves which
   Claude/Codex session a pane belongs to via
   `agent_<name>_scrape_ps_resume` (reads `--resume <uuid>` straight from the
   pane's running process argv — ground truth) first, scrollback scrape
   second, and the filesystem cursor-pop fallback last. The cursor-pop
   fallback previously ran with no verification and silently pinned
   stale/unrelated transcripts (days or weeks old) and even subagent/teammate
   transcripts to live panes. It's still needed for genuinely fresh sessions
   with no `--resume` in argv yet, but it must (a) exclude teammate/subagent
   transcripts (`agent_claude_all_session_ids` skips any `.jsonl` starting
   with `<teammate-message`) and (b) reject transcripts older than the pane's
   `@necro_pane_first_seen` stamp via the optional `min_epoch` filter. Never
   drop back to a scrollback/cursor-pop-only resolution order.

10. **Resume launches during restore/apply must be paced, not fired all at
    once.** `necro-restore.sh` and `necro-apply.sh` send a `claude`/`codex
    --resume` into every matching pane; doing this back-to-back for several
    sessions spikes CPU/memory enough to stall the machine. Both scripts
    sleep `@necromancer_resume_delay` (default 5s) after every
    `@necromancer_resume_batch_size` (default 1) resumes — configurable via
    tmux option, `NECROMANCER_RESUME_DELAY`/`NECROMANCER_RESUME_BATCH_SIZE`
    env vars, or `--resume-delay`/`--resume-batch-size` CLI flags. Don't
    remove the pacing to "simplify" the loop — the stall it prevents is real
    and reproducible, not tests-passing.

11. **Claude encodes `/`, `.` AND `_` as `-`** in `~/.claude/projects/<cwd>`.
    Encoding only `/` (the obvious rule) silently mis-resolves any cwd with a
    dot or underscore — a `.worktrees/` checkout, a `/var/folders/..._...`
    tmpdir — and every filesystem lookup then finds nothing: no fallback id, no
    cursor-pop candidate, and the transcript-size guard reports "unknown or
    missing", waving oversized transcripts through. Verified against every
    project dir on disk: slash-only matched 65/148, slash+dot+underscore
    148/148. Tests must call `agent_claude_project_dir` rather than
    re-implementing the rule — a fixture that hardcodes `${cwd//\//-}` diverges
    from the code and hides exactly this bug.

12. **The cursor pop records WHICH ids it handed out, not HOW MANY.** The
    watcher's cursor dir is persistent, and the newest-first listing changes
    between ticks, so a positional index silently breaks: `idx=1` into a list
    that shrank back to one entry reads as "exhausted" (a fresh session never
    gets pinned), and `idx=1` into `[new, old]` re-hands `old`, which is
    already pinned to another pane. Cursor-pop is the NORMAL path for fresh
    sessions (no `--resume` in argv, nothing in scrollback), so this is not an
    edge case.

13. **Every script must run under macOS's stock `/bin/bash` 3.2 — no bash-4
    constructs anywhere, not just the status-right path.** Invariants 4 and 8
    forbid `mapfile`/assoc-arrays in the `/bin/sh` status-right path;
    invariant 13 extends the *no-bash-4* rule to the whole plugin. The
    shebang is `#!/usr/bin/env bash`, so which bash runs is decided by the
    PATH of whatever started the tmux server — and tmux `run-shell` /
    `display-popup` (the restore keybind, the menu, `necro-reboot-resume.sh`)
    inherit that PATH. On a stock macOS box with no Homebrew bash, `env bash`
    is `/bin/bash` 3.2. `necro-restore.sh` once used `declare -A`; under 3.2
    that errors, the `session|win_idx` group key then arithmetic-evaluates as
    an *indexed* subscript (`session | win_idx` = bitwise OR of an unset
    identifier), and `set -u` aborts the loop on the FIRST record — a **silent
    0-session restore** (exit 0, nothing rebuilt, errors buried in the log by
    `necro_init_log`'s `exec > >(tee)`). This is the plugin's worst failure
    mode, and tests never caught it because they invoke `bash <script>` which
    resolves the developer's Homebrew bash 5. The group maps now use
    hex-encoded dynamically-named scalars (`group_get`/`group_set`). When
    adding string→value maps, do the same; never reach for `declare -A`.
    Verify new/changed scripts with `bash -n` under `/bin/bash` AND run the
    restore suite with the script forced onto 3.2.

14. **Exit-capture is opt-in, not opt-out, and requires a verified real tty —
    not a permission-bit check.** `necro-snapshot.sh` defaults to
    `--idle-only` (zero pane disruption); reaching the exit-keys code path at
    all requires an explicit `--interactive` or `--yes` flag. Even then, the
    script refuses to send any keys unless a real controlling terminal is
    verified by actually attempting to open `/dev/tty`
    (`{ : </dev/tty; } 2>/dev/null`) — NOT `[ -t 0 ]` (wrong fd, since
    `necro_init_log` already pipes stdout through `tee`) and NOT
    `[ -r /dev/tty ]` (false-passes in ttyless contexts: `/dev/tty`'s
    permission bits allow read access at the `access(2)` level even when
    there's no controlling terminal for `open(2)` to actually attach to, so
    the check would pass under cron/launchd/a scripted shell where it must
    fail). `necro-reboot-prep.sh` mirrors this exact guard independently
    rather than trusting `necro-snapshot.sh`'s own default, so its `$MODE`
    tracking — and therefore which snapshot file it globs for and pins as the
    reboot target — stays consistent with what the child process actually
    did; without the mirror, a ttyless `--yes` reboot-prep run would have its
    child downgrade to `.idle-only.jsonl` while the wrapper's stale `$MODE`
    still searched for a plain `.jsonl`, pinning an unrelated, possibly stale
    snapshot as the reboot target with no warning. This fixed a real
    production bug: a ttyless invocation of the interactive capture flow fell
    through its per-pane approval prompt (`read -r ans </dev/tty || ans=""` —
    an empty answer on EOF wasn't caught by the prompt's `case` statement,
    which only explicitly matched `q`/`s`/`n`) straight into sending exit
    keys, silently exiting every live Claude Code / Codex session it found.
    Don't remove or weaken this guard to "simplify" the flag parsing or the
    tty check.

## Testing

Self-contained bash tests live in `tests/`. Each uses `mktemp -d` + `NECROMANCER_SNAPSHOT_DIR`
for full isolation — no live tmux server required. Run any test directly:

```bash
bash tests/necro-autosave-lock-test.sh   # lock: only one concurrent autosave fires
bash tests/necro-autosave-lock-lifetime-test.sh  # lock is held for the WORK, not just setup
bash tests/necro-watch-lock-test.sh      # watcher lock: no concurrent walks; stale lock self-heals
bash tests/necro-context-codex-test.sh   # context enrichment for Codex sessions
bash tests/necro-prune-idle-window-test.sh  # prune kills idle windows, keeps busy ones
bash tests/necro-agent-claude-project-dir-test.sh # Claude's cwd encoding ('/', '.', '_' -> '-')
bash tests/necro-agent-pop-cursor-test.sh # cursor pop tracks WHICH ids were used, not how many
bash tests/necro-agent-codex-min-epoch-test.sh    # codex honors the stale-transcript filter too
bash tests/necro-agent-codex-scrape-ps-resume-test.sh  # codex argv ground truth (subcommand form)
bash tests/necro-menu-cleanup-pin-test.sh # menu cleanup never deletes the pinned reboot snapshot
bash tests/necro-restore-claim-group-test.sh # claimed windows group later records (no flattening)
bash tests/necro-agent-scrape-ps-resume-test.sh   # ps-argv is ground truth for pane UUID pinning
bash tests/necro-agent-scrape-ps-resume-multichild-test.sh  # finds claude among sibling processes
bash tests/necro-agent-min-epoch-filter-test.sh   # cursor-pop fallback rejects stale transcripts
bash tests/necro-watch-priority-order-test.sh     # argv > scrollback > cursor-pop, end-to-end
bash tests/necro-watch-first-seen-persistence-test.sh      # first-seen stamp doesn't drift across ticks
bash tests/necro-watch-first-seen-reset-on-restart-test.sh # first-seen resets on agent relaunch
bash tests/necro-watch-suspend-vs-exit-test.sh     # a suspended (Ctrl-Z) agent is not mistaken for a real exit
bash tests/necro-restore-resume-delay-test.sh     # resume launches are paced, not fired all at once
bash tests/necro-restore-batch-skips-test.sh      # skipped records don't consume a pacing batch slot
bash tests/necro-snapshot-layout-field-test.sh    # snapshot records carry the pane's window_layout
bash tests/necro-snapshot-no-tty-guard-test.sh    # exit-capture refused without a real controlling tty
bash tests/necro-snapshot-default-idle-only-test.sh  # bare invocation defaults to idle-only, no pane disruption
bash tests/necro-snapshot-empty-answer-aborts-test.sh  # EOF on the exit prompt aborts (q), never falls through to exit-keys
bash tests/necro-restore-layout-test.sh           # restore replays window_layout via select-layout
bash tests/necro-restore-resume-message-test.sh   # restore sends the post-resume message (or none if empty)
bash tests/necro-apply-resume-message-test.sh     # apply sends the post-resume message too
bash tests/necro-restore-bash32-test.sh           # restore runs clean under stock /bin/bash 3.2 (no declare -A)
bash tests/necro-agent-codex-matches-test.sh      # @necromancer_codex_commands globs; default still matches the truncated native binary
bash tests/necro-agent-claude-matches-test.sh     # @necromancer_claude_commands globs; a plain name stays an exact match
bash tests/necro-autosave-daemon-lock-test.sh     # autosave daemon lock: one daemon per server
bash tests/necro-autosave-daemon-wiring-test.sh   # the TPM entrypoint actually starts the autosave daemon
bash tests/necro-autosave-rotation-pin-test.sh    # rotation never deletes the pinned reboot snapshot
bash tests/necro-clean-debug-logs-python-test.sh  # python cleaner removes logs only, never snapshots
bash tests/necro-debug-logging-test.sh            # debug logging is opt-in and writes structured events
bash tests/necro-reboot-resume-cleanup-test.sh    # reboot-resume idle-window cleanup keeps busy windows
bash tests/necro-restore-claim-existing-test.sh   # restore claims unmarked resurrect-created panes
bash tests/necro-restore-multipane-window-test.sh # multi-pane windows restore as splits, not flat windows
bash tests/necro-restore-safety-test.sh           # restore skips oversized transcripts and unsafe cwds
bash tests/necro-snapshot-idle-shell-test.sh      # idle shells trust only pane-local watcher state
bash tests/necro-watch-daemon-lock-test.sh        # watcher daemon lock: one daemon per server
```

For restore/snapshot changes, run against an **isolated tmux socket**:

```bash
tmux -L necrotest kill-server 2>/dev/null
# set NECROMANCER_SNAPSHOT_DIR to a tmpdir, exercise necro-restore.sh twice,
# assert window counts don't grow.
```

The TUI: `cd tui && go build ./... && go test ./...`.

Key things to verify after any change to restore/snapshot:
- snapshot captures an `agent` + `uuid` for every pane with a known cwd
- restore run twice → second run adds 0 windows, resumes 0 agents
- multi-agent: a `codex` record yields `codex resume <id>`
- autosave log has no `mapfile` errors and honors `@necromancer_max_snapshots`
- pinned UUID actually matches the pane's real process argv (not a stale or
  subagent transcript from the filesystem fallback)
- restoring multiple sessions pauses between resumes — doesn't fire every
  `claude`/`codex --resume` back-to-back
- restored multi-pane windows get their saved layout re-applied
  (`select-layout`) only when the live pane count matches the snapshot's
- resumed panes receive the configured post-resume message (default `continue`)
  after the resume, and none when the message is set empty

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for known failure modes
and their fixes. Key one: **sessions missing after reboot** — use `safe-reboot` /
`safe-shutdown` aliases instead of the Apple menu.

## Conventions

- Conventional-commit titles (`feat:`, `fix:`, `docs:`, …).
- No AI attribution in commits/PRs.
- Keep scripts dependency-light: bash, python3, jq, tmux. No node/ruby.
