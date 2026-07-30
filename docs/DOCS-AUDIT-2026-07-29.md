# 🔎 Docs Audit — tmux-ai-necromancer

**Date:** 2026-07-29
**Scope:** every file under `docs/`, plus `README.md` and `CLAUDE.md`, audited against the actual code
**Method:** read all 15 `.sh` + 1 `.py` scripts, `lib/`, both adapters, TPM entrypoint, TUI surface — then verified every claim empirically
**Test suite:** ✅ **40/40 pass** (`PASS=40 FAIL=0`, isolated `NECROMANCER_SNAPSHOT_DIR`)
**Invariant check:** ✅ no code violates any of the 14 `CLAUDE.md` invariants
**Status:** 📋 findings only — **nothing edited yet, awaiting approval**

---

## 📊 At a Glance

| Bucket | Count | Notes |
|---|---:|---|
| 🐛 **Code bugs** | **1** | 🔴 Critical — breaks `safe-reboot` / `safe-shutdown` end-to-end |
| ❌ Doc claims contradicted by code | 7 | Wrong facts a reader would act on |
| ⚠️ Doc claims stale | 6 | Was true, no longer is |
| 🕳️ Behavior documented nowhere | 6 | Real features with zero coverage |
| 🔁 Same fact in 2+ files (drift risk) | 1 | The per-window/per-pane claim |
| 📐 Point-in-time records needing an as-built note | 2 | Plans/specs — annotate, **never rewrite** |
| **Total rows** | **24** | |

### 🚦 By severity

| Severity | Count | Meaning |
|---|---:|---|
| 🔴 Critical | 1 | Silently defeats a core documented workflow |
| 🟠 High | 5 | Actively misleads a user or contradicts an invariant |
| 🟡 Medium | 10 | Internal inaccuracy; wastes a maintainer's time |
| 🟢 Low | 8 | Cosmetic, cross-platform nit, or optional annotation |

### 🔑 Legend

| Symbol | Meaning |
|---|---|
| 🐛 | Code bug (not a doc bug — the code is wrong) |
| ❌ | Wrong — contradicted by code |
| ⚠️ | Stale — was true, no longer is |
| 🕳️ | Missing — code has behavior no doc mentions |
| 🔁 | Duplicated — same fact in 2+ places that can drift apart |
| 📐 | Drift-to-annotate — design record superseded, add dated note only |
| 🟩 | Trivial: 1-line / 1-word change, ~1 min |
| 🟨 | Small: a few lines or a list entry, ~5 min |
| 🟧 | Medium: new paragraph or section, ~15–30 min |

---

## 📋 All Findings

| # | 📄 Where (Doc) | 🔍 What | 🏷️ Type | 🚦 Severity | 🔧 Fix Complexity & Effort | 💬 Claim | ⚖️ Verdict | 🧪 Evidence | 💻 Code Evidence | ✅ Recommended Fix |
|---:|---|---|---|---|---|---|---|---|---|---|
| **1** | `scripts/necro-reboot-prep.sh:140` | **`$SNAPSHOT` is never assigned** — the variable is `SNAPSHOT_FILE` / `TARGET`. Under `set -uo pipefail` the expansion is fatal, so the script **always exits 1** after all four phases succeed. Because both aliases use `&&`, **`safe-reboot` never reboots and `safe-shutdown` never shuts down**. `necro-menu.sh` option 4→1/2 is the same silent no-op. | 🐛 Code bug | 🔴 **Critical** | 🟩 Trivial — 1 word | Docs promise "snapshot all live sessions → `sudo reboot`" as one command | ❌ **Broken** | Live `--dry-run` (writes nothing): all 4 phases ran, then `line 140: SNAPSHOT: unbound variable`, `EXIT STATUS: 1`. Isolated repro confirms `set -u` kills at **argument expansion**, before the function body — so the debug-off early-return in `necro_log_event` never protects it. `grep -n SNAPSHOT` shows line 140 is its **only** occurrence | `necro-reboot-prep.sh:25` (`set -uo pipefail`), `:105` (`TARGET="$SNAPSHOT_FILE"`), `:140`; blast radius at `necro-menu.sh:296,304` and `10-aliases.zsh:462-463` | Change `$SNAPSHOT` → `$TARGET` on line 140. ⚠️ **Fix this first — it is the only finding that silently loses a user workflow.** |
| **2** | `README.md:236` | Restore idempotency described as keyed on a **per-window** marker | ❌ Wrong 🔁 | 🟠 High | 🟩 Trivial — 1 word | "Restore is keyed on a stable **per-window** marker (`@necro_id`), not window names" | ❌ **Wrong** | Contradicts **invariant 2** verbatim. Marker is set with `tmux set-option -p` (pane scope) at 4 distinct call sites | `necro-restore.sh:278-284` — "keyed on a stable per-**PANE** marker… Marking panes (not windows) lets several records that shared one window restore as splits"; sets at `:416,449,459,474` | `per-window` → `per-pane` |
| **3** | `docs/TROUBLESHOOTING.md:84` | Same per-window claim, second location | ❌ Wrong 🔁 | 🟠 High | 🟩 Trivial — 1 word | "Restore is keyed on a stable **per-window** marker (`@necro_id`)" | ❌ **Wrong** | Duplicate of #2 — this is exactly the drift-prone duplication the audit looks for | `necro-restore.sh:278-284` | `per-window` → `per-pane`; consider pointing one file at the other to kill the duplication |
| **4** | `docs/agents.md:73-74` | Names `codex.sh` as an adapter that **doesn't** implement `min_epoch` filtering | ❌ Wrong | 🟠 High | 🟩 Trivial — delete clause | "Adapters that don't implement this filtering (**e.g. `codex.sh`**) simply ignore the extra argument" | ❌ **Wrong** | `codex.sh` implements it in full, and there is a **dedicated passing test** for exactly this | `codex.sh:40-48` (`min_epoch` param + `stat -f %m` mtime guard); `tests/necro-agent-codex-min-epoch-test.sh` ✅ passes | Drop the `codex.sh` example. Keep the "it's optional, not part of the required contract" rule — that part is still true |
| **5** | `docs/agents.md:9` | Contract function count | ❌ Wrong | 🟠 High | 🟩 Trivial — 1 word | "Implement these **five** functions, prefixed `agent_<name>_`" | ❌ **Wrong** | Its own code block immediately below lists **seven**: `matches`, `latest_session_id`, `scrape_session_id`, `scrape_resume_cmd`, `scrape_ps_resume`, `resume_cmd`, `exit_keys` | `docs/agents.md:11-41`; all seven dispatched from `lib/agents.sh:114-160` | `five` → `seven`. Also worth noting `all_session_ids` is de-facto required for cursor-pop (`lib/agents.sh:88`) but appears only in the `min_epoch` prose |
| **6** | `README.md:213-214` | Watcher pane-option count | ❌ Wrong | 🟠 High | 🟨 Small — add 5th item | "maintains **four** tmux pane options: `@necro_uuid`, `@necro_agent`, `@necro_cmd`, `@necro_agent_exited`" | ❌ **Wrong** | Five. The missing one — `@necro_pane_first_seen` — is the option **invariant 9 depends on** to reject stale cursor-pop candidates, so omitting it hides the whole staleness guard | `necro-watch.sh:12-18` (header documents all 5), `:108-112` (writes it), `:117` (passes as `min_epoch`) | `four` → `five`; add `@necro_pane_first_seen` with a one-clause note on what it guards |
| **7** | `README.md:119` | Blanket claim that the plugin sets every documented option | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — 1 word | "the plugin **sets** every one of these itself, so the single `set -g @plugin` line is enough on its own" | ⚠️ **Imprecise** | `set_default` covers **11 of 14** listed options. `@necromancer_snapshot_dir`, `@necromancer_resume_message`, `@necromancer_resume_message_delay` get **zero** `set_default` calls (`grep -c` = 0 each). Values still land correctly via in-code fallbacks, so the follow-on claim "pasting the block verbatim changes nothing" **is true** ✅ | `tmux-ai-necromancer.tmux:32-42` (11 `set_default` calls); fallbacks at `common.sh:152`, `necro-restore.sh:181`, `:191` | `sets` → `defaults`. No other change needed — all 16 documented default **values** were traced to source and are correct ✅ |
| **8** | `README.md:224-228` | Snapshot record JSON sample | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — add field | Sample shows `…"uuid_source":"pane-option","captured_at":…` | ⚠️ **Stale** | Sample omits `window_layout`, which every record has carried since the layout feature landed. A reader writing a consumer against this sample misses a field | `necro-snapshot.sh:92` — `window_layout` sits between `uuid_source` and `captured_at` in the `printf` template; `:90,102` | Add `"window_layout":"…"` to the sample in the correct position |
| **9** | `CLAUDE.md:70` | Invariant 2 names a variable that no longer exists | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — rename | "later records with the same key `split-window` into it (tracked via **`WIN_FOR_GROUP`**)" | ⚠️ **Stale** | `grep -rn WIN_FOR_GROUP scripts/ lib/` → **no matches in executable code**. Replaced by hex-encoded scalars during the bash-3.2 rewrite (invariant 13). Two stale code comments still reference it too | `necro-restore.sh:342-351` (`group_var`/`group_get`/`group_set`); stale comments at `:419,422` | `WIN_FOR_GROUP` → `group_get/group_set`; fix the two code comments at `necro-restore.sh:419,422` in the same pass |
| **10** | `CLAUDE.md` — Testing section | Test index is 30% incomplete | 🕳️ Missing | 🟡 Medium | 🟨 Small — 12 lines | Index implies it lists the suite | 🕳️ **12 undocumented** | **28 listed, 40 on disk, 0 broken entries** ✅ (every listed file exists and passes). Missing: `codex-matches`, `autosave-daemon-lock`, `autosave-daemon-wiring`, `autosave-rotation-pin`, `clean-debug-logs-python`, `debug-logging`, `reboot-resume-cleanup`, `restore-claim-existing`, `restore-multipane-window`, `restore-safety`, `snapshot-idle-shell`, `watch-daemon-lock` | `comm -13` of `grep -oE 'tests/[a-z0-9-]+\.sh' CLAUDE.md` vs `ls tests/*.sh` | Add the 12 missing entries with one-line descriptions, matching the existing format |
| **11** | `CLAUDE.md` — Architecture block | Script map omits 5 of 16 scripts | 🕳️ Missing | 🟡 Medium | 🟨 Small — 5 lines | The ```` ``` ```` block presents itself as the map of `scripts/` | 🕳️ **5 missing** | Absent: `necro-menu.sh`, `necro-clean-debug-logs.sh`, `necro-clean-debug-logs.py`, `necro-log-divider.sh`, `necro-log-monitor.sh`. `necro-menu.sh` is user-facing (a README alias) and `necro-log-monitor.sh` is currently **untracked** in git | `comm -13` of the CLAUDE.md code block vs `ls scripts/` | Add the 5 entries. Also decide whether `necro-log-monitor.sh` should be committed or gitignored |
| **12** | `README.md:231-234` | `uuid_source` value enumeration | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — add 2 values | "`uuid_source` is `pane-option` … or `latest-jsonl` for the filesystem fallback" | ⚠️ **Incomplete** | Code emits **four** values: those two plus `scrollback` (interactive capture) and `""` (nothing found) | `necro-snapshot.sh:232` (`scrollback`), `:167,192` (empty), `:185,189` (`pane-option`/`latest-jsonl`) | Mention `scrollback` and the empty case in the same sentence |
| **13** | `docs/tests/MANUAL-TEST-SCENARIOS.md:7` | Heading cites the wrong autosave interval | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — 1 digit | "## Capture the current state on command (no **15-min** wait)" | ⚠️ **Stale** | Default `@necromancer_interval` is **5** minutes — as this same file's own body correctly says at `:9-11` | `necro-autosave.sh:27` (`necro_tmux_option @necromancer_interval 5`); `tmux-ai-necromancer.tmux:32` | `15-min` → `5-min` |
| **14** | `docs/TROUBLESHOOTING.md:76` | Paste-able diagnostic uses a Linux-only flag | ⚠️ Stale | 🟢 Low | 🟩 Trivial — 1 letter | "check `pgrep -af necro-watch-daemon.sh`" | ⚠️ **Wrong platform** | Ran it: BSD/macOS `pgrep` accepts `-a` but does **not** print the command line — output is bare PIDs, and `-f` self-matches the wrapping shell (spurious extra PID). `pgrep -lf` gives what the doc intends. Plugin is macOS-targeted | Live comparison: `pgrep -af` → `13627`, `27060`; `pgrep -lf` → `27060 bash …/necro-watch-daemon.sh` | `-af` → `-lf` |
| **15** | `scripts/necro-restore.sh:10` | File header contradicts its own body 268 lines later | ⚠️ Stale | 🟡 Medium | 🟩 Trivial — 1 line | "skips a window whose **(name+cwd)** already exists in the target session" | ⚠️ **Stale** | Superseded by the pane-marker mechanism. Name-matching survives only as one clause of the *unmarked-pane claim* heuristic, not as the idempotency key. Invariant 2 explicitly forbids keying on window name | `necro-restore.sh:278-284` (the real mechanism), `:300-306` (`unmarked_window_id_for_record`) | Reword to "claims a pane already carrying its `@necro_id` marker" |
| **16** | `lib/agents.sh:7` | Header comment promises a feature that does not exist | ❌ Wrong | 🟡 Medium | 🟩 Trivial — delete clause | "add its name to the default `@necromancer_agents` list **(or it's auto-discovered)**" | ❌ **Wrong** | There is **no** auto-discovery. `necro_load_agents` iterates `necro_enabled_agents` only; an adapter file present in `lib/agents/` but absent from `@necromancer_agents` is never sourced. `docs/agents.md:102-110` gets this right | `lib/agents.sh:17-30` (`for name in $(necro_enabled_agents)`), `:12-14` | Delete "(or it's auto-discovered)" |
| **17** | `lib/agents/claude.sh:5` | File header states the pre-invariant-11 encoding rule | ❌ Wrong | 🟠 High | 🟩 Trivial — 1 line | "`~/.claude/projects/<cwd-with-**slashes**-as-dashes>/<uuid>.jsonl`" | ❌ **Wrong** | This is the exact wording of the bug **invariant 11** exists to prevent — slash-only encoding matched 65/148 project dirs; slash+dot+underscore matched 148/148. The function's own comment 20 lines down (`:25-26`) states the correct rule, so the file contradicts itself | `claude.sh:27-34` (`agent_claude_project_dir` encodes `/`, `.` **and** `_`); `tests/necro-agent-claude-project-dir-test.sh` ✅ passes | Reword to "`/`, `.` and `_` all encoded as `-`" — a header that restates the bug is worse than no header |
| **18** | `tmux-ai-necromancer.tmux:7-18` | Entrypoint's own option header is incomplete | 🕳️ Missing | 🟢 Low | 🟨 Small — 5 lines | Header block lists "User-tunable options" | 🕳️ **5 missing** | Omits `@necromancer_claude_commands` — **which this very file sets at `:35`** — plus `resume_message`, `resume_message_delay`, `max_claude_transcript_bytes`, `unsafe_cwd_patterns` | `tmux-ai-necromancer.tmux:35`; `necro-restore.sh:133,180,191,204` | Add the 5 lines so the entrypoint header matches what the plugin actually reads |
| **19** | *(nowhere)* | **90-second post-boot autosave suppression** | 🕳️ Missing | 🟡 Medium | 🟨 Small — 2 sentences | — | 🕳️ **Undocumented** | Autosave silently skips entirely for the first 90s of machine uptime so it can't snapshot a half-restored server before `necro-resume` runs. Deliberate and load-bearing for the reboot flow, but explains "why didn't my first autosave fire?" and appears in **no** doc | `necro-autosave.sh:40-46` (`sysctl -n kern.boottime`, `reason=recent_boot`) | Add to README "How it works" **and** TROUBLESHOOTING — it's a plausible support question |
| **20** | `docs/DEBUG_LOGGING.md` | Two debug scripts absent from the debug guide | 🕳️ Missing | 🟡 Medium | 🟨 Small — 2 entries | Guide covers enabling, contents, growth, cleanup | 🕳️ **2 missing** | `necro-log-divider.sh` (stamps a labelled separator into every log — a pure debugging aid) and `necro-log-monitor.sh` (hourly launchd sampler + 24h report) appear nowhere in the doc whose subject they are. The divider is referenced once in passing at `MANUAL-TEST-SCENARIOS.md:151` | `necro-log-divider.sh:1-10`; `necro-log-monitor.sh:1-10` | Add both to `DEBUG_LOGGING.md` — the divider under a "Marking a repro" heading, the monitor under "Long-running health check" |
| **21** | `README.md:125-140` | Two restore-safety options missing from the config block | 🕳️ Missing | 🟢 Low | 🟨 Small — 2 lines | Block presents itself as the option list | 🕳️ **Partial** | `@necromancer_max_claude_transcript_bytes` (default `52428800`) and `@necromancer_unsafe_cwd_patterns` are absent. Mitigated — both **are** documented in `necro-restore.sh --help` and `TROUBLESHOOTING.md:88-95`, so this is incompleteness, not a wrong value | `necro-restore.sh:128-139`, `:199-209`; help text at `:67-72` | Either add both lines, or add "see `necro-restore.sh --help` for restore-safety options" — deliberate omission is fine if stated |
| **22** | `scripts/necro-apply.sh:46-50` | Hardcoded personal routing table, undocumented | 🕳️ Missing | 🟢 Low | 🟨 Small — 1 note | — | 🕳️ **Undocumented** | `ROUTING_TABLE` ships with two of **your** paths (`*/ai-tools/*`, `*/dotfiles*` → `$HOME/Desktop/dev/ai-tools`, `$HOME/dotfiles`) baked in. Only an inline comment says "Customize for your own projects" — no doc mentions `necro-apply.sh` has routing at all, and README never mentions the script | `necro-apply.sh:44-50`; consumed at `:122-132,157` | Document `necro-apply.sh` + its routing in README's usage table, or move the table to a tmux option. ⚠️ For a public repo, personal paths as the shipped default are a smell |
| **23** | `docs/superpowers/plans/2026-06-23-pane-watcher.md:152,191-193` | Recorded design superseded by invariant 9 with no note | 📐 Annotate | 🟢 Low | 🟨 Small — dated note | Plan records resolution as **scrollback → cursor-pop** over **3** pane options (`@necro_uuid`, `@necro_cmd`, `@necro_agent_exited`) | 📐 **Drift** | Code now does **argv → scrollback → cursor-pop** over **5** options. That change *is* invariant 9 and post-dates the plan. Valid finding type for a point-in-time record: decision recorded, code diverged, no note | `necro-watch.sh:96-118` (argv first via `necro_agent_scrape_ps_resume`), `:12-18`; `tests/necro-watch-priority-order-test.sh` ✅ passes | Append a dated "**As-built differs (2026-07):** …" note. 🚫 **Do NOT rewrite the plan** — it is a historical record |
| **24** | `docs/superpowers/specs/2026-07-16-*.md` (both) | Specs reference the pre-bash-3.2 implementation | 📐 Annotate | 🟢 Low | 🟩 Trivial — optional | Specs describe `declare -A WIN_FOR_GROUP` / `LAYOUT_FOR_GROUP` / `PANE_COUNT_FOR_GROUP` | ✅ **Behaviorally correct** | ⭐ Both specs **match the as-built code** on every behavioral claim: message default `continue`, delay `8`, empty string disables, layout replayed only when live pane count == saved. Only the *implementation vehicle* changed (assoc arrays → hex scalars, per invariant 13) | Verified: `necro-restore.sh:181` (`continue`), `:191` (`8`), `:543` (pane-count guard); `necro-restore.sh:342-351` (scalars) | Optional one-line as-built note. Lowest priority in this table — nothing is *wrong* here |

---

## 🎯 Recommended Order of Attack

| Wave | Rows | Why | Effort |
|---|---|---|---|
| 🥇 **1 — Ship immediately** | **#1** | The only finding that silently breaks a real user workflow. One word. | 🟩 ~1 min |
| 🥈 **2 — User-facing wrong facts** | #2, #3, #4, #5, #6, #17 | Everything a reader would act on and be misled by. All trivial. | 🟩 ~15 min total |
| 🥉 **3 — Maintainer accuracy** | #7, #8, #9, #12, #13, #15, #16 | Stale claims that waste the next person's time. | 🟩🟨 ~30 min |
| 4 — Coverage | #10, #11, #18, #19, #20 | Index and map completeness; the undocumented boot-skip. | 🟨 ~45 min |
| 5 — Judgment calls | #14, #21, #22 | Need a decision, not just an edit (esp. #22 for a public repo). | 🟨 varies |
| 6 — Historical notes | #23, #24 | Annotate only. Never rewrite a design record. | 🟩 ~10 min |

---

## ✅ What Was Verified Clean

Not everything drifted — these were checked and hold up:

| Area | Result |
|---|---|
| 🧪 Test suite | **40/40 pass**, isolated snapshot dir |
| 📇 Test index integrity | **0 broken entries** — every test listed in `CLAUDE.md` exists and passes |
| 🔢 All 16 documented default **values** | ✅ every one traced to its setting line and correct (`interval 5`, `max_snapshots 20`, `agents "claude codex"`, `restore_key R`, `snapshot_dir ~/.claude/tmux-snapshots`, `log_dir`, `debug off`, `autosave_tick 60`, `watch_tick 1`, `claude_commands claude`, `resume_delay 5`, `resume_batch_size 1`, `resume_message continue`, `resume_message_delay 8`, `max_claude_transcript_bytes 52428800`, `unsafe_cwd_patterns`) |
| ⌨️ Every paste-able command in every doc | ✅ executed or dry-run — `pkill -9 -f 'necro-.*-daemon\.sh'` matches exactly the two daemons and nothing else; `tmux show-option -gv @necromancer_agents` → `claude codex`; both cleanup helpers `--dry-run` exit 0; `python3 -m json.tool --json-lines` works; the `docs/agents.md` "Test it" snippet returns a real uuid + `claude --resume <id>` |
| 🔒 Daemon locking | ✅ exactly one autosave daemon (27052) + one watch daemon (27060), both matching their lock pid files — reload idempotency works as documented |
| 🏠 `TROUBLESHOOTING.md:21-22` alias location claim | ✅ `safe-reboot` / `safe-shutdown` really are at `dotfiles/shell/zshrc.d/30-ux/10-aliases.zsh:462-463` |
| ⏱️ "config takes effect per-run vs. daemon-startup" table | ✅ correct — one-shot scripts are fresh processes each tick, so the per-process option cache never staleness-traps them; only the two daemon ticks are read-once, exactly as documented |
| 📐 Both 2026-07-16 specs | ✅ match as-built behavior on every claim |
| 🛡️ All 14 `CLAUDE.md` invariants | ✅ no code violates any of them |

---

## 📌 Notes

- 🗂️ **Git is restored** — this repo is now a real checkout with remote `RonenMars/tmux-ai-necromancer`, so fixes can be branched, committed and pushed normally. The earlier "changes are lost on `prefix + U`" hazard no longer applies.
- 📄 `scripts/necro-log-monitor.sh` is currently **untracked** and `README.md` has uncommitted modifications — worth resolving before starting a fix branch.
- 🚫 No `docs/superpowers/` plan or spec should be rewritten to agree with current code. The only valid edit there is a dated as-built note (#23, #24).
