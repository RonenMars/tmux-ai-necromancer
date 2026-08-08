---
name: tmux-ai-necromancer-design
description: Use this skill to generate well-branded interfaces and assets for tmux-ai-necromancer (the AI-session-resurrecting tmux plugin), either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping the high-contrast terminal-necromancy aesthetic.
user-invocable: true
---

Read the `readme.md` file within this skill, and explore the other available files.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## Quick orientation

- **Brand:** tmux-ai-necromancer — "Resurrecting dead coding agents. Seamless session restore." High-contrast terminal necromancy: near-black void canvas, Necromancer Green (#00ff8c) for alive/restoring, Azure Circuit (#00d4ff) for data flow, Signal Red (#ff4d4d) for danger.
- **Tokens:** everything is a CSS custom property in `tokens/` (reached via `styles.css`). Never hardcode hex — use `var(--necro-green)`, `var(--surface-card)`, `var(--glow-green-md)`, etc.
- **Type:** Montserrat (wordmark/headings/UI) + Roboto Mono (all code/terminal/labels).
- **Components:** read off `window.DesignSystem_7d9b63` after loading `_ds_bundle.js` (Button, Input, Badge, KeyCap/KeyCombo, Card, FeatureCard, TerminalWindow).
- **Signature moves:** the green reanimation *glow*, the `TerminalWindow` surface, blinking `RESTORING`, pulsing status dots, the circuit-grid + corner-glow backdrop.
- **Voice:** dry technical sysadmin with a death/undead metaphor; lowercase wordmark, UPPERCASE mono labels, real commands only, only the 🪦 emoji.
- **Assets:** `assets/logo-mark.png`; the brand concept sheet lives at the repo root as `assets/concept-design.png`.
- **Reference UI kit:** `ui_kits/website/index.html` (the landing page).

See `readme.md` for the full CONTENT FUNDAMENTALS, VISUAL FOUNDATIONS, and ICONOGRAPHY sections.
