# Supported agents

| Agent | Transcript store | Resume |
|---|---|---|
| Claude Code | `~/.claude/projects/<cwd>/<uuid>.jsonl` | `claude --resume <uuid>` |
| Codex | `~/.codex/sessions/<date>/rollout-*-<uuid>.jsonl` | `codex resume <uuid>` |

The two differ in ways worth knowing: Claude transcripts are foldered per
working directory, Codex rollouts are not, so Codex resolves a cwd by reading
the meta line of the 200 most-recent rollouts. The Claude-only transcript size
guard doesn't apply to Codex either. See
[Codex-specific behavior](TROUBLESHOOTING.md#codex-specific-behavior).

Want another agent? See [`agents.md`](agents.md) — it's one file.
