// Keybindings — documents the prefix bindings with keycaps.
function Keybindings() {
  const { KeyCombo, Card } = window.DesignSystem_7d9b63;
  const rows = [
    { combo: [{label:'Prefix'},{label:'n',tone:'green'}], name: 'Checkpoint', desc: 'Manual snapshot of every live pane' },
    { combo: [{label:'Prefix'},{label:'R',tone:'green'}], name: 'Restore', desc: 'Reanimate the latest snapshot (popup)' },
    { combo: [{label:'Prefix'},{label:'c',tone:'azure'}], name: 'Continue', desc: 'Resume the focused agent in place' },
  ];
  return (
    <section style={{ maxWidth: 'var(--container-max)', margin: '0 auto', padding: '32px 40px 72px' }}>
      <h2 style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'var(--fs-h3)', color: 'var(--text-primary)', margin: '0 0 8px' }}>Keybindings</h2>
      <p style={{ color: 'var(--text-muted)', margin: '0 0 28px', fontFamily: 'var(--font-mono)', fontSize: '14px' }}>Set in <span style={{color:'var(--azure-circuit)'}}>~/.tmux.conf</span> before TPM loads.</p>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '18px' }}>
        {rows.map((r) => (
          <Card key={r.name} interactive style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
            <KeyCombo keys={r.combo} size="md" />
            <div>
              <div style={{ fontFamily: 'var(--font-display)', fontWeight: 700, color: 'var(--text-primary)', fontSize: '16px' }}>{r.name}</div>
              <div style={{ color: 'var(--text-secondary)', fontSize: '13px', marginTop: '4px' }}>{r.desc}</div>
            </div>
          </Card>
        ))}
      </div>
    </section>
  );
}
Object.assign(window, { Keybindings });
