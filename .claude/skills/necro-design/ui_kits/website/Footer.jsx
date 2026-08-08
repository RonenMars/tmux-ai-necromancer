// Footer — supported agents table + links.
function Footer() {
  const { Badge } = window.DesignSystem_7d9b63;
  const agents = [
    { name: 'Claude Code', store: '~/.claude/projects/<cwd>/<uuid>.jsonl', resume: 'claude --resume <uuid>' },
    { name: 'Codex', store: '~/.codex/sessions/<date>/rollout-*-<uuid>.jsonl', resume: 'codex resume <uuid>' },
  ];
  return (
    <footer style={{ borderTop: '1px solid var(--border-subtle)', background: 'var(--bg-sunken)' }}>
      <div style={{ maxWidth: 'var(--container-max)', margin: '0 auto', padding: '56px 40px 40px' }}>
        <h2 style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'var(--fs-h4)', color: 'var(--text-primary)', margin: '0 0 6px' }}>Supported agents</h2>
        <p style={{ color: 'var(--text-muted)', margin: '0 0 22px', fontSize: '14px' }}>Want another? It's one adapter file.</p>
        <div style={{ display: 'grid', gridTemplateColumns: '180px 1fr 1fr', gap: '0', fontFamily: 'var(--font-mono)', fontSize: '13px', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', overflow: 'hidden' }}>
          {['Agent', 'Transcript store', 'Resume'].map((h) => (
            <div key={h} style={{ padding: '12px 16px', background: 'var(--surface-raised)', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.1em', fontSize: '11px', borderBottom: '1px solid var(--border-subtle)' }}>{h}</div>
          ))}
          {agents.map((a) => (
            <React.Fragment key={a.name}>
              <div style={{ padding: '14px 16px', color: 'var(--necro-green)', borderBottom: '1px solid var(--border-subtle)' }}>{a.name}</div>
              <div style={{ padding: '14px 16px', color: 'var(--text-secondary)', borderBottom: '1px solid var(--border-subtle)' }}>{a.store}</div>
              <div style={{ padding: '14px 16px', color: 'var(--azure-circuit)', borderBottom: '1px solid var(--border-subtle)' }}>{a.resume}</div>
            </React.Fragment>
          ))}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '40px', paddingTop: '24px', borderTop: '1px solid var(--border-subtle)', flexWrap: 'wrap', gap: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <img src="../../assets/logo-mark.png" alt="" style={{ height: '32px' }} />
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: '13px', color: 'var(--text-muted)' }}>MIT · github.com/RonenMars/tmux-ai-necromancer</span>
          </div>
          <Badge tone="alive" dot pulse>autosave running</Badge>
        </div>
      </div>
    </footer>
  );
}
Object.assign(window, { Footer });
