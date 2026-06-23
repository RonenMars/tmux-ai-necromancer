# Adding an agent adapter

`tmux-ai-necromancer` is agent-agnostic. Support for a new AI coding agent is a
single file in `lib/agents/<name>.sh` plus adding `<name>` to
`@necromancer_agents`.

## The contract

Implement these five functions, prefixed `agent_<name>_`:

```bash
# Is this pane's foreground command your agent?
agent_<name>_matches() { [ "$1" = "<binary>" ]; }

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

# The shell command that resumes a session id.
agent_<name>_resume_cmd() { printf '<binary> resume %s' "$1"; }

# Keys to send for a clean exit during interactive capture (e.g. "/exit").
agent_<name>_exit_keys() { printf '/exit'; }
```

## How session ids are recovered

Two strategies, in priority order:

1. **Scrollback scrape** — high confidence, but only works when the agent was
   cleanly exited interactively and printed a resume hint that's still on
   screen. Most agents won't have this; returning "" is fine.
2. **Filesystem fallback** — the reliable path for autosave. Map a working
   directory to the agent's most-recent transcript and extract its id.

The two reference adapters show both shapes:

- **`claude.sh`** — transcripts are foldered by cwd
  (`~/.claude/projects/<cwd-as-dashes>/<uuid>.jsonl`), so the fallback is a
  simple newest-file lookup. It also scrapes the `claude --resume <uuid>`
  farewell line.
- **`codex.sh`** — transcripts are date-nested and NOT foldered by cwd
  (`~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`). The cwd lives
  inside the first `session_meta` line, so the fallback scans recent rollouts
  newest-first and matches on that embedded cwd. No reliable scrollback hint, so
  the scrape returns "".

## Command name matching

`agent_<name>_matches` is called with `pane_current_command` — the process
name the kernel sees. For Claude Code, this is `claude` by default, but if
you run it via an alias or wrapper script named differently (e.g. `cc`), add
your command name to `@necromancer_claude_commands`:

```tmux
set -g @necromancer_claude_commands 'claude cc'
```

Other agents: implement `agent_<name>_matches` to match however your binary
appears in `pane_current_command`.

## Register it

```tmux
set -g @necromancer_agents 'claude codex <name>'
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
