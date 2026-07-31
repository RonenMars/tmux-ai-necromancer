# Incident: autosave silently stopped for ~12 of 13 days

**Component:** `necro-autosave.sh` work lock (`$SNAP_DIR/.autosave.lock`)
**First outage:** 2026-07-18 12:35 → 2026-07-25 21:35 (7d 9h)
**Second outage:** 2026-07-25 21:53 → 2026-07-30 13:09 (4d 15h)
**Detected by:** `necro-doctor.sh`, on its first ever run
**Fixed by:** [#27](https://github.com/RonenMars/tmux-ai-necromancer/pull/27)

This file is kept as a worked example for whoever — human or agent —
investigates the next failure of this kind. The lesson is not "a lock got
stuck". It is that **every signal available at the time said the system was
healthy**, and the one signal that would have caught it was not being looked at.

---

## Summary

The autosave work lock is acquired by `necro-autosave.sh`, and released by an
`EXIT` trap inside the backgrounded work subshell. If that subshell dies to a
signal the trap cannot catch, the lock survives. At the time there was no
recovery path, so every subsequent tick failed `mkdir`, logged
`reason=lock_held`, and exited.

The result is a **silent, permanent stop**. No error is raised anywhere. The
daemon keeps running and keeps reporting as running. The watcher keeps pinning
UUIDs correctly. The only symptom is a snapshot file that stops advancing —
and nothing was watching that.

It happened twice. Clearing the lock by hand after the first outage restored
service for **18 minutes** before it wedged again, which is what elevates this
from a freak event to a design defect.

## Timeline

| When | What |
|---|---|
| 2026-07-18 12:35:32 | A snapshot is written. Its run's subshell dies without releasing the lock. |
| 2026-07-18 → 07-25 | **Outage 1.** Zero snapshots for 7 days. Daemon healthy throughout. |
| 2026-07-25 01:20 | [#21](https://github.com/RonenMars/tmux-ai-necromancer/pull/21) merges, adding recovery for the *daemon* locks. It does not touch the *work* lock. |
| 2026-07-25 19:50 | A manual log analysis correctly identifies the stale work lock and recommends adding recovery to `necro-autosave.sh` itself (see appendix). |
| 2026-07-25 21:35–21:40 | Lock cleared by hand. Two snapshots written. Service restored. |
| 2026-07-25 21:53:08 | Lock acquired again. Snapshot written at 21:53:10. **Subshell dies again.** |
| 2026-07-25 → 07-30 | **Outage 2.** Zero snapshots for 4½ days. |
| 2026-07-30 ~13:00 | `necro-doctor.sh` is written and run for the first time. It reports the lock held 4d 14h and the newest snapshot 4d 14h old. |
| 2026-07-30 13:09:57 | Lock cleared. Autosave completes within 3 seconds. |
| 2026-07-30 (later) | [#27](https://github.com/RonenMars/tmux-ai-necromancer/pull/27) adds work-lock recovery, verified against the live daemon. |

Only **four** snapshots exist between 18 and 30 July: one on the 18th, three on
the 25th.

## Impact

For roughly 12 of 13 days, a crash or reboot would have restored sessions from
a snapshot up to a week stale. `necro-reboot-prep.sh` would still have produced
a fresh snapshot on demand, so the exposure was limited to unplanned loss — but
that is precisely the case the plugin exists for.

## Why nothing detected it

This is the part worth studying.

**"Daemon running" was true and useless.** Both daemons were alive and ticking
the entire time. Any check based on process liveness — `pgrep`, `launchctl
list`, a PID in a lock file — reported green through both outages. The daemon
was never the thing that failed; the *work* was.

**A monitor was running and did detect it, and nobody read the output.** An
hourly sampler recorded `lock=present` on 23 of 24 samples starting from its
first sample after the wedge. It wrote to a file no one opened. It has since
been deleted; an unread signal is not a signal.

**A correct written diagnosis existed for six days and was not implemented.**
The appendix below is dated 2026-07-25 19:50. Its recommendation #2 is
precisely what #27 eventually did. Outage 2 ran for its entire duration with
the fix already specified in a file on disk.

**Two metrics actively misled.** The monitor's `error_matches` counter rose by
exactly one per sample and looked like a slow-burning fault; it was counting
its own log line, because the file it wrote lived in the directory it grepped
and every line contained the string it searched for. Its log-size counters were
cumulative and never differenced, so they always rose and never indicated
anything.

**The evidence was almost destroyed.** By the time of the investigation the
debug logs had been cleaned and only reached back four days. The forensic
timeline was reconstructed from **snapshot file mtimes**, which survived
because they are data rather than logs. When logs are gone, look at what the
system *produced*, not what it *said*.

## Root cause

`.autosave.lock` was the only lock in the plugin with no recovery path.

| Lock | Recovery at the time |
|---|---|
| `.watch.lock` | breaks on age > 60s |
| `.autosave-daemon.lock` | pid-based reclaim (#21) |
| `.watch-daemon.lock` | pid-based reclaim (#21) |
| `.autosave.lock` | **none** — `mkdir \|\| exit 0` |

#21 fixed the daemon locks four months' worth of attention earlier in the same
week and stopped one step short. The work lock looks similar enough to the
daemon lock that it reads as already covered.

## The fix

[#27](https://github.com/RonenMars/tmux-ai-necromancer/pull/27): the work
subshell stamps its pid inside the lock, and a later run reclaims the lock when
`ps` shows that pid is no longer a `necro-autosave.sh` process. A lock with no
recorded pid is reclaimed on age instead, so a wedge left by an older version
still heals — but only after 60s, so a run that has just won `mkdir` is not
robbed before it can stamp its pid.

Recovery fires on the next **due** autosave, not the next daemon tick, because
the interval throttle returns before the lock code. Worst-case heal time is one
`@necromancer_interval`, not one `@necromancer_autosave_tick`.

An earlier attempt used `pgrep -f 'necro-autosave\.sh'` to find the owner. It is
wrong: any wrapper shell whose command line merely mentions the script reads as
a live owner, so the lock is never reclaimed. It fails 4 of the 5 cases in
`tests/necro-autosave-stale-lock-test.sh`.

## Prevention

- [#26](https://github.com/RonenMars/tmux-ai-necromancer/pull/26) —
  `necro-doctor.sh` reports snapshot age and lock state together, and reads the
  snapshot rather than the logs so it works with debug logging off (the
  default). Both outages are a one-line finding in its output.
- Debug logging is off by default. It cost ~13 MB/day and detected nothing.
- Invariant 7 in `CLAUDE.md` now requires *recovery*, not just correct trap
  placement, for every lock.

## If you are investigating something similar

In order, cheapest first:

1. **`scripts/necro-doctor.sh`.** It exists because of this incident.
2. **Compare the newest snapshot's mtime to `@necromancer_interval`.** This is
   the single highest-value check and it needs no logs.
3. **Do not trust process liveness.** A running daemon proves scheduling works,
   nothing more.
4. **Prefer artifacts over logs.** Snapshot files, lock directory mtimes and
   `ls -t` ordering survive log rotation and cleanup.
5. **Search for existing analysis before deriving your own.** This incident's
   correct diagnosis sat unread in `~/.tmux-ai-necromancer-logs/` for six days.
6. **Distrust any counter that only ever rises**, and check whether a metric can
   observe its own output.

---

## Appendix: the original analysis, 2026-07-25 19:50

Reproduced verbatim. It was written during outage 1, correctly diagnosed the
cause, and correctly specified the fix. Its "since July 18" is accurate for
outage 1; outage 2 began about two hours after it was written. Its claim that
no autosave had completed is correct for the production snapshot directory.

> # tmux-ai-necromancer log analysis
>
> Date: 2026-07-25 19:50 Asia/Jerusalem
> Plugin revision: `4d61d6b` (`main`, PR #21 merged)
> Log directory: `/Users/ronenmars/.tmux-ai-necromancer-logs`
>
> ## Executive conclusion
>
> The watcher daemon is running and behaving coherently, and `status-right` is
> clean. Autosave is not functioning: its job lock has been stale since July 18,
> so every daemon tick is being rejected with `reason=lock_held`. This is a
> production-impacting failure because no periodic autosave snapshots are being
> created.
>
> The follow-up PR that was merged (`fix(autosave): recover stale daemon locks`)
> fixes the daemon's own scheduler lock, but it does not fix the separate
> `.autosave.lock` owned by the one-shot autosave job.
>
> ## Evidence
>
> ### Autosave: critical failure
>
> - `/Users/ronenmars/.claude/tmux-snapshots/.autosave.lock` exists with mtime
>   `2026-07-18 12:35:26 +0300`.
> - The directory contains no PID file and no matching autosave process owns it.
> - `necro-autosave.log` contains approximately 1,150 repeated
>   `phase=autosave action=skip reason=lock_held` events.
> - The last successful autosave event in that log is at `2026-07-25 01:10:16`,
>   but it writes to a temporary test snapshot directory, not the production
>   snapshot directory. The production daemon therefore has not completed an
>   autosave since the stale lock appeared.
> - The daemon itself is alive (`pid 29889`) and continues ticking every 60
>   seconds; the failure is inside the one-shot job lock, not daemon scheduling.
>
> ### Watcher: functioning, but very high debug-log volume
>
> - One watcher daemon is running with `tick_seconds=1`.
> - `necro-watch.log` has about 207,000 lines and is approximately 16 MB.
> - The event mix is consistent with a one-second polling loop: roughly 59,000
>   watcher starts and 118,000 adapter-load events.
> - UUID pinning, one agent exit, and one agent restart were observed. Those are
>   expected state transitions; no error, panic, invalid, or fatal events were
>   found.
> - The log volume is excessive while `@necromancer_debug=on`; it is operational
>   overhead rather than evidence of agent respawning.
>
> ### Plugin/runtime topology: healthy
>
> - `status-right` contains zero `necro-status`, `necro-watch`, or
>   `necro-autosave` hooks.
> - Exactly one autosave daemon and one watcher daemon are running.
> - Duplicate-daemon `already_running` entries after plugin reload are expected
>   and confirm the single-instance locks are working.
> - `necro-status.log` is historical output from the removed status script and
>   was excluded from active-behavior analysis.
>
> ## Monitoring caveat
>
> The detached 24-hour monitor did not remain alive. Its report contains only the
> initial sample, so no 35-minute samples or three-hour reviews were completed.
> This report is therefore based on the current log contents and direct runtime
> checks, not a completed 24-hour observation window.
>
> ## Recommended next actions
>
> 1. Verify no autosave worker is running, remove the stale
>    `~/.claude/tmux-snapshots/.autosave.lock`, run one production autosave, and
>    confirm an `autosave action=complete` event plus a new `.idle-only.jsonl`
>    snapshot.
> 2. Add stale-lock recovery to `necro-autosave.sh` itself; PR #21 only covered
>    `.autosave-daemon.lock`.
> 3. Set `@necromancer_debug` to `off` after the investigation or add stronger
>    log rotation for the one-second watcher log.

All three recommendations were eventually implemented: #1 by hand on 2026-07-30,
#2 as [#27](https://github.com/RonenMars/tmux-ai-necromancer/pull/27), #3 in the
dotfiles repo. Recommendation #1 alone was not enough — it was carried out on
2026-07-25 and the lock wedged again 18 minutes later, which is why #2 mattered.
