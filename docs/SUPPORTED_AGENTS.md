# Supported agents

| Agent | Transcript store | Resume |
|---|---|---|
| Claude Code | `~/.claude/projects/<cwd>/<uuid>.jsonl` | `claude --resume <uuid>` |
| Codex | `~/.codex/sessions/<date>/rollout-*-<uuid>.jsonl` | `codex resume <uuid>` |
| Cursor Agent | `~/.cursor/chats/<md5(cwd)>/<uuid>/` | `cursor-agent --resume <uuid>` |

The two differ in ways worth knowing: Claude transcripts are foldered per
working directory, Codex rollouts are not, so Codex resolves a cwd by reading
the meta line of the 200 most-recent rollouts. The Claude-only transcript size
guard doesn't apply to Codex either. See
[Codex-specific behavior](TROUBLESHOOTING.md#codex-specific-behavior).

Cursor panes report `node` as their foreground command (the CLI re-execs through a
bundled node), so the adapter confirms from the process argv before claiming a
pane. It only ever claims `node`/`agent` panes whose process runs the
`cursor-agent/versions/…` bundle, and cannot read previews from `store.db`.
An agent suspended with Ctrl-Z is not recognised as alive by the watcher.
Cursor is enabled by default since #66; to opt out, set
`set -g @necromancer_agents "claude codex"`. Interactive exit-capture sends no
exit keys to Cursor (its quit command is unverified), so it records the newest
chat for the cwd instead. Chat folders are keyed by the cwd's physical path, so
a symlinked cwd is resolved before hashing.

Want another agent? See [`agents.md`](agents.md) — it's one file.
