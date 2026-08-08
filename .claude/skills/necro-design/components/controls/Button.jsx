import React from 'react';

/**
 * Button — primary action control for tmux-ai-necromancer.
 * Green fill is the "alive"/primary action; azure is secondary; ghost is
 * low-emphasis; danger is destructive (kill/delete).
 */
export function Button({
  variant = 'primary',
  size = 'md',
  disabled = false,
  glow = false,
  iconLeft = null,
  iconRight = null,
  type = 'button',
  onClick,
  children,
  style = {},
  ...rest
}) {
  const sizes = {
    sm: { padding: '7px 14px', fontSize: '0.8125rem', gap: '6px' },
    md: { padding: '11px 22px', fontSize: '0.9375rem', gap: '8px' },
    lg: { padding: '15px 30px', fontSize: '1.0625rem', gap: '10px' },
  };

  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--fw-bold)',
    lineHeight: 1,
    letterSpacing: '0.01em',
    border: '1px solid transparent',
    borderRadius: 'var(--radius-md)',
    cursor: disabled ? 'not-allowed' : 'pointer',
    opacity: disabled ? 0.45 : 1,
    transition: 'transform var(--dur-fast) var(--ease-out), background var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out), border-color var(--dur-base) var(--ease-out)',
    whiteSpace: 'nowrap',
    ...sizes[size],
  };

  const variants = {
    primary: {
      background: 'var(--necro-green)',
      color: 'var(--text-on-green)',
      boxShadow: glow ? 'var(--glow-green-md)' : 'none',
    },
    secondary: {
      background: 'transparent',
      color: 'var(--azure-circuit)',
      borderColor: 'var(--border-azure)',
      boxShadow: glow ? 'var(--glow-azure-sm)' : 'none',
    },
    ghost: {
      background: 'transparent',
      color: 'var(--text-secondary)',
      borderColor: 'var(--border-default)',
    },
    danger: {
      background: 'var(--signal-red)',
      color: '#240606',
    },
  };

  return (
    <button
      type={type}
      disabled={disabled}
      onClick={onClick}
      style={{ ...base, ...variants[variant], ...style }}
      onMouseDown={(e) => { if (!disabled) e.currentTarget.style.transform = 'translateY(1px)'; }}
      onMouseUp={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}
      {...rest}
    >
      {iconLeft ? <span style={{ display: 'inline-flex', fontSize: '1.1em' }}>{iconLeft}</span> : null}
      {children}
      {iconRight ? <span style={{ display: 'inline-flex', fontSize: '1.1em' }}>{iconRight}</span> : null}
    </button>
  );
}
