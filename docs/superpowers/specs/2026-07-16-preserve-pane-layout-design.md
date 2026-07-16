# Design: preserve pane layout geometry through snapshot/restore

Date: 2026-07-16
Status: approved

## Goal

After `necro-restore.sh`, a multi-pane window reproduces its original pane
**arrangement and sizes**, not just tmux's default split placement.
Single-pane windows are unaffected. Old snapshots (without the new field) still
restore cleanly.

## Background

Today the snapshot records one JSONL line per pane with `session`,
`window_index`, `window_name`, `cwd`, `agent`, `uuid`, and a few enrichment
slots — but no geometry.
Restore groups panes sharing `(session, window_index)` into one window via
`split-window` (tracked in `WIN_FOR_GROUP`), so panes end up together in the
right window, but tmux lays them out with its default split behavior.
A carefully arranged or drag-resized layout is lost.

tmux exposes the exact geometry as `#{window_layout}`, a checksum + geometry
tree string, e.g. a two-pane vertical split:

```
c005,364x71,0,0{182x71,0,0,5,181x71,183,0,8}
```

It is replayed with `tmux select-layout -t <window> "<string>"`.
This is the same mechanism tmux-resurrect uses.

## Approach

Capture `#{window_layout}` per pane in the snapshot; replay it with
`select-layout` after each window's panes exist during restore.

Rejected alternatives:

- **Window-level snapshot section / new record type.** Cleaner data model on
  paper, but changes the snapshot file structure and forces every reader (Go
  TUI, `necro-context.sh`, autosave rotation, restore) to handle it.
  Too much blast radius for one string.
- **Named preset layouts** (tiled/even-horizontal/...). Same capture cost as
  the exact string but strictly less information — loses all sizing and only
  matches when the layout happened to equal a tmux preset.
  A manually-dragged split matches none.

## Component 1 — Snapshot (`necro-snapshot.sh`)

- Add `#{window_layout}` as a new tab-separated field in the pane-walk
  `tmux list-panes` format string (currently ~line 113); read it into a
  `layout` variable in the `while IFS=$'\t' read` loop.
- Thread `layout` through every `emit_record` call (all sites) and add it as a
  new JSON field `window_layout` in the record template (`emit_record`,
  line 67), escaped via `necro_json_escape`.
- All panes in a window emit the same string — redundant but harmless; restore
  uses the first per group.

Invariant #1 respected: no new pipelines, no `set -e` change — one more
`#{...}` field and one more `printf` arg.

## Component 2 — Restore (`necro-restore.sh`)

- Add two associative arrays alongside `WIN_FOR_GROUP` (line 281):
  `LAYOUT_FOR_GROUP` and `PANE_COUNT_FOR_GROUP`.
- In the main loop, parse the layout: `layout=$(jq -r '.window_layout // empty' <<<"$line")`.
  - The **first record** for each `group` (`session|window_index`) stores its
    string into `LAYOUT_FOR_GROUP[$group]`.
  - Increment `PANE_COUNT_FOR_GROUP[$group]` for every record sharing the group
    (the saved pane count).
- **After the main loop**, before the stage-5 cleanup (line 437), add one new
  pass:
  - For each group with a non-empty `LAYOUT_FOR_GROUP` entry and a resolved
    `window_id` (from `WIN_FOR_GROUP`), compare the live pane count
    (`tmux list-panes -t <win> | wc -l`) to `PANE_COUNT_FOR_GROUP[$group]`.
  - If equal: `tmux select-layout -t <window_id> "<layout>" 2>/dev/null || true`.
  - If not equal, or `DRY_RUN=1`: skip and log
    (`layout skipped: pane count N != M` / `DRY: select-layout ...`).

## Data flow

```
snapshot:   each pane record   -> window_layout: "c005,364x71,0,0{...}"
restore loop:
  first record per (session,win_idx) -> LAYOUT_FOR_GROUP[group]
  record count per group             -> PANE_COUNT_FOR_GROUP[group]
post-loop pass:
  live_count == saved_count -> tmux select-layout <win> "<string>"
```

## Error handling / edge cases

- **Empty/missing `window_layout`** (old snapshots, records without it): skip
  that group; falls back to today's default split placement.
  Fully backward-compatible.
- **Pane-count mismatch** (a resume shifted things, user modified the window, or
  a record was skipped mid-run): skip layout for that group, log the reason.
  Never force a layout onto a window whose shape changed.
- **Idempotency (invariant #2):** re-running applies the same string to an
  already-correct window — a no-op. Nothing added, nothing resumed,
  no pane/window count growth.
- **Reused/claimed windows** (idempotency claim path, lines 338-354) never
  populate `WIN_FOR_GROUP`, so the post-loop pass finds no `window_id` for that
  group and skips it. This is intentional: a window whose panes were claimed
  from existing shells already carries the user's live arrangement — restore
  must not stomp it. Layout is only applied to windows this run freshly created
  (`new-window`/`split-window`), which is exactly where `WIN_FOR_GROUP` is set.
- **`select-layout` failure** (malformed string): guarded with `|| true`,
  logged; restore continues.

## Other consumers

No change needed. The Go TUI, `necro-context.sh`, and autosave rotation all
read records field-by-field and ignore unknown fields — the new
`window_layout` field is invisible to them.

## Testing

- New `tests/necro-restore-layout-test.sh` on an isolated `-L necrotest`
  socket: build a snapshot with a 2-pane window carrying a known layout string,
  restore, assert the live window's pane geometry matches the saved layout
  (the checksum prefix differs across tmux instances — compare the geometry
  tree portion, or assert resulting pane sizes). Re-run → assert 0 panes added
  (idempotency).
- Regression: existing `necro-restore-*` tests must still pass (single-pane
  windows unaffected).
- Backward-compat: verify a snapshot without the `window_layout` field restores
  cleanly with no layout applied.

## Explicitly out of scope (YAGNI)

- No window-level snapshot section / new record type.
- No preset-layout fallback.
- No cross-window or session-geometry restoration — only pane layout within a
  window.
