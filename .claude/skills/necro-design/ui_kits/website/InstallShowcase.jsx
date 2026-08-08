// InstallShowcase — tabbed install instructions (code block) beside a live
// snapshot/session list with restore + delete actions.
function InstallShowcase() {
  const { Card, Badge, Button } = window.DesignSystem_7d9b63;
  const [tab, setTab] = React.useState('TPM');
  const [sessions, setSessions] = React.useState([
    { id: 'a1b2c3', name: 'tb-mobile', agent: 'claude', cwd: '~/dev/threadbase', state: 'alive' },
    { id: '9f8e7d', name: 'web-platform', agent: 'codex', cwd: '~/dev/web', state: 'data' },
    { id: 'c4d5e6', name: 'necromancer', agent: 'claude', cwd: '~/dev/necro', state: 'dormant' },
  ]);
  const code = {
    TPM: `# ~/.tmux.conf
set -g @plugin 'RonenMars/tmux-ai-necromancer'

# then press prefix + I to install
# autosave starts immediately`,
    Manual: `git clone https://github.com/RonenMars/\\
  tmux-ai-necromancer \\
  ~/.tmux/plugins/tmux-ai-necromancer

run-shell ~/.tmux/plugins/\\
  tmux-ai-necromancer/tmux-ai-necromancer.tmux`,
    Config: `set -g @necromancer_interval      '5'
set -g @necromancer_max_snapshots '20'
set -g @necromancer_agents 'claude codex'
set -g @necromancer_restore_key   'R'`,
  };
  return (
    <section style={{ maxWidth: 'var(--container-max)', margin: '0 auto', padding: '24px 40px 80px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '28px', alignItems: 'start' }}>
      {/* install */}
      <div>
        <h2 style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'var(--fs-h3)', color: 'var(--text-primary)', margin: '0 0 18px' }}>Install in one line</h2>
        <div style={{ display: 'flex', gap: '8px', marginBottom: '14px' }}>
          {['TPM', 'Manual', 'Config'].map((t) => (
            <button key={t} onClick={() => setTab(t)} style={{
              fontFamily: 'var(--font-mono)', fontSize: '13px', cursor: 'pointer',
              padding: '7px 14px', borderRadius: 'var(--radius-sm)',
              border: '1px solid ' + (tab === t ? 'var(--border-green)' : 'var(--border-default)'),
              background: tab === t ? 'rgba(0,255,140,0.08)' : 'transparent',
              color: tab === t ? 'var(--necro-green)' : 'var(--text-muted)',
            }}>{t}</button>
          ))}
        </div>
        <pre style={{ margin: 0, background: 'var(--surface-terminal)', border: '1px solid var(--border-green)', borderRadius: 'var(--radius-lg)', padding: '20px', fontFamily: 'var(--font-mono)', fontSize: '13px', lineHeight: 1.7, color: 'var(--text-terminal)', overflow: 'auto', boxShadow: 'var(--shadow-md)' }}>{code[tab]}</pre>
      </div>
      {/* sessions */}
      <div>
        <h2 style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'var(--fs-h3)', color: 'var(--text-primary)', margin: '0 0 18px' }}>Snapshot</h2>
        <Card padding="var(--space-4)" style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {sessions.map((s) => (
            <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: '14px', padding: '12px 14px', background: 'var(--surface-inset)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)' }}>
              <Badge tone={s.state} dot pulse={s.state === 'alive'} style={{ flex: 'none' }}>{s.agent}</Badge>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: '14px', color: 'var(--text-primary)' }}>{s.name}</div>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{s.cwd} · {s.id}</div>
              </div>
              <Button variant="ghost" size="sm" onClick={() => setSessions((x) => x.map((y) => y.id === s.id ? { ...y, state: 'alive' } : y))} style={{ flex: 'none' }}>Restore</Button>
              <Button variant="danger" size="sm" onClick={() => setSessions((x) => x.filter((y) => y.id !== s.id))} style={{ flex: 'none' }}>Delete</Button>
            </div>
          ))}
          {sessions.length === 0 ? (
            <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)', fontSize: '13px' }}>No snapshots — the void is empty.</div>
          ) : null}
        </Card>
      </div>
    </section>
  );
}
Object.assign(window, { InstallShowcase });
