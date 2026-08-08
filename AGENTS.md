# AGENTS.md — tmux-ai-necromancer

Project instructions for Codex and any agent that reads `AGENTS.md`.
Claude Code reads `CLAUDE.md` instead; both describe the same repo.

## Before anything else

`CLAUDE.md` is the operating manual: architecture, the agent-adapter contract,
and **14 hard-won invariants**. Every invariant encodes a production bug.
Contradicting one is a regression, not a cleanup. Read it first.

## Troubleshooting and fixing the local environment

Follow the **`necro-triage`** skill — doctor first, then a finding → test → fix
table, then the rules for changing code safely.

It is one file, `.claude/skills/necro-triage/SKILL.md`, with
`.codex/skills/necro-triage` a relative symlink to it. Codex discovers it as a
repo-local skill (verified on codex-cli 0.146.0) and resolves it through the
symlink to that path, so both tools read the same bytes and cannot drift. To
confirm on your machine, from the repo root:

```bash
codex debug prompt-input | grep -i necro-triage
```

That renders what Codex actually sends the model. Discovery is cwd-dependent —
run it from the repo. If a future version stops discovering repo-local skills,
this file still names the path; read it directly.

The short version:

```bash
scripts/necro-doctor.sh     # read-only. Start here, always.
```

A running daemon proves scheduling works and **nothing more**. Autosave was
silently dead for ~12 of 13 days in July 2026 while every liveness signal
reported green — see `docs/incidents/2026-07-autosave-lock-outage.md`. The
snapshot's age and how many of its records carry a UUID are the checks that
actually matter.

## Hard constraints

- **bash 3.2 only.** macOS ships `/bin/bash` 3.2 and tmux `run-shell` inherits
  the server's PATH. No `declare -A`, `mapfile`, `BASHPID`, or `${var,,}`.
  Verify with `/bin/bash -n <script>`, not your own newer bash.
- **`set -uo pipefail`, never `set -e`.** Pipelines here legitimately exit
  non-zero on no-match; `-e` kills the pane walk mid-loop.
- **Never `set -e`-abort on a tmux call.** Guard with `|| true` and warn.
- Dependency-light: bash, python3, jq, tmux. No node, no ruby.

## Testing

Self-contained, no live tmux server needed. Always isolate:

```bash
export NECROMANCER_SNAPSHOT_DIR="$(mktemp -d)"
for t in tests/*-test.sh; do bash "$t" >/dev/null 2>&1 || echo "FAILED: $t"; done
```

New behaviour needs a test that you have **watched fail** before the fix. Two
fixes in this repo were wrong on the first attempt and only the red-green cycle
caught them. Add new tests to `CLAUDE.md`'s index, and new scripts to its map.

## Never run these against a live tmux server

`necro-prune.sh` (kills windows), `necro-snapshot.sh --interactive` / `--yes`
(sends exit keys to live agents), and the `necro-menu.sh` cleanup actions
(delete snapshots). Use `tmux -L necrotest` plus a `mktemp -d` snapshot dir.

Read-only and always safe: `necro-doctor.sh`, any `--dry-run`, `tmux
list-panes`, `tmux show-option`.

## Conventions

- Conventional-commit titles (`feat:`, `fix:`, `docs:`, …).
- No AI attribution in commits or PRs.
- Branch → PR → squash-merge. Never commit to `main` directly.

## Cursor Cloud specific instructions

The Cloud VM is **Ubuntu/Linux with GNU coreutils**, but this plugin targets
**macOS (bash 3.2, BSD tools)**. Toolchain is preinstalled: `bash`, `python3`,
`jq`, `tmux 3.5a`, `go`, `node`+`npm`. The startup update script only refreshes
language deps (`tui` Go modules, `website` npm) — the bash plugin itself needs
no install.

Three components, each run as documented elsewhere:

- **Core plugin (bash)** — main product. Tests: the isolated loop in the
  *Testing* section above. Live snapshot→restore: the `tmux -L necrotest` +
  `mktemp -d` pattern in `CLAUDE.md`.
- **TUI (Go)** — `tui/`. `make build` / `make test` / `make run` (see
  `tui/README.md`).
- **Website (Vite + React)** — `website/`, entirely separate from the plugin.
  `npm run dev` (serves on `http://localhost:5173/`), `npm run lint`,
  `npm run build`.

Two **Linux-only, pre-existing** gotchas — not regressions, do not "fix" them
as part of unrelated work:

- **6 of 47 bash tests fail on this VM** purely from BSD-vs-GNU tool
  differences: `necro-doctor-test`, `necro-watch-lock-test`,
  `necro-autosave-stale-lock-test`, `necro-agent-min-epoch-filter-test`,
  `necro-agent-codex-min-epoch-test` all hit `stat -f %m` (BSD) which on GNU
  `stat` prints filesystem info to stdout before failing, contaminating the
  `|| stat -c %Y` fallback; `necro-snapshot-empty-answer-aborts-test` uses the
  util-linux `script` whose flags differ from BSD `script`. The other 41 pass,
  and the whole restore/snapshot engine works on Linux.
- **The TUI's live pane table may show 0 rows on this VM.** Cause unconfirmed.
  An earlier note here blamed tmux ≥ 3.5 escaping the ASCII Unit-Separator
  (`0x1f`) that `list-panes -F` uses between fields; that does not reproduce —
  on tmux 3.7b the separator round-trips as a raw byte (even inside a value)
  and `ListPanes` parses every pane, and tmux's 3.5 changelog entry about
  octal escapes covers input parsing and `list-keys` output, not `list-panes
  -F`. Before assuming a parse bug, check the far likelier explanation: with
  no tmux server on the default socket `ListPanes` returns zero panes and no
  error, which looks identical. Read the `list_panes_complete` debug event —
  it reports `server: absent` for that case and a `dropped` count when rows
  actually fail to parse.
