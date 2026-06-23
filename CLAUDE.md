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

2. **Restore is idempotent via a stable window marker (`@necro_id` =
   `<cwd>|<uuid>`).** Do NOT key idempotency on window name (auto-renamed by the
   shell after first prompt) or `pane_current_path` (unset right after window
   creation). Re-running restore must add zero windows and re-resume zero
   agents.

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

## Testing

Self-contained bash tests live in `tests/`. Each uses `mktemp -d` + `NECROMANCER_SNAPSHOT_DIR`
for full isolation — no live tmux server required. Run any test directly:

```bash
bash tests/necro-autosave-lock-test.sh   # lock: only one concurrent autosave fires
bash tests/necro-context-codex-test.sh   # context enrichment for Codex sessions
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

## Conventions

- Conventional-commit titles (`feat:`, `fix:`, `docs:`, …).
- No AI attribution in commits/PRs.
- Keep scripts dependency-light: bash, python3, jq, tmux. No node/ruby.
