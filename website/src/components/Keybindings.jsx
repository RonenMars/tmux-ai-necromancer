import { SectionHead } from './Features';

const binds = [
  { keys: ['Prefix', 'R'], tone: 'green', label: 'Restore latest snapshot', sub: 'popup' },
  { keys: ['Prefix', 'I'], tone: 'azure', label: 'Install via TPM', sub: 'tpm' },
];

const cmds = [
  { cmd: 'necro-snapshot.sh --idle-only', label: 'Manual snapshot, no disruption' },
  { cmd: 'necro-restore.sh --dry-run', label: 'Preview a restore' },
  { cmd: 'necro-reboot-prep.sh', label: 'Before reboot' },
  { cmd: 'necro-reboot-resume.sh', label: 'After reboot' },
];

function Keycap({ children, tone = 'neutral' }) {
  const colors = {
    neutral: { bg: 'var(--surface-3)', color: 'var(--text-1)', border: 'var(--line-strong)' },
    green: { bg: 'rgba(0,255,140,0.12)', color: 'var(--necro-green)', border: 'var(--line-green)' },
    azure: { bg: 'rgba(0,212,255,0.12)', color: 'var(--azure)', border: 'var(--line-azure)' },
  };
  const c = colors[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      padding: '6px 14px', minWidth: 36, borderRadius: 'var(--radius-xs)',
      fontFamily: 'var(--font-mono)', fontSize: 13, fontWeight: 600,
      background: c.bg, color: c.color,
      border: `1px solid ${c.border}`,
      boxShadow: '0 2px 0 rgba(0,0,0,0.4)',
    }}>{children}</span>
  );
}

export default function Keybindings() {
  return (
    <section id="resources" style={{ padding: '80px 28px', maxWidth: 1200, margin: '0 auto' }}>
      <SectionHead eyebrow="// keybindings & commands" title="Two keys. The rest is muscle memory." />
      <div style={{
        display: 'grid', gridTemplateColumns: '0.85fr 1.15fr', gap: 40,
        marginTop: 44, alignItems: 'start',
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          {binds.map((b) => (
            <div key={b.keys.join()} style={{
              display: 'flex', alignItems: 'center', gap: 16, padding: '18px 20px',
              background: 'var(--surface-1)', border: '1px solid var(--line)',
              borderRadius: 'var(--radius-md)',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Keycap tone="neutral">{b.keys[0]}</Keycap>
                <span style={{ color: 'var(--text-4)', fontFamily: 'var(--font-mono)' }}>+</span>
                <Keycap tone={b.tone}>{b.keys[1]}</Keycap>
              </div>
              <div>
                <div style={{ fontSize: 14, color: 'var(--text-1)', fontWeight: 600 }}>{b.label}</div>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-4)' }}>{b.sub}</div>
              </div>
            </div>
          ))}
        </div>

        <div style={{
          border: '1px solid var(--line)', borderRadius: 'var(--radius-md)',
          overflow: 'hidden', background: 'var(--surface-1)',
        }}>
          {cmds.map((c, i) => (
            <div key={c.cmd} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16,
              padding: '16px 20px',
              borderTop: i ? '1px solid var(--line-faint)' : 'none',
            }}>
              <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13, color: 'var(--necro-green)' }}>
                {c.cmd}
              </code>
              <span style={{ fontSize: 12.5, color: 'var(--text-3)', textAlign: 'right', flexShrink: 0 }}>
                {c.label}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
