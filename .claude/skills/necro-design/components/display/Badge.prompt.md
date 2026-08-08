**Badge** — compact uppercase mono status chip mapped to lifecycle states.

```jsx
<Badge tone="alive" dot pulse>Restoring</Badge>
<Badge tone="data" dot>Snapshot</Badge>
<Badge tone="dead" dot>Crashed</Badge>
<Badge tone="dormant">Idle</Badge>
```

Tones: `alive | data | dead | dormant`. Use `dot` + `pulse` for live/restoring states.
