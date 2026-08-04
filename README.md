# 🪦 tmux-ai-necromancer 🪦

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<img src="banner/github-banner.svg" width="100%" alt="tmux-ai-necromancer banner">

> Bring your dead AI coding sessions back to life.

`tmux-ai-necromancer` is a [TPM](https://github.com/tmux-plugins/tpm)-compatible
tmux plugin that does for **AI coding agent sessions** what
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) does for tmux
panes: it snapshots your running agent conversations on a timer and resurrects
them — with the exact session resumed — after a crash, reboot, or
`tmux kill-server`.

It is **multi-agent**: [Claude Code](https://claude.com/claude-code) and
[Codex](https://developers.openai.com/codex/cli/) work out of the box, and
adding another agent is one small adapter file.

Born from a real problem: tmux 3.6b crashes (heap corruption in copy mode) kept
killing 9 live Claude Code sessions at once, with no way to get them back.

## What it does

- 👁️ **Pane watcher** — pins each pane's session UUID the instant an agent starts.

- 💾 **Autosave** — snapshots every pane's agent + session id on a timer, in the background, without touching a running agent.

- 🧟 **Restore** — recreates sessions and resumes every agent, idempotently.

- 🔁 **Reboot survival** — pairs with tmux-resurrect + tmux-continuum to bring the whole layout back after a reboot.

- 🖥️ **Session viewer (TUI)** — a live viewer that joins panes against the latest snapshot.

## Quick start

Add to `~/.tmux.conf`, then press `prefix + I`:

```tmux
set -g @plugin 'RonenMars/tmux-ai-necromancer'
```

That's it — the autosave daemon starts immediately. See
[`docs/INSTALL.md`](docs/INSTALL.md) for manual install, dependencies, and WSL2.

## Key bindings

| Keys | Action |
|---|---|
| `prefix + a i` | Restore latest snapshot (popup) |
| `necro-menu` | Browse/restore/cleanup snapshots, prep for reboot |
| `necro-doctor.sh` | Check the plugin's health (read-only) |

Full command reference, including snapshot/restore scripts and recommended
aliases: [`docs/USAGE.md`](docs/USAGE.md).

## Documentation

| Topic | Doc |
|---|---|
| Installing (TPM, manual, dependencies, WSL2) | [`docs/INSTALL.md`](docs/INSTALL.md) |
| Commands, keybindings, recommended aliases | [`docs/USAGE.md`](docs/USAGE.md) |
| Tunable options and how to apply changes | [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) |
| Daemons, pane watcher, autosave, snapshot format | [`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md) |
| Supported agents and transcript stores | [`docs/SUPPORTED_AGENTS.md`](docs/SUPPORTED_AGENTS.md) |
| Adding a new agent adapter | [`docs/agents.md`](docs/agents.md) |
| Debug logging | [`docs/DEBUG_LOGGING.md`](docs/DEBUG_LOGGING.md) |

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for common issues:
sessions missing after reboot, the "inside tmux" guard, partial autosaves, and
idempotency behavior.

## License

MIT — see [LICENSE](LICENSE).
