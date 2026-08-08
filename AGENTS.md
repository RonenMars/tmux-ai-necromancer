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

Two environment gotchas. Neither is a regression in the plugin, and the first
must not be "fixed" as part of unrelated work:

- **6 of 47 bash tests fail on this VM** purely from BSD-vs-GNU tool
  differences: `necro-doctor-test`, `necro-watch-lock-test`,
  `necro-autosave-stale-lock-test`, `necro-agent-min-epoch-filter-test`,
  `necro-agent-codex-min-epoch-test` all hit `stat -f %m` (BSD) which on GNU
  `stat` prints filesystem info to stdout before failing, contaminating the
  `|| stat -c %Y` fallback; `necro-snapshot-empty-answer-aborts-test` uses the
  util-linux `script` whose flags differ from BSD `script`. The other 41 pass,
  and the whole restore/snapshot engine works on Linux.
- **tmux 3.5a escapes the `0x1f` field separator; 3.6 and later do not.**
  `list-panes -F` renders the ASCII Unit Separator as the four literal
  characters `\037`, so any consumer splitting on a real `0x1f` sees one field
  per line. Measured on binaries built from source: 3.5a emits **zero** raw
  `0x1f` bytes, 3.6 and 3.7b emit the raw byte. This is handled now — the Go
  parser retries with the escaped form and `necro-watch.sh` unescapes before
  its read loop — so the VM's tmux 3.5a is no longer a problem. Do not
  "simplify" either unescape away on the grounds that tmux emits a raw byte;
  that is only true from 3.6 on. Covered by
  `tests/necro-watch-escaped-separator-test.sh` and
  `tui/internal/tmux/parse_panes_test.go`.

  If a pane table is empty anyway, read the `list_panes_complete` debug event
  before theorising: it reports `server: absent` when no tmux server is
  running on the default socket (`ListPanes` returns zero panes and no error,
  which looks identical to a parse bug) and a `dropped` count when rows
  genuinely fail to parse.
