# tmux-ai-necromancer — Design System

> 🪦 *Resurrecting dead coding agents. Seamless session restore.*

The brand system for **tmux-ai-necromancer**, a TPM-compatible tmux plugin that
snapshots running AI coding-agent sessions (Claude Code, Codex, …) and
resurrects them — with the exact session resumed — after a crash, reboot, or
`tmux kill-server`. It does for **AI agent sessions** what
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) does for panes.

The aesthetic is **high-contrast terminal necromancy**: a near-black "void"
canvas, cascading **Necromancer Green** for everything alive/restoring, **Azure
Circuit** blue for data flow, and the signature reanimation *glow*. Think live
tmux pane meets occult ritual.

---

## Sources

This system was built from materials the user provided. You may not have access,
but they are recorded here so you can dig deeper:

- **GitHub (plugin):** https://github.com/RonenMars/tmux-ai-necromancer — the
  bash plugin + Go TUI. The `README.md`, `CLAUDE.md`, and `docs/agents.md` are
  the source of product copy, feature names, keybindings, and the supported-agent
  table. *Explore this repo to build more accurate product UIs.*
- **Brand asset sheet:** `assets/concept-design.png` at the repo root — the strict
  visual reference: dark theme, the five named colors, the logo, and a full
  landing-page mockup (hero terminal, feature grid, keybindings, code blocks).
- The repo ships a React landing page under `website/` — treat it, not this kit,
  as the source of truth for live product copy.

> ⚠️ **Font substitution:** the brand sheet's wordmark is a heavy geometric
> sans; we use **Montserrat 900** as the closest widely-available match, and
> **Roboto Mono** (explicitly named on the sheet) for all code/terminal type.
> Fonts load from Google Fonts CDN via `tokens/fonts.css`. If you have the exact
> wordmark binary, drop it in and replace the `@import` with a local
> `@font-face` — **please send updated font files if Montserrat isn't the intent.**

---

## CONTENT FUNDAMENTALS

**Voice — necromantic sysadmin.** Dry, technical, confident, with a dead/undead
metaphor running through everything. The product literally raises the dead, so
the copy leans into it without becoming campy.

- **Person:** speaks to *you* ("Never lose **your** agent's train of thought").
  Imperative for actions ("Restore Session", "Bring your terminal back to life").
- **Casing:** sentence case for prose; the wordmark is **always lowercase**
  (`tmux-ai-necromancer`); mono labels/eyebrows are **UPPERCASE** with wide
  tracking (`AUTOSAVE RUNNING`, `› ROBOTO MONO`).
- **The death/life metaphor is the through-line.** Use it for state names, never
  for filler: *dead* command prompts, *resurrect*, *reanimate*, *revive*,
  *seamless restore*, *train of thought*, *the void is empty* (empty state).
- **Technically precise.** Real commands, real paths, real file formats appear in
  copy verbatim: `claude --resume <uuid>`, `~/.claude/tmux-snapshots`, `prefix + a i`,
  JSONL. Never fake a command — check the plugin source before writing one.
- **Emoji:** exactly one, the headstone 🪦, used as a brand bookend (title/footer).
  Do **not** sprinkle emoji through UI or features.
- **Taglines are short and parallel:** "Resurrecting Dead Coding Agents. Seamless
  Session Restore." — two clipped fragments, title case, period-separated.

Example microcopy:
- Hero: *"Never lose your agent's train of thought."*
- Feature: *"Auto-saves tmux windows, panes, and directory states in the background."*
- Empty state: *"No snapshots — the void is empty."*
- Status: *"autosave running"*, *"reanimating"*, *"2 panes · alive"*.

---

## VISUAL FOUNDATIONS

**Colors.** Five named brand colors anchor everything:
`Necromancer Green #00ff8c` (primary / alive), `Midnight Void #0a0a14` (canvas),
`Azure Circuit #00d4ff` (secondary / data flow), `Ash Gray #aaaaaa` (muted body),
`Signal Red #ff4d4d` (danger / dead). The neutral ramp is a cool **blue-black**
("void"), never warm gray. Green and azure are reserved for signal — large fields
stay dark. Green-on-green text uses dark ink (`--text-on-green`) for contrast.

**Type.** Two families only. **Montserrat** for the wordmark (900, -0.02em,
lowercase), headings (700), and UI/prose (400–600). **Roboto Mono** for all
terminals, code blocks, labels, eyebrows, keycaps, and metadata. Eyebrows are
uppercase mono with `0.12em` tracking, usually azure or green.

**Backgrounds.** The void (`#0a0a14`) everywhere. The signature backdrop is a
faint **circuit grid** (48px, `--grid-line` at ~5% green) masked to fade out,
plus soft **radial corner glows** (green top-left, azure bottom-right). No
photography, no illustration beyond the logo. Optional subtle scanline texture.

**The glow is the brand.** "Reanimation" = a green box-shadow halo
(`--glow-green-md/lg`) on hero terminals and primary CTAs, and a text-shadow
(`--text-glow-green`) on live words like `RESTORING`. Azure has its own glow for
data-flow elements. Use glow sparingly — it marks *what is alive*.

**Borders.** Hairline (`1px`) is the default — `rgba(255,255,255,0.07–0.20)` for
neutral chrome, colored borders (`--border-green` / `--border-azure` /
`--border-red`) to signal state. Terminal windows always have a green border.

**Corners.** Sharp and terminal-flavored: `2–10px` for most surfaces, `14px` max.
Only chips/badges/keycaps use the pill radius. Nothing is soft/blobby.

**Shadows.** Cool, near-black elevation (`--shadow-md/lg`) — shadows sit on the
void, never tinted. Real depth comes from glow + border, not big drop shadows.

**Cards.** Flat dark panels (`--surface-card #12121e`), hairline border, modest
`shadow-md`, `radius-lg`. Interactive cards lift `-3px` and gain a green border +
glow on hover. No colored left-border-accent cards, no gradients on cards.

**Animation.** Restrained and mechanical. `--ease-out` for entrances, fast
(`120–200ms`) transitions. Signature motions: a **blink** on `RESTORING` (steps
timing, terminal cursor feel) and a **pulse** on live status dots. No bounce, no
parallax, no decorative infinite loops on content.

**Hover / press.** Buttons translate down `1px` on press (key-press feel); cards
lift on hover; links gain a green underline. Hover emphasis = border brightens to
green + glow, not background fills.

**Transparency & blur.** The sticky nav uses `rgba(10,10,20,0.72)` +
`backdrop-filter: blur(12px)`. Otherwise blur is rare — the void is opaque.

**Imagery vibe.** Cool, green-cast, high-contrast, "matrix rain" energy. The only
real image is the logo mark; everything else is type, terminals, and glow.

---

## ICONOGRAPHY

- **Primary icon set: [Lucide](https://lucide.dev)** (CDN), thin/consistent
  stroke — it matches the brand sheet's line-icons for the feature grid
  (`folder-check`, `brain-circuit`, `database`, `timer-reset`). Loaded via
  `<script src="https://unpkg.com/lucide@1.30.0/...">` then `lucide.createIcons()`.
  Always pin the version and carry an `integrity` hash — never `@latest`.
  This is a **substitution** of the closest CDN match for the sheet's bespoke
  line icons — flag if exact icons are required.
- **No icon font, no SVG sprite in the source repo** (it's a bash plugin) — so
  Lucide is the system standard for new work. Colorize icons with `currentColor`
  (green or azure), never multicolor.
- **Terminal glyphs as iconography:** the prompt `›` / `>_`, `$`, and `→` are
  used as inline "icons" in mono contexts — preferred over drawn icons inside
  terminals and command copy.
- **Emoji:** only 🪦 (headstone), as a brand bookend. No other emoji.
- **Logo:** `assets/logo-mark.png` — a code-rendered skull with circuit-trace
  wings over a terminal prompt. Use green-on-void; never recolor or place on light.

---

## INDEX

**Root**
- `styles.css` — global entry point (consumers link this); `@import`s only.
- `tokens/` — `fonts.css`, `colors.css`, `typography.css`, `spacing.css`, `effects.css`.
- `assets/` — `logo-mark.png` (cropped lockup). The reference concept sheet is the
  repo-root `assets/concept-design.png`.
- `SKILL.md` — Agent-Skills-compatible entry for downloading this system.

**Components** (`window.DesignSystem_7d9b63.*`)
- `components/controls/` — **Button**, **Input**
- `components/display/` — **Badge**, **KeyCap** + **KeyCombo**
- `components/surfaces/` — **Card**, **FeatureCard**, **TerminalWindow** *(signature)*

**UI kit**
- `ui_kits/website/` — full **landing page** recreation (`index.html`) composed
  from `Nav`, `Hero`, `FeatureGrid`, `Keybindings`, `InstallShowcase`, `Footer`.

**Templates** (copyable starting points for consuming projects)
- `templates/landing-page/LandingPage.dc.html` — the marketing landing page as a
  reusable Design Component that `x-import`s this system's own components.

**Foundation cards** (`guidelines/`) — populate the Design System tab: color
(brand core, ramps, surfaces), type (display, headings, body, mono), spacing
(scale, radii, shadows), brand (logo, backdrop).

---

## USAGE

Link the global stylesheet, load the compiled bundle, read components off the
namespace:

```html
<link rel="stylesheet" href="styles.css" />
<script src="_ds_bundle.js"></script>
<script type="text/babel">
  const { Button, TerminalWindow, Badge } = window.DesignSystem_7d9b63;
</script>
```

All styling flows through CSS custom properties — never hardcode hex; use
`var(--necro-green)`, `var(--surface-card)`, `var(--glow-green-md)`, etc.
