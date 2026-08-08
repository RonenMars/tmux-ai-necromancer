import React from 'react';

/**
 * TerminalWindow — the signature surface. macOS-style chrome (traffic lights),
 * optional title, and a near-black body for monospace content. Use `glow` for
 * the hero "reanimation" treatment.
 */
export function TerminalWindow({
  title = '',
  glow = false,
  statusLeft = '',
  statusRight = '',
  bodyStyle = {},
  style = {},
  children,
  ...rest
}) {
  return (
    <div
      style={{
        background: 'var(--surface-terminal)',
        border: '1px solid var(--border-green)',
        borderRadius: 'var(--radius-lg)',
        overflow: 'hidden',
        boxShadow: glow ? 'var(--glow-green-lg), var(--shadow-lg)' : 'var(--shadow-lg)',
        fontFamily: 'var(--font-mono)',
        ...style,
      }}
      {...rest}
    >
      {/* chrome */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        padding: '10px 14px',
        background: 'var(--surface-terminal-chrome)',
        borderBottom: '1px solid var(--border-subtle)',
      }}>
        <span style={{ display: 'flex', gap: '7px' }}>
          <i style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57' }} />
          <i style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e' }} />
          <i style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840' }} />
        </span>
        {title ? (
          <span style={{
            marginLeft: '8px',
            fontSize: 'var(--fs-caption)',
            color: 'var(--text-muted)',
            letterSpacing: 'var(--ls-wide)',
          }}>{title}</span>
        ) : null}
      </div>
      {/* body */}
      <div style={{
        padding: 'var(--space-5)',
        fontSize: 'var(--fs-small)',
        lineHeight: 'var(--lh-relaxed)',
        color: 'var(--text-terminal)',
        minHeight: '120px',
        ...bodyStyle,
      }}>
        {children}
      </div>
      {/* status bar */}
      {(statusLeft || statusRight) ? (
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          padding: '6px 14px',
          background: 'rgba(0,255,140,0.06)',
          borderTop: '1px solid var(--border-green)',
          fontSize: 'var(--fs-caption)',
          color: 'var(--necro-green)',
        }}>
          <span>{statusLeft}</span>
          <span>{statusRight}</span>
        </div>
      ) : null}
    </div>
  );
}
