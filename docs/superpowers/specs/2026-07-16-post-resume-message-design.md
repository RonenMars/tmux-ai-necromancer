# Design: auto-send a follow-up message after resume

Date: 2026-07-16
Status: approved

## Goal

After `necro-restore.sh` / `necro-apply.sh` send a `claude`/`codex --resume`
into a freshly-created pane, optionally send a short follow-up prompt (default
`continue`) so the resumed agent picks up its in-progress task without the user
retyping anything.

## Motivation

On resume, Claude Code reloads the full transcript but sits idle at the prompt.
The user must type "continue"/"proceed" into every restored pane by hand. This
automates that nudge.

## Behavior

- New tmux option `@necromancer_resume_message`, also settable via
  `NECROMANCER_RESUME_MESSAGE` env var and `--resume-message` CLI flag
  (same three-tier precedence as the existing resume-delay option:
  CLI flag > env var > tmux option > built-in default).
- **Default: `continue`.** Sent after every resume unless overridden.
- **Empty string is the explicit off-switch**: set
  `@necromancer_resume_message ''` (or `--resume-message ''`) to send nothing
  and preserve pre-feature behavior.
- New tmux option `@necromancer_resume_message_delay` (env
  `NECROMANCER_RESUME_MESSAGE_DELAY`, flag `--resume-message-delay`), default
  `8` seconds — the pause between sending the resume command and sending the
  message, so the agent has time to boot past its loading screen before the
  prompt lands. Validated as a non-negative number; falls back to `8`.

## Where it fires

Both scripts have one send-keys resume site each:

- `necro-restore.sh:415` — `tmux send-keys -t "$target" "$resume_cmd" Enter`
- `necro-apply.sh:136` — `tmux send-keys -t "$window_id" "$resume_cmd" Enter`

Immediately after each successful resume send (guarded by the same
`DRY_RUN=0` / fresh-window conditions that gate the resume itself), if the
resolved message is non-empty:

```
sleep "$resume_message_delay"
tmux send-keys -t "$target" "$resume_message" Enter
```

The message send reuses the same `$target` / `$window_id` the resume used.

## Interaction with resume pacing

The existing batch pacing (invariant #10) sleeps `@necromancer_resume_delay`
every Nth resume. The message delay is separate and per-resume. To avoid
compounding sleeps that stall a large restore, the message delay applies only
when a message is actually sent, and the batch-pacing sleep stays where it is
(after the message send for that record). Net added time per resumed pane =
`resume_message_delay` (default 8s) only when a message is configured.

## Edge cases

- **Empty message** → skip the sleep and the send entirely (no wasted 8s wait).
- **DRY_RUN** → log `DRY: send-keys <message>` instead of sending; no sleep.
- **Resume skipped** (reused window, missing uuid, skip-reason) → no message,
  because the message is gated on the same "freshly resumed" branch.
- **Pending question from last turn**: auto-sending `continue` may blindly
  answer a question the agent posed to the user. This is inherent to any
  auto-nudge and documented as a caveat; the empty off-switch is the mitigation.

## Scope

Both `necro-restore.sh` and `necro-apply.sh`. Codex and Claude both accept a
plain-text line + Enter at their prompt, so no per-agent adapter change is
needed — the message is agent-agnostic.

## Out of scope (YAGNI)

- Per-agent or per-pane distinct messages.
- Waiting/polling for the agent to be "ready" instead of a fixed delay.
- Retrying if the message appears to land on a boot screen.

## Testing

- New `tests/necro-restore-resume-message-test.sh` on the mock-tmux harness
  (same style as `necro-restore-resume-delay-test.sh`): assert that after a
  resume send, a `send-keys ... continue` call is logged; assert that with
  `--resume-message ''` no such call is logged; assert DRY_RUN logs but does
  not send.
- Regression: existing `necro-restore-*` and apply tests still pass.
