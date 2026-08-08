import React from 'react';

/**
 * Badge — compact status/label chip. Tracks the brand's three states:
 * alive (green), data (azure), dead (red), plus neutral/dormant.
 */
export function Badge({
  tone = 'alive',
  dot = false,
  pulse = false,
  style = {},
  children,
  ...rest
}) {
  const tones = {
    alive:   { fg: 'var(--necro-green)',  bd: 'var(--border-green)', bg: 'rgba(0,255,140,0.08)' },
    data:    { fg: 'var(--azure-circuit)',bd: 'var(--border-azure)', bg: 'rgba(0,212,255,0.08)' },
    dead:    { fg: 'var(--red-400)',      bd: 'var(--border-red)',   bg: 'rgba(255,77,77,0.08)' },
    dormant: { fg: 'var(--text-muted)',   bd: 'var(--border-default)', bg: 'rgba(255,255,255,0.03)' },
  };
  const t = tones[tone] || tones.alive;

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '7px',
        fontFamily: 'var(--font-mono)',
        fontSize: 'var(--fs-caption)',
        fontWeight: 600,
        letterSpacing: 'var(--ls-wide)',
        textTransform: 'uppercase',
        color: t.fg,
        background: t.bg,
        border: `1px solid ${t.bd}`,
        borderRadius: 'var(--radius-pill)',
        padding: '4px 12px',
        lineHeight: 1.2,
        ...style,
      }}
      {...rest}
    >
      {dot ? (
        <span style={{
          width: '7px', height: '7px', borderRadius: '50%',
          background: t.fg, flex: 'none',
          boxShadow: tone === 'alive' ? '0 0 8px var(--green-glow)' : tone === 'data' ? '0 0 8px var(--azure-glow)' : 'none',
          animation: pulse ? 'necroPulse 1.4s var(--ease-in-out) infinite' : 'none',
        }} />
      ) : null}
      {children}
      {pulse ? (
        <style>{`@keyframes necroPulse{0%,100%{opacity:1}50%{opacity:0.35}}`}</style>
      ) : null}
    </span>
  );
}
