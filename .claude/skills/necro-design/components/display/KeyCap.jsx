import React from 'react';

/**
 * KeyCap — a single keyboard key rendered as a terminal keycap. Compose with
 * <KeyCombo> for "Prefix + n" style bindings. Matches the keybindings section
 * of the brand sheet.
 */
export function KeyCap({ tone = 'neutral', size = 'md', style = {}, children, ...rest }) {
  const tones = {
    neutral: { fg: 'var(--text-secondary)', bd: 'var(--border-strong)', bg: 'var(--surface-raised)' },
    green:   { fg: 'var(--necro-green)',    bd: 'var(--border-green)',  bg: 'rgba(0,255,140,0.06)' },
    azure:   { fg: 'var(--azure-circuit)',  bd: 'var(--border-azure)',  bg: 'rgba(0,212,255,0.06)' },
  };
  const sizes = {
    sm: { padding: '4px 10px', fontSize: '0.8125rem', minWidth: '28px' },
    md: { padding: '8px 16px', fontSize: '1rem', minWidth: '40px' },
    lg: { padding: '12px 22px', fontSize: '1.375rem', minWidth: '56px' },
  };
  const t = tones[tone] || tones.neutral;
  return (
    <kbd
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: 'var(--font-mono)',
        fontWeight: 700,
        color: t.fg,
        background: t.bg,
        border: `1px solid ${t.bd}`,
        borderBottomWidth: '3px',
        borderRadius: 'var(--radius-md)',
        ...sizes[size],
        ...style,
      }}
      {...rest}
    >
      {children}
    </kbd>
  );
}

/** KeyCombo — lays out keycaps joined by a "+". */
export function KeyCombo({ keys = [], size = 'md', style = {}, ...rest }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '12px', ...style }} {...rest}>
      {keys.map((k, i) => (
        <React.Fragment key={i}>
          {i > 0 ? <span style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-mono)', fontSize: '1.1em' }}>+</span> : null}
          <KeyCap tone={k.tone} size={size}>{k.label}</KeyCap>
        </React.Fragment>
      ))}
    </span>
  );
}
