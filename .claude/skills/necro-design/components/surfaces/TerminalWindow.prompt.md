**Card / FeatureCard / TerminalWindow** — the brand's surfaces. Flat dark panels, hairline borders, sharp radii; the terminal window is the hero centerpiece.

```jsx
<TerminalWindow title="necromancer — restore" glow statusLeft="~/dev/app" statusRight="2 panes · alive">
  <span style={{color:'var(--necro-green)'}}>RESTORING</span> claude --resume a1b2…
</TerminalWindow>

<FeatureCard icon={<i data-lucide="folder-check" />} title="Automatic Session Checkpointing">
  Auto-saves your session into your terminal every 5 minutes.
</FeatureCard>

<Card interactive accent="green">…</Card>
```

`TerminalWindow` = macOS chrome + near-black mono body + optional tmux status bar. `Card` is the base panel; pass `interactive` for the hover lift. `FeatureCard` composes Card with an icon tile.
