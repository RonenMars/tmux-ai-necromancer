// Hero — wordmark, tagline, CTAs, and the signature split-pane terminal that
// flows a dead session into a reanimated one.
function Hero({ onRestore, restoring }) {
  const { Button, Badge, TerminalWindow } = window.DesignSystem_7d9b63;
  return (
    <section style={{ display: 'grid', gridTemplateColumns: '1fr 1.05fr', gap: '56px', alignItems: 'center', padding: '72px 40px 56px', maxWidth: 'var(--container-wide)', margin: '0 auto' }}>
      {/* left */}
      <div>
        <Badge tone="data" dot style={{ marginBottom: '24px' }}>TPM-compatible · multi-agent</Badge>
        <h1 style={{ margin: 0, fontFamily: 'var(--font-display)', fontWeight: 900, fontSize: 'clamp(40px, 5vw, 72px)', lineHeight: 1.02, letterSpacing: '-0.02em', color: 'var(--necro-green)' }}>
          tmux-<span style={{ color: 'var(--azure-circuit)' }}>ai</span>-necromancer
        </h1>
        <p style={{ margin: '20px 0 0', maxWidth: '460px', fontSize: '19px', lineHeight: 1.55, color: 'var(--text-secondary)' }}>
          Resurrecting dead coding agents. Never lose your agent's train of thought — restore your entire terminal exactly where you left off.
        </p>
        <div style={{ display: 'flex', gap: '16px', marginTop: '36px', flexWrap: 'wrap' }}>
          <Button variant="primary" size="lg" glow iconLeft="›" onClick={onRestore}>
            {restoring ? 'Reanimating…' : 'Restore Session'}
          </Button>
          <Button variant="secondary" size="lg">Read the Docs</Button>
        </div>
        <div style={{ marginTop: '28px', fontFamily: 'var(--font-mono)', fontSize: '13px', color: 'var(--text-muted)' }}>
          <span style={{ color: 'var(--necro-green)' }}>$</span> set -g @plugin 'RonenMars/tmux-ai-necromancer'
        </div>
      </div>
      {/* right — terminal */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0' }}>
        <TerminalWindow title="necromancer — session 0" glow statusLeft="[necromancer] reanimating" statusRight="2 panes · ~/dev" style={{ flex: 1 }} bodyStyle={{ minHeight: '300px', padding: 0 }}>
          <div style={{ display: 'grid', gridTemplateRows: '1fr 1fr', height: '300px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', borderBottom: '1px solid var(--border-green)' }}>
              <div style={{ padding: '14px', borderRight: '1px solid var(--border-green)', color: 'var(--text-muted)' }}>
                <span style={{ color: 'var(--necro-green)' }}>›</span> <span style={{ background: 'var(--necro-green)', color: 'var(--surface-terminal)' }}>&nbsp;</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,255,140,0.04)' }}>
                <span style={{ fontWeight: 700, letterSpacing: '0.18em', color: 'var(--necro-green)', textShadow: 'var(--text-glow-green)', animation: restoring ? 'heroBlink 0.9s steps(2) infinite' : 'none' }}>RESTORING</span>
              </div>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr' }}>
              <div style={{ padding: '14px', borderRight: '1px solid var(--border-green)' }}>
                <span style={{ color: 'var(--necro-green)' }}>›</span>
              </div>
              <div style={{ padding: '14px', fontSize: '12px', color: 'var(--azure-circuit)', lineHeight: 1.7 }}>
                <div>→ claude --resume a1b2c3</div>
                <div>→ codex resume 9f8e7d</div>
                <div style={{ color: 'var(--text-muted)' }}>→ 12 panes / 4 sessions</div>
              </div>
            </div>
          </div>
        </TerminalWindow>
        <div style={{ width: '64px', height: '2px', background: 'linear-gradient(90deg, var(--azure-circuit), transparent)', flex: 'none' }}></div>
        <div style={{ width: '120px', flex: 'none' }}>
          <div style={{ border: '1px solid var(--border-azure)', borderRadius: '8px', background: 'var(--surface-terminal)', padding: '12px', boxShadow: 'var(--glow-azure-sm)' }}>
            <div style={{ display: 'flex', gap: '5px', marginBottom: '12px' }}>
              <i style={{ width: 7, height: 7, borderRadius: '50%', background: '#ff5f57' }}></i>
              <i style={{ width: 7, height: 7, borderRadius: '50%', background: '#febc2e' }}></i>
              <i style={{ width: 7, height: 7, borderRadius: '50%', background: '#28c840' }}></i>
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', color: 'var(--necro-green)', fontSize: '22px' }}>›_</div>
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text-muted)', marginTop: '8px', textAlign: 'center' }}>Claude Code V2.</div>
        </div>
      </div>
      <style>{`@keyframes heroBlink{0%,100%{opacity:1}50%{opacity:0.25}}`}</style>
    </section>
  );
}
Object.assign(window, { Hero });
