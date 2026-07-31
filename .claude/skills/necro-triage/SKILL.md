---
name: necro-triage
description: Diagnose and fix tmux-ai-necromancer on this machine. Use when sessions did not come back, autosave seems stopped, snapshots are missing or empty, agent panes have no UUID, a lock looks stuck, a daemon is not running, restore duplicates or flattens windows, or a test fails. Also use before changing any script in this repo, to establish a healthy baseline first.
---

# necro-triage

Diagnose, verify, and fix `tmux-ai-necromancer` against the local environment.

**The one rule that matters:** a running daemon proves scheduling works and
nothing more. In July 2026 autosave was silently dead for ~12 of 13 days while
both daemons ran, the watcher pinned UUIDs correctly, and every liveness check
reported green. Read `docs/incidents/2026-07-autosave-lock-outage.md` before
trusting any process-based signal.

## Step 1 — always start here

```bash
scripts/necro-doctor.sh
```

Read-only: sends no keys, kills nothing, writes nothing. Safe against a live
server, including from inside tmux. Exit `1` if it found a problem (`✗`), `0`
if only warnings (`⚠`).

Do not skip it and do not start from the logs. Debug logging is **off** by
default, so logs usually do not exist — and when they do they lie by omission,
because they record what the code *said*, not what it *produced*.

## Step 2 — map the finding to a cause, a test, and a fix

| Doctor reports | What it means | Verify with | Fix |
|---|---|---|---|
| `autosave lock held for <long>` | A work subshell died without releasing it. Autosave is **stopped**, not slow. | `necro-autosave-stale-lock`, `necro-autosave-lock-lifetime` | Should self-heal on the next *due* autosave (up to one `@necromancer_interval`). If it persists past that, `rmdir` the lock and treat the recovery itself as broken. |
| `watcher lock held for <long>` | UUID pinning has stopped. | `necro-watch-lock` | Self-heals after 60s. If not, the age break-in is broken. |
| `<daemon> is NOT running` | Nothing is scheduling work. | `necro-autosave-daemon-lock`, `necro-watch-daemon-lock`, `necro-autosave-daemon-wiring` | `tmux run-shell -b scripts/necro-<name>-daemon.sh`, or re-source tmux.conf. |
| `lock records pid X but live process is Y` | Harmless right after a restart; persistent means a second daemon was blocked. | daemon lock tests | Usually nothing. |
| `N of M agent pane(s) have a pinned UUID` | The watcher cannot resolve an id for those panes. | `necro-watch-priority-order`, `necro-agent-scrape-ps-resume`, `necro-agent-min-epoch-filter`, `necro-agent-pop-cursor` | Check the pane's command matches an adapter (`@necromancer_claude_commands` / `@necromancer_codex_commands`). A fresh agent pins within a tick. |
| `no record names an agent` | Adapters are not recognising your panes. | `necro-agent-claude-matches`, `necro-agent-codex-matches` | `@necromancer_agents` must list the agent; the command name must match its list. |
| `agent record(s) carry no UUID` | Those sessions **cannot be resumed**. Restore will recreate the pane and stop. | `necro-snapshot-idle-shell`, watcher tests above | Fix pinning first; snapshots only record what the watcher resolved. |
| `last written <long> ago` | Autosave is not completing. Almost always a lock. | autosave tests | See the lock rows. |
| `snapshot is empty` | Restore would rebuild nothing. | `necro-snapshot-default-idle-only` | Check the pane walk and `@necromancer_agents`. |
| `pointer is dangling` | `necro-reboot-resume.sh` falls back to the newest autosave. | `necro-menu-cleanup-pin`, `necro-autosave-rotation-pin`, `necro-reboot-resume-cleanup` | Re-run `necro-reboot-prep.sh` or delete the pointer. |
| adapter `missing` / not loaded | An enabled agent has no adapter file or an incomplete one. | `necro-agent-*` | See `docs/agents.md` — the contract is seven functions. |
| all green but restore misbehaves | Duplicated windows, flattened splits, wrong layout. | `necro-restore-claim-group`, `necro-restore-multipane-window`, `necro-restore-claim-existing`, `necro-restore-layout`, `necro-restore-safety`, `necro-restore-bash32` | Invariant 2 (per-**pane** marker) and invariant 13 (bash 3.2). |

## Step 3 — run the tests

Targeted first, using the table above:

```bash
bash tests/<name>-test.sh
```

Then the full suite before claiming anything is fixed. Always isolate:

```bash
export NECROMANCER_SNAPSHOT_DIR="$(mktemp -d)"
for t in tests/*-test.sh; do bash "$t" >/dev/null 2>&1 || echo "FAILED: $t"; done
```

Tests need no live tmux server. If one fails, read it before reading the code —
each test's header states the regression it guards.

## Step 4 — fixing

Before you change a script:

- **Reproduce first.** If there is no test for the behaviour, write one and
  watch it fail. Then fix. Then watch it pass. A test that has never been red
  proves nothing — two fixes in this repo's history were wrong on the first
  attempt and only the red-green cycle caught them.
- **Read `CLAUDE.md`'s invariants.** All 14 encode a production bug. Contradicting
  one is a regression, not a cleanup.
- **bash 3.2 only** (invariant 13). No `declare -A`, no `mapfile`, no `BASHPID`,
  no `${var,,}`. Verify with `/bin/bash -n <script>` — not your Homebrew bash.
- **`set -uo pipefail`, never `set -e`** (invariant 1).

After you change a script:

```bash
/bin/bash -n <changed scripts>            # bash 3.2 syntax
bash tests/<targeted>-test.sh             # the behaviour you touched
# then the full isolated suite above
```

Update `CLAUDE.md`'s test index if you added a test, and its script map if you
added a script. The doctor's own test asserts it stays read-only.

## Never do these against a live tmux server

These mutate or destroy real state. In a sandbox (`tmux -L necrotest` plus a
`mktemp -d` snapshot dir) they are fine.

- `scripts/necro-prune.sh` — kills windows.
- `scripts/necro-snapshot.sh --interactive` / `--yes` — sends exit keys to live
  agents. It refuses without a real tty (invariant 14); do not defeat that.
- `scripts/necro-menu.sh` cleanup actions — delete snapshots.
- Anything that calls `tmux send-keys`, `kill-window`, or `kill-session`.

Reading is always safe: `necro-doctor.sh`, `necro-restore.sh --dry-run`,
`necro-prune.sh --dry-run`, `tmux list-panes`, `show-option`.

## When logs are gone, use artifacts

Debug logs are off by default and get cleaned. Snapshot files, lock directory
mtimes, and `ls -t` ordering survive and are more trustworthy — they record what
the system *produced*. The July 2026 timeline was reconstructed entirely from
snapshot mtimes after the logs had been wiped.

To turn logging on for an investigation:

```bash
tmux set-option -g @necromancer_debug on
# reproduce
scripts/necro-log-divider.sh "what I am about to do"
# ... then when finished
scripts/necro-clean-debug-logs.sh
tmux set-option -g @necromancer_debug off
```

It costs ~13 MB/day and nothing prunes it automatically.

## Reference

- `docs/incidents/2026-07-autosave-lock-outage.md` — worked example of a silent failure
- `docs/TROUBLESHOOTING.md` — user-facing symptoms
- `docs/agents.md` — the adapter contract
- `CLAUDE.md` — architecture and the 14 invariants
