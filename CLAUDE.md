# CLAUDE.md

Operating manual for AI agents (and humans) working in this repository.

## What this repo is

`tmux-ai-necromancer` is a TPM-compatible tmux plugin that snapshots running AI
coding-agent sessions (Claude Code, Codex, …) and resurrects them after a crash
or reboot. Pure bash + a small Go TUI. No build step for the plugin itself.

## Architecture (read before editing)

```
tmux-ai-necromancer.tmux   TPM entrypoint — wires autosave + watcher into status-right, binds restore key
scripts/                   the executables (all source lib/*.sh)
  necro-snapshot.sh        walk panes → JSONL snapshot (per-agent id capture)
  necro-autosave.sh        status-right hook; throttled background snapshot + rotation
  necro-watch.sh           status-right hook; per-tick pane watcher — pins @necro_uuid/@necro_agent to panes
  necro-restore.sh         rebuild sessions/windows from a snapshot (IDEMPOTENT)
  necro-apply.sh           reorganize LIVE panes into dest sessions + resume
  necro-context.sh         enrich a snapshot with conversation previews
  necro-reboot-prep.sh     pre-reboot: snapshot + enrich + resurrect save + pin pointer
  necro-reboot-resume.sh   post-reboot: ensure server up → necro-restore.sh
  necro-prune.sh           kill windows whose panes are all idle shells (no child procs)
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
   same key `split-window` into it (tracked via `WIN_FOR_GROUP`). This
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
   `mkdir` is the only POSIX-safe atomic primitive here; `trap ... EXIT` cleans
   up on any exit path.

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

## Testing

Self-contained bash tests live in `tests/`. Each uses `mktemp -d` + `NECROMANCER_SNAPSHOT_DIR`
for full isolation — no live tmux server required. Run any test directly:

```bash
bash tests/necro-autosave-lock-test.sh   # lock: only one concurrent autosave fires
bash tests/necro-context-codex-test.sh   # context enrichment for Codex sessions
bash tests/necro-prune-idle-window-test.sh  # prune kills idle windows, keeps busy ones
bash tests/necro-agent-scrape-ps-resume-test.sh   # ps-argv is ground truth for pane UUID pinning
bash tests/necro-agent-scrape-ps-resume-multichild-test.sh  # finds claude among sibling processes
bash tests/necro-agent-min-epoch-filter-test.sh   # cursor-pop fallback rejects stale transcripts
bash tests/necro-watch-priority-order-test.sh     # argv > scrollback > cursor-pop, end-to-end
bash tests/necro-watch-first-seen-persistence-test.sh      # first-seen stamp doesn't drift across ticks
bash tests/necro-watch-first-seen-reset-on-restart-test.sh # first-seen resets on agent relaunch
bash tests/necro-restore-resume-delay-test.sh     # resume launches are paced, not fired all at once
bash tests/necro-restore-batch-skips-test.sh      # skipped records don't consume a pacing batch slot
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

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for known failure modes
and their fixes. Key one: **sessions missing after reboot** — use `safe-reboot` /
`safe-shutdown` aliases instead of the Apple menu.

## Conventions

- Conventional-commit titles (`feat:`, `fix:`, `docs:`, …).
- No AI attribution in commits/PRs.
- Keep scripts dependency-light: bash, python3, jq, tmux. No node/ruby.
