# Continuous integration

Three workflows in `.github/workflows/`, all running on pushes to `main` and on
every pull request.

## `tests.yml` — bash suite + syntax check

Runs `bash -n` over every script, then the whole `tests/*-test.sh` suite, on a
two-OS matrix.

The `macos-latest` leg is the important one. GitHub's macOS image preinstalls
Homebrew bash 5 ahead of `/bin/bash` on `PATH`, so a plain run would resolve
`#!/usr/bin/env bash` to bash 5 — exactly the blind spot that lets a bash-4
construct ship. A step symlinks `/bin/bash` into a temp dir and prepends it to
`$GITHUB_PATH`, so both `env bash` and the tests' own `bash <script>` calls
resolve to stock 3.2. That enforces [invariant 13](../CLAUDE.md) in CI: a
`declare -A` or `mapfile` reaching `necro-restore.sh` produces a **silent
0-session restore** on any stock Mac, and no local run on a dev box with
Homebrew bash can catch it.

The suite needs no tmux server and no network — each test uses `mktemp -d` plus
`NECROMANCER_SNAPSHOT_DIR` for isolation.

## `shellcheck.yml` — lint

`ludeeus/action-shellcheck` with `-S error -s bash`. Error severity only, on
purpose: it catches the traps this repo has actually hit (unquoted variables
that don't word-split, IFS handling in the pane walk) without burying the run
in style warnings. `tmux-ai-necromancer.tmux` is passed via `additional_files`
since it has no `.sh` extension.

If a run goes red, read the findings — don't lower the severity.

## `tui.yml` — Go

`go build`, `go vet`, `go test` in `tui/`, pinned to the `go.mod` version and
path-filtered to `tui/**` so plugin-only changes skip it.

## Running the same checks locally

```bash
for t in tests/*-test.sh; do bash "$t" || echo "FAILED: $t"; done
for f in scripts/*.sh lib/*.sh lib/agents/*.sh *.tmux; do bash -n "$f"; done
cd tui && go build ./... && go vet ./... && go test ./...
```

To reproduce the bash 3.2 leg on a Mac with Homebrew bash installed, run the
suite with the stock interpreter explicitly:

```bash
for t in tests/*-test.sh; do /bin/bash "$t" || echo "FAILED: $t"; done
```
