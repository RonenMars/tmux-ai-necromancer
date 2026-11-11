# Adding an agent adapter

`tmux-ai-necromancer` is agent-agnostic. Support for a new AI coding agent is a
single file in `lib/agents/<name>.sh` plus adding `<name>` to
`@necromancer_agents`.

## The contract

Implement these functions, prefixed `agent_<name>_` (optional ones may be omitted):

```bash
# Is this pane's foreground command your agent?
agent_<name>_matches() { [ "$1" = "<binary>" ]; }
# Optional 2nd arg: the pane id. Use it when the foreground command is too
# generic to trust (Cursor reports `node`) and confirm from the process argv.

# Most-recent resumable session id for a working directory (filesystem
# fallback). Echo the id, or nothing if none. This is the workhorse for
# unattended autosave, where the agent is still running and can't be exited.
agent_<name>_latest_session_id() { ... }

# Optional: scrape a session id from pane scrollback near a "resume" marker.
# Used only during interactive capture after a clean exit. Return "" if N/A.
agent_<name>_scrape_session_id() { ... }

# Optional: scrape a `--resume <uuid>` startup line from scrollback.
# Used by the watcher on first detection to handle resurrect-restored panes.
# Return "" if N/A.
agent_<name>_scrape_resume_cmd() { ... }

# Optional: read the session id straight from the pane's foreground process
# argv (e.g. `ps` on the pane's child PID) instead of guessing from
# scrollback or a filesystem cursor. This is ground truth when available —
# the watcher tries it first. Return "" if N/A (e.g. a fresh, non-resumed
# session has no id here yet — that's not a failure).
agent_<name>_scrape_ps_resume() { ... }

# Optional: the session id the agent itself records for its live process,
# given the pane's PID (Claude: ~/.claude/sessions/<pid>.json, checked for the
# pane process and its children). The watcher tries it before argv, and
# re-checks every pinned pane against it each tick, so a /clear or a relaunch
# within one tick re-pins. Must not call tmux (invariant 15). Return "" if N/A.
# Only "kind": "interactive" files count: a headless child is not the pane.
agent_<name>_live_session_id() { ... }

# Optional: background sessions with no pane (Claude: `claude --bg`). Print
# one TSV line per LIVE one: id, cwd, name, parent pane (or ""). The snapshot
# records each as a pane-less "kind":"bg" record. Judge liveness by the
# process (kill -0), not by a state file: those outlive a killed process.
agent_<name>_bg_sessions() { ... }

# Optional: exit 0 if a live process of this agent holds the session id.
# Restore relaunches a bg record only when this says no; without it, a
# relaunch of a still-running session would start a second copy.
agent_<name>_session_running() { ... }

# Optional: the command that relaunches a bg record detached, in its cwd.
agent_<name>_bg_resume_cmd() { printf '<binary> --bg --resume %s' "$1"; }

# Optional: return 0 if this pane's recent scrollback shows a rate/session
# limit banner (Claude: "hit your session limit"; Codex: "hit your usage
# limit"). Used by necro-snapshot.sh --rate-limited and the watcher's
# throttled auto-save. Omit (or always return 1) if the agent has no such
# banner.
agent_<name>_hit_limit() { ... }

# The shell command that resumes a session id.
agent_<name>_resume_cmd() { printf '<binary> resume %s' "$1"; }

# Keys to send for a clean exit during interactive capture (e.g. "/exit").
agent_<name>_exit_keys() { printf '/exit'; }
```

## How session ids are recovered

Three strategies, in priority order:

1. **Process argv (`scrape_ps_resume`)** — ground truth: reads the id the
   pane's agent process was actually launched with. Preferred whenever
   available; nothing to guess. Returns "" for a fresh session that was never
   resumed — there's no id to report yet, not a failure.
2. **Scrollback scrape** — high confidence, but only works when the agent was
   cleanly exited interactively and printed a resume hint that's still on
   screen, or the pane's scrollback still holds the startup `--resume` line.
   Most agents won't have this; returning "" is fine.
3. **Filesystem fallback** — last resort, used only when neither of the above
   yields an id (typically a genuinely fresh session). Maps a working
   directory to the agent's most-recent transcript. Because it can't verify
   which pane a transcript actually belongs to, treat it as a guess: filter
   out anything that clearly isn't a standalone interactive session (e.g.
   `claude.sh` excludes teammate/subagent transcripts from this list), and
   honor an optional `min_epoch` filter (see below) so a stale transcript
   can't be handed to a pane that didn't exist yet when it was last touched.

### `min_epoch` filtering on the filesystem fallback

`agent_<name>_all_session_ids "$cwd" ["$min_epoch"]` takes an optional second
argument: an epoch-seconds floor. When present, only transcripts touched at or
after that time are candidates. The watcher passes the pane's
`@necro_pane_first_seen` stamp (the closest proxy tmux offers for "when this
pane was created" — tmux has no true creation timestamp) so a transcript from
days/weeks before the pane existed is never eligible, no matter where it falls
in the newest-mtime-first ordering. Both reference adapters implement it;
an adapter that doesn't simply ignores the extra argument — it's optional,
not part of the required contract.

The two reference adapters show both shapes:

- **`claude.sh`** — transcripts are foldered by cwd
  (`~/.claude/projects/<cwd-as-dashes>/<uuid>.jsonl`), so the fallback is a
  simple newest-file lookup. It also scrapes the `claude --resume <uuid>`
  farewell line.
- **`codex.sh`** — transcripts are date-nested and NOT foldered by cwd
  (`~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`). The cwd lives
  inside the first `session_meta` line, so the fallback scans recent rollouts
  newest-first and matches on that embedded cwd. No reliable scrollback hint, so
  the scrape returns "". Three details worth copying if your agent stores
  sessions the same way:
  - The scan is **bounded to the 200 most-recent rollouts** for speed. Without
    a per-cwd directory there is nothing to narrow the search by, so an
    unbounded scan would read every rollout ever written on every lookup. The
    cost is that a session older than the last 200 is invisible to the
    fallback.
  - The cwd comparison is **case-folded**. Codex canonicalizes the recorded cwd
    to lowercase, and macOS filesystems are case-insensitive, so a literal
    match would miss any path with capitals (`tb-PRs-follow` vs
    `tb-prs-follow`).
  - `agent_codex_scrape_ps_resume` matches the **subcommand** form
    `codex resume <uuid>`, not a `--resume <uuid>` flag. Read your agent's
    actual argv before writing this function; the flag form is not universal.

- **`copilot.sh`** — one folder per session under `~/.copilot/session-state/`;
  the cwd is the `cwd:` line of `workspace.yaml` (physical path, so resolve
  symlinks first). Only sessions with an `events.jsonl` are resumable. Resume
  is the flag form `copilot --resume <uuid>`, read from argv. It defines no
  `agent_copilot_exit_keys` on purpose: an adapter without that function is
  never sent keys by interactive capture, and the snapshot records the
  filesystem id instead (`cursor.sh` does the same).

## Command name matching

`agent_<name>_matches` is called with `pane_current_command` — the process
name the kernel sees. The bundled adapters read a space-separated list of
command names from a tmux option, so an alias or wrapper script named
differently needs a config change, not a code change:

| Option | Default | Matches |
|---|---|---|
| `@necromancer_claude_commands` | `claude` | Claude Code |
| `@necromancer_codex_commands` | `codex codex-*` | Codex |
| `@necromancer_cursor_commands` | `cursor-agent node agent` | Cursor Agent (`node`/`agent` only with the Cursor bundle in argv) |
| `@necromancer_copilot_commands` | `copilot` | GitHub Copilot CLI |

```tmux
set -g @necromancer_claude_commands 'claude cc'
set -g @necromancer_codex_commands  'codex codex-* cx'
```

Entries are **glob patterns**, not exact strings. A plain name matches only
itself, so existing config keeps working, but a pattern lets one entry cover a
family of names. That is why the Codex default is two entries: tmux reports the
native binary's truncated basename (`codex-aarch64-a` for
`codex-aarch64-apple-darwin`), so `codex-*` catches it while `codex` catches
the wrapper. Note the list is split with globbing disabled, so a pattern is
never accidentally expanded against the working directory.

Other agents: implement `agent_<name>_matches` to match however your binary
appears in `pane_current_command`. Reading your own
`@necromancer_<name>_commands` option is the friendlier pattern — copy either
bundled adapter.

## Register it

```tmux
set -g @necromancer_agents 'claude codex cursor copilot <name>'
```

Adapters are sourced on demand; an unknown name just logs a warning and is
skipped. That's all — snapshot, restore, apply, and the TUI pick it up
automatically because they only ever talk to the dispatcher in `lib/agents.sh`.

## Test it

```bash
source lib/common.sh
source lib/agents/<name>.sh
agent_<name>_latest_session_id "/path/to/a/project/you/used"
agent_<name>_resume_cmd "<that-id>"
```

You should get back a real id and a runnable resume command.
