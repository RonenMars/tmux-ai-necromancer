import { useState } from 'react';

const CMD = "set -g @plugin 'RonenMars/tmux-ai-necromancer'";

const agents = [
  { name: 'Claude Code', store: '~/.claude/projects/<cwd>/<uuid>.jsonl', resume: 'claude --resume <id>' },
  { name: 'Codex', store: '~/.codex/sessions/<date>/rollout-*.jsonl', resume: 'codex resume <id>' },
];

export default function Install() {
  const [copied, setCopied] = useState(false);

  const copy = () => {
    navigator.clipboard?.writeText(CMD);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <section id="terminal" style={{
      background: 'var(--void-900)',
      borderTop: '1px solid var(--line-faint)',
    }}>
      <div style={{ padding: '80px 28px', maxWidth: 1000, margin: '0 auto', textAlign: 'center' }}>
        <div className="eyebrow" style={{ marginBottom: 16 }}>// install</div>
        <h2 style={{
          margin: 0, fontFamily: 'var(--font-display)', fontWeight: 800,
          fontSize: 'clamp(30px, 4vw, 46px)', letterSpacing: '-0.03em', lineHeight: 1.05,
          color: 'var(--text-1)',
        }}>
          One line in{' '}
          <span style={{ color: 'var(--necro-green)' }}>~/.tmux.conf</span>
        </h2>
        <p style={{ margin: '18px auto 0', maxWidth: 520, fontSize: 16, color: 'var(--text-3)' }}>
          Add the plugin, press{' '}
          <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--text-2)' }}>prefix + I</span>,
          and autosave starts immediately.
        </p>

        {/* copy bar */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 14, margin: '32px auto 0', maxWidth: 640,
          padding: '14px 16px 14px 20px',
          background: 'var(--void-700)', border: '1px solid var(--line-strong)',
          borderRadius: 'var(--radius-md)',
          boxShadow: '0 0 40px rgba(0,255,140,0.06)',
        }}>
          <span style={{ color: 'var(--necro-green)', fontFamily: 'var(--font-mono)' }}>$</span>
          <code style={{
            flex: 1, textAlign: 'left', fontFamily: 'var(--font-mono)', fontSize: 14,
            color: 'var(--text-1)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            background: 'none',
          }}>{CMD}</code>
          <CopyBtn copied={copied} onClick={copy} />
        </div>

        {/* agents table */}
        <div style={{ marginTop: 48, textAlign: 'left' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16, justifyContent: 'center',
          }}>
            <span style={{
              width: 8, height: 8, borderRadius: '50%', background: 'var(--necro-green)',
              boxShadow: 'var(--glow-green-sm)', display: 'inline-block',
            }} />
            <span style={{
              fontFamily: 'var(--font-mono)', fontSize: 12, letterSpacing: '0.1em',
              textTransform: 'uppercase', color: 'var(--text-3)',
            }}>
              Supported agents — adding one is a single file
            </span>
          </div>
          <div style={{ border: '1px solid var(--line)', borderRadius: 'var(--radius-md)', overflow: 'hidden' }}>
            {agents.map((a, i) => (
              <div key={a.name} style={{
                display: 'grid', gridTemplateColumns: '160px 1fr 1fr', gap: 16, alignItems: 'center',
                padding: '16px 20px', background: 'var(--surface-1)',
                borderTop: i ? '1px solid var(--line-faint)' : 'none',
              }}>
                <div style={{ fontWeight: 600, color: 'var(--text-1)', fontSize: 14 }}>{a.name}</div>
                <code style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-3)', background: 'none' }}>
                  {a.store}
                </code>
                <code style={{ fontFamily: 'var(--font-mono)', fontSize: 12.5, color: 'var(--azure)', background: 'none' }}>
                  {a.resume}
                </code>
              </div>
            ))}
          </div>
        </div>

        <div style={{ marginTop: 40 }}>
          <a href="https://github.com/RonenMars/tmux-ai-necromancer#install" target="_blank" rel="noopener noreferrer" style={{
            display: 'inline-block', padding: '15px 32px', borderRadius: 'var(--radius-sm)',
            fontFamily: 'var(--font-mono)', fontSize: 15, fontWeight: 700, textDecoration: 'none',
            background: 'var(--necro-green)', color: 'var(--text-on-green)',
            boxShadow: 'var(--glow-green)',
          }}>
            Get Started
          </a>
        </div>
      </div>
    </section>
  );
}

function CopyBtn({ copied, onClick }) {
  return (
    <button onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      padding: '7px 14px', borderRadius: 'var(--radius-sm)',
      fontFamily: 'var(--font-mono)', fontSize: 13, fontWeight: 600, cursor: 'pointer',
      background: copied ? 'var(--necro-green)' : 'var(--surface-2)',
      color: copied ? 'var(--text-on-green)' : 'var(--text-1)',
      border: copied ? 'none' : '1px solid var(--line-strong)',
      transition: 'all 160ms', flexShrink: 0,
    }}>
      {copied ? (
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="20 6 9 17 4 12"/>
        </svg>
      ) : (
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
        </svg>
      )}
      {copied ? 'Copied' : 'Copy'}
    </button>
  );
}
