import { SectionHead } from './Features';
import TerminalWindow from './TerminalWindow';

const steps = [
  { k: '01', cmd: 'autosave', title: 'Snapshot', body: 'A throttled #(...) hook on status-right fires a non-disruptive --idle-only snapshot. Never touches a running agent.' },
  { k: '02', cmd: 'jsonl', title: 'Serialize', body: 'One record per pane: agent, cwd, window marker, and the resumable uuid — written as JSON Lines.' },
  { k: '03', cmd: 'restore', title: 'Reanimate', body: 'Rebuilds sessions/windows and runs the right resume command per agent. Idempotent — re-runs add zero windows.' },
];

export default function HowItWorks() {
  return (
    <section style={{
      background: 'var(--void-900)',
      borderTop: '1px solid var(--line-faint)',
      borderBottom: '1px solid var(--line-faint)',
    }}>
      <div style={{ padding: '80px 28px', maxWidth: 1200, margin: '0 auto' }}>
        <SectionHead eyebrow="// how it works" title="Like tmux-continuum, but for conversations" />
        <div style={{
          display: 'grid', gridTemplateColumns: '1.1fr 0.9fr', gap: 40,
          marginTop: 44, alignItems: 'center',
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {steps.map((s, i) => (
              <div key={s.k} style={{ display: 'flex', gap: 18, alignItems: 'flex-start' }}>
                <div style={{
                  flex: 'none', width: 46, height: 46, borderRadius: 'var(--radius-md)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontFamily: 'var(--font-mono)', fontSize: 15, fontWeight: 700,
                  color: 'var(--necro-green)', background: 'var(--surface-1)',
                  border: '1px solid var(--line-green)',
                }}>{s.k}</div>
                <div style={{ paddingTop: 2 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <h3 style={{
                      margin: 0, fontFamily: 'var(--font-display)', fontWeight: 700,
                      fontSize: 17, color: 'var(--text-1)',
                    }}>{s.title}</h3>
                    <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-4)' }}>
                      necro-{s.cmd}.sh
                    </span>
                  </div>
                  <p style={{ margin: '6px 0 0', fontSize: 14, lineHeight: 1.55, color: 'var(--text-3)', maxWidth: 460 }}>
                    {s.body}
                  </p>
                  {i < steps.length - 1 && (
                    <div style={{ width: 1, height: 12, marginLeft: -32, marginTop: 8, background: 'var(--line)' }} />
                  )}
                </div>
              </div>
            ))}
          </div>

          <TerminalWindow title="snapshot.jsonl" bodyStyle={{ fontSize: 12.5, lineHeight: 1.85 }}>
            <div style={{ color: 'var(--text-4)' }}>{'{'}</div>
            <div style={{ paddingLeft: 16 }}>
              <Row k="pane_id" v='"%5"' c="var(--azure)" />
              <Row k="session" v='"tb-mobile"' c="var(--azure)" />
              <Row k="agent" v='"claude"' />
              <Row k="cwd" v='"~/dev/app"' c="var(--azure)" />
              <Row k="uuid" v='"a1b2c3d4-…"' />
              <Row k="uuid_source" v='"latest-jsonl"' />
            </div>
            <div style={{ color: 'var(--text-4)' }}>{'}'}</div>
          </TerminalWindow>
        </div>
      </div>
    </section>
  );
}

function Row({ k, v, c }) {
  return (
    <div>
      <span style={{ color: 'var(--text-4)' }}>"{k}"</span>
      <span style={{ color: 'var(--text-4)' }}>: </span>
      <span style={{ color: c || 'var(--necro-green)' }}>{v}</span>
      <span style={{ color: 'var(--text-4)' }}>,</span>
    </div>
  );
}
