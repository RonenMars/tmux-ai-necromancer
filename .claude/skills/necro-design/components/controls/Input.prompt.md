**Input** — terminal-flavored text field; monospace, optional leading prompt glyph, green focus ring.

```jsx
<Input label="Session ID" prompt placeholder="claude --resume <uuid>" />
<Input label="Email" type="email" placeholder="you@host" />
<Input invalid defaultValue="bad value" />
```

Set `prompt` for the `›` prefix (great for command-style fields). `invalid` switches the border/ring to signal red. All native input props pass through.
