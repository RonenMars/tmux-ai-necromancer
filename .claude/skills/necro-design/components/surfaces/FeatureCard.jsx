import React from 'react';
import { Card } from './Card.jsx';

/**
 * FeatureCard — icon + title + description tile used in the marketing feature
 * grid. Icon is supplied as a ReactNode (e.g. a Lucide <i data-lucide>).
 */
export function FeatureCard({
  icon = null,
  title,
  children,
  accent = 'green',
  align = 'left',
  style = {},
  ...rest
}) {
  const color = accent === 'azure' ? 'var(--azure-circuit)' : 'var(--necro-green)';
  return (
    <Card interactive accent="none" padding="var(--space-6)" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)', alignItems: align === 'center' ? 'center' : 'flex-start', textAlign: align, ...style }} {...rest}>
      {icon ? (
        <span style={{
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: '52px',
          height: '52px',
          borderRadius: 'var(--radius-md)',
          color,
          background: accent === 'azure' ? 'rgba(0,212,255,0.07)' : 'rgba(0,255,140,0.07)',
          border: `1px solid ${accent === 'azure' ? 'var(--border-azure)' : 'var(--border-green)'}`,
        }}>{icon}</span>
      ) : null}
      <h3 style={{
        margin: 0,
        fontFamily: 'var(--font-display)',
        fontWeight: 'var(--fw-bold)',
        fontSize: 'var(--fs-h5)',
        color: 'var(--text-primary)',
        lineHeight: 'var(--lh-snug)',
      }}>{title}</h3>
      <p style={{
        margin: 0,
        fontFamily: 'var(--font-body)',
        fontSize: 'var(--fs-small)',
        lineHeight: 'var(--lh-relaxed)',
        color: 'var(--text-secondary)',
      }}>{children}</p>
    </Card>
  );
}
