import React from 'react';

/**
 * Input — text field with terminal-flavored styling. Optional leading prompt
 * glyph and label. Focus produces a green ring.
 */
export function Input({
  label,
  prompt = false,
  prefixGlyph = '›',
  invalid = false,
  type = 'text',
  id,
  style = {},
  containerStyle = {},
  ...rest
}) {
  const [focused, setFocused] = React.useState(false);
  const borderColor = invalid
    ? 'var(--border-red)'
    : focused
    ? 'var(--border-green)'
    : 'var(--border-default)';

  return (
    <label style={{ display: 'block', ...containerStyle }}>
      {label ? (
        <span style={{
          display: 'block',
          fontFamily: 'var(--font-mono)',
          fontSize: 'var(--fs-caption)',
          textTransform: 'uppercase',
          letterSpacing: 'var(--ls-wider)',
          color: 'var(--text-muted)',
          marginBottom: '8px',
        }}>{label}</span>
      ) : null}
      <span style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        background: 'var(--surface-inset)',
        border: `1px solid ${borderColor}`,
        borderRadius: 'var(--radius-md)',
        padding: '0 12px',
        boxShadow: focused && !invalid ? 'var(--glow-green-sm)' : 'none',
        transition: 'border-color var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out)',
      }}>
        {prompt ? (
          <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--necro-green)', fontWeight: 700 }}>{prefixGlyph}</span>
        ) : null}
        <input
          id={id}
          type={type}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          style={{
            flex: 1,
            background: 'transparent',
            border: 'none',
            outline: 'none',
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-mono)',
            fontSize: 'var(--fs-small)',
            padding: '11px 0',
            ...style,
          }}
          {...rest}
        />
      </span>
    </label>
  );
}
