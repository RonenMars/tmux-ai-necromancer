# Troubleshooting

## Sessions missing after reboot

**Symptom:** `necro-resume` restores only a handful of sessions; most are gone.

**Cause:** The autosave runs every 5 minutes. If you close sessions manually
before rebooting — or if macOS begins killing processes during shutdown — the
final autosave captures only whatever was still alive at that moment.

**Fix:** Use `safe-reboot` / `safe-shutdown` instead of the system menu:

```bash
safe-reboot    # necro-reboot-prep.sh (snapshot all live sessions) → sudo reboot
safe-shutdown  # necro-reboot-prep.sh → sudo shutdown -h now
```

These aliases run `necro-reboot-prep.sh` first, which snapshots every live
session while they are all still open, then hands off to the OS.

Add them once to your shell config (already in
`dotfiles/shell/zshrc.d/30-ux/10-aliases.zsh`).

**Manual recovery from an older snapshot:**

If you already rebooted without prep, pick the last pre-reboot autosave:

```bash
ls -lt ~/.claude/tmux-snapshots/*.idle-only.jsonl | head -10
necro-restore.sh ~/.claude/tmux-snapshots/<timestamp>.idle-only.jsonl
```

Use the snapshot immediately *before* the shutdown timestamp — the one taken
at shutdown may be partial.

---

## `necro-resume` blocked: "You're inside tmux"

**Symptom:** Running `necro-resume` inside a tmux pane prints
`✗ You're inside tmux. Run from a fresh terminal.`

**Cause:** `necro-reboot-resume.sh` guards against running inside tmux to avoid
conflicts with an already-live server's session state during post-reboot restore.

**Fix:** Open a terminal emulator that is *not* inside tmux (e.g. a new iTerm2
or Tabby window not attached to a session), then run `necro-resume` there.

---

## Autosave shows only 3 records when many sessions are open

**Symptom:** `autosave.log` summary line shows `total=3` but you have 15+
sessions.

**Likely cause:** The autosave fired during or after a shutdown sequence, and
most sessions were already gone. See **Sessions missing after reboot** above.

**Other causes to rule out:**
- `@necromancer_agents` tmux option doesn't include your agent
  (`tmux show-option -gv @necromancer_agents`)
- Watcher (`necro-watch.sh`) isn't hooked into `status-right` — check
  `tmux show-option -gv status-right`
- Sessions use a different shell command than registered adapters recognize
  (`necro_agent_for_cmd` in `lib/agents.sh`)

---

## Restore adds 0 windows on second run (idempotency)

This is expected. Restore is keyed on a stable per-window marker
(`@necro_id`). If the windows already exist from a previous restore run,
they are reused — no duplicates, no extra agents launched.

---

## `necro-restore.sh` exits with "duplicate session"

Should not happen in current versions. If it does, the `ensure_session`
function in `necro-restore.sh` is not correctly guarding the `tmux
new-session` call. File a bug with the output of `tmux list-sessions`.
