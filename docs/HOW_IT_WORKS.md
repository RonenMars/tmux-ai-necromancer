# How it works

The plugin starts independent autosave and watcher daemons with
`tmux run-shell -b`; neither runs during `status-right` rendering. Autosave
polls every `@necromancer_autosave_tick` seconds (default 60), while the
one-shot job self-throttles to `@necromancer_interval` minutes (default 5).
The watcher polls every `@necromancer_watch_tick` seconds (default 1). Atomic
daemon locks make plugin reloads idempotent, and both daemons exit when the
tmux server disappears.

**Pane watcher** (`necro-watch.sh`) runs from the watcher daemon and maintains five tmux pane
options: `@necro_uuid`, `@necro_agent`, `@necro_cmd`, `@necro_agent_exited`, and
`@necro_pane_first_seen`. When an agent starts it pins the UUID immediately; when
it exits it sets the exited flag so autosave can log the closed session. The
first-seen stamp records when the pane's agent was first observed, so the
filesystem fallback can reject transcripts older than the pane itself.

**Autosave** (`necro-autosave.sh`) self-throttles to your interval and, when due,
runs a `--idle-only` snapshot in the background. An atomic `mkdir` lock prevents
concurrent daemon ticks or manual invocations from firing duplicate snapshots.
It also skips entirely during the first 90 seconds of machine uptime, so a
snapshot of a half-restored server can't overwrite the good one before
`necro-reboot-resume.sh` has had a chance to run.

A snapshot is JSON Lines, one record per pane:

```json
{"pane_id":"%5","session":"tb-mobile","window_index":3,"window_name":"feat:x",
 "cwd":"/Users/you/dev/app","prev_cmd":"claude","agent":"claude",
 "uuid":"abc-…","uuid_source":"pane-option","window_layout":"c005,364x71,0,0{…}",
 "zoomed":0,"pane_active":1,"window_active":1,"captured_at":"…",
 "first_user":"","last_assistant":"","dest_session":"","dest_window_name":""}
```

`uuid_source` is `"pane-option"` when the watcher already pinned the UUID,
`"latest-jsonl"` for the filesystem fallback (most-recent transcript for the
pane's cwd), `"scrollback"` when an interactive capture scraped it from the
pane, or `""` when no id could be found at all. The watcher path is preferred —
it's exact and collision-free even when multiple agents share the same working
directory.

Restore is keyed on a stable per-pane marker (`@necro_id`), not window names
(which auto-rename) — so repeated restores never stack duplicates.
