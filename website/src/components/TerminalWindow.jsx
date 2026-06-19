export default function TerminalWindow({ title, lights = true, glow = false, scanlines = true, children, style = {}, bodyStyle = {} }) {
  return (
    <div style={{
      borderRadius: 'var(--radius-lg)',
      border: '1px solid var(--line-strong)',
      background: 'var(--void-700)',
      overflow: 'hidden',
      boxShadow: glow ? 'var(--shadow-lg), 0 0 50px rgba(0,255,140,0.10)' : 'var(--shadow-lg)',
      ...style,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        height: 38, padding: '0 14px',
        background: 'linear-gradient(180deg, #1b202d 0%, #161a26 100%)',
        borderBottom: '1px solid var(--line)',
      }}>
        {lights && (
          <div style={{ display: 'flex', gap: 8 }}>
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840' }} />
          </div>
        )}
        <span style={{
          marginLeft: lights ? 8 : 0,
          fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-3)',
        }}>{title}</span>
      </div>
      <div style={{
        position: 'relative', padding: '20px',
        fontFamily: 'var(--font-mono)', fontSize: 13, lineHeight: 1.75,
        color: 'var(--necro-green)',
        background: scanlines ? 'var(--scanlines), var(--void-700)' : 'var(--void-700)',
        minHeight: 80,
        ...bodyStyle,
      }}>
        {children}
      </div>
    </div>
  );
}
