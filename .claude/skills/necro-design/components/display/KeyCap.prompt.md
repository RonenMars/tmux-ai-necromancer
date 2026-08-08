**KeyCap / KeyCombo** — keyboard keycaps for documenting keybindings; matches the brand sheet's "Prefix + n" treatment.

```jsx
<KeyCombo keys={[{label:'Prefix'},{label:'n',tone:'green'}]} />
<KeyCombo keys={[{label:'Prefix'},{label:'c',tone:'azure'}]} />
<KeyCap tone="green" size="lg">R</KeyCap>
```

`KeyCap` tones: `neutral | green | azure`. Use `green` for checkpoint/save actions, `azure` for continue/resume actions — mirrors the lifecycle color logic.
