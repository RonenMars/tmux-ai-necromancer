const GH = 'https://github.com/RonenMars/tmux-ai-necromancer';

const cols = [
  { h: 'Plugin', items: [
    { label: 'Install', href: GH + '#install' },
    { label: 'Usage', href: GH + '#usage' },
    { label: 'Configuration', href: GH + '#configuration' },
    { label: 'Supported Agents', href: GH + '/blob/main/docs/agents.md' },
  ]},
  { h: 'Resources', items: [
    { label: 'README', href: GH + '#readme' },
    { label: 'docs/agents.md', href: GH + '/blob/main/docs/agents.md' },
    { label: 'TUI Viewer', href: GH + '/tree/main/tui' },
    { label: 'Changelog', href: GH + '/releases' },
  ]},
  { h: 'Project', items: [
    { label: 'GitHub', href: GH },
    { label: 'Issues', href: GH + '/issues' },
    { label: 'License (MIT)', href: GH + '/blob/main/LICENSE' },
    { label: 'tmux-resurrect', href: 'https://github.com/tmux-plugins/tmux-resurrect' },
  ]},
];

export default function Footer() {
  return (
    <footer style={{ background: 'var(--void-900)', borderTop: '1px solid var(--line)' }}>
      <div style={{
        padding: '56px 28px 40px', maxWidth: 1200, margin: '0 auto',
        display: 'grid', gridTemplateColumns: '1.4fr 1fr 1fr 1fr', gap: 40,
      }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: 16 }}>
            <img src="/skull-mark.png" alt="" width="32" height="32" style={{ borderRadius: 'var(--radius-sm)', border: '1px solid var(--line)' }} />
            <span style={{
              fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: 15,
              letterSpacing: '-0.02em', color: 'var(--necro-green)', textTransform: 'lowercase',
            }}>
              tmux-<span style={{ color: 'var(--azure)' }}>ai</span>-necromancer
            </span>
          </div>
          <p style={{ margin: 0, fontSize: 13, lineHeight: 1.6, color: 'var(--text-4)', maxWidth: 280 }}>
            Resurrect AI coding-agent sessions across tmux crashes and reboots.
            Born from a real bug — heap corruption in copy mode killing a dozen live sessions at once.
          </p>
        </div>
        {cols.map((c) => (
          <div key={c.h}>
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: 11, letterSpacing: '0.12em',
              textTransform: 'uppercase', color: 'var(--text-3)', marginBottom: 14,
            }}>{c.h}</div>
            <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
              {c.items.map((it) => (
                <li key={it.label}>
                  <a href={it.href} target="_blank" rel="noopener noreferrer" style={{ fontSize: 13.5, color: 'var(--text-3)', textDecoration: 'none', transition: 'color 160ms' }}
                    onMouseEnter={(e) => e.currentTarget.style.color = 'var(--necro-green)'}
                    onMouseLeave={(e) => e.currentTarget.style.color = 'var(--text-3)'}
                  >{it.label}</a>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div style={{
        borderTop: '1px solid var(--line-faint)', padding: '20px 28px',
        maxWidth: 1200, margin: '0 auto',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        flexWrap: 'wrap', gap: 12,
      }}>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-4)' }}>
          MIT © RonenMars · tmux ≥ 3.0
        </span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-4)' }}>
          no AI attribution in commits — by convention
        </span>
      </div>
    </footer>
  );
}

