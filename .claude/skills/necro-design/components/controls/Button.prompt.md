**Button** — the primary action control; green fill = primary/alive, azure outline = secondary, ghost = low-emphasis, signal-red = destructive.

```jsx
<Button variant="primary" glow>Sign Up</Button>
<Button variant="secondary" iconLeft="›">Terminal</Button>
<Button variant="ghost">Log In</Button>
<Button variant="danger" size="sm">Delete</Button>
```

Variants: `primary | secondary | ghost | danger`. Sizes: `sm | md | lg`. Set `glow` for the reanimation halo (use on hero CTAs only). Primary uses dark ink on green for AA contrast.
