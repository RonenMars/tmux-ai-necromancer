import React from 'react';

/**
 * Card — base surface container. The brand's cards are flat dark panels with a
 * hairline border (no heavy rounding). Set glow/accent for emphasis.
 */
export function Card({
  accent = 'none',
  glow = false,
  interactive = false,
  padding = 'var(--space-6)',
  style = {},
  children,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const accents = {
    none: {},
    green: { borderColor: 'var(--border-green)' },
    azure: { borderColor: 'var(--border-azure)' },
  };
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        background: 'var(--surface-card)',
        border: '1px solid var(--border-subtle)',
        borderRadius: 'var(--radius-lg)',
        padding,
        transition: 'transform var(--dur-base) var(--ease-out), border-color var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out)',
        boxShadow: glow ? 'var(--glow-green-md)' : 'var(--shadow-md)',
        ...accents[accent],
        ...(interactive && hover
          ? { transform: 'translateY(-3px)', borderColor: 'var(--border-green)', boxShadow: 'var(--glow-green-md)' }
          : null),
        ...style,
      }}
      {...rest}
    >
      {children}
    </div>
  );
}
