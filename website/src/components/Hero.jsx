import { useState, useEffect, useMemo } from 'react';
import TerminalWindow from './TerminalWindow';

const GITHUB = 'https://github.com/RonenMars/tmux-ai-necromancer';

export default function Hero() {
  return (
    <section id="top" style={{
      position: 'relative', overflow: 'hidden',
      padding: '72px 28px 64px',
      background: 'var(--grad-hero-vignette), var(--bg-page)',
    }}>
      <img src="/necromancer-skull.png" alt="" aria-hidden="true" style={{
        position: 'absolute', right: -80, top: -20, width: 620,
        opacity: 0.10, pointerEvents: 'none', filter: 'saturate(1.2)',
        maskImage: 'radial-gradient(60% 60% at 50% 40%, #000 30%, transparent 75%)',
        WebkitMaskImage: 'radial-gradient(60% 60% at 50% 40%, #000 30%, transparent 75%)',
      }} />

      <div style={{
        position: 'relative', maxWidth: 1200, margin: '0 auto',
        display: 'grid', gridTemplateColumns: '1.05fr 1fr', gap: 56, alignItems: 'center',
      }}>
        {/* left — copy */}
        <div>
          <div className="eyebrow" style={{ marginBottom: 20 }}>
            // tmux-resurrect for your AI agents
          </div>
          <h1 style={{
            margin: 0, fontFamily: 'var(--font-display)', fontWeight: 800,
            fontSize: 'clamp(38px, 5vw, 60px)', lineHeight: 1.02, letterSpacing: '-0.03em',
            color: 'var(--text-1)',
          }}>
            Bring your dead<br />coding agents{' '}
            <span className="glow-text" style={{ color: 'var(--necro-green)' }}>back to life.</span>
          </h1>
          <p style={{
            margin: '22px 0 0', maxWidth: 480, fontSize: 18, lineHeight: 1.6,
            color: 'var(--text-3)',
          }}>
            Snapshots your running Claude Code &amp; Codex sessions on a timer and
            resurrects them — exact session resumed — after a crash, reboot, or{' '}
            <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--text-2)' }}>tmux kill-server</span>.
          </p>
          <div style={{ display: 'flex', gap: 14, marginTop: 32, flexWrap: 'wrap' }}>
            <Btn primary glow href={GITHUB + '#install'}>Install Plugin</Btn>
            <Btn iconLeft href={GITHUB}>View on GitHub</Btn>
          </div>
          <div style={{ display: 'flex', gap: 20, marginTop: 28, alignItems: 'center', flexWrap: 'wrap' }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '3px 10px 3px 6px',
              border: '1px solid var(--line-green)',
              borderRadius: 'var(--radius-sm)',
              fontFamily: 'var(--font-mono)', fontSize: 11, fontWeight: 600,
              letterSpacing: '0.08em', color: 'var(--necro-green)',
            }}>
              <span style={{
                width: 6, height: 6, borderRadius: '50%', background: 'var(--necro-green)',
                boxShadow: 'var(--glow-green-sm)',
                animation: 'necro-pulse 2s infinite',
              }} />
              MULTI-AGENT
            </span>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-4)' }}>
              TPM-compatible · bash + Go · MIT
            </span>
          </div>
        </div>

        {/* right — restore demo */}
        <RestoreDemo />
      </div>
    </section>
  );
}

function RestoreDemo() {
  const script = useMemo(() => [
    { t: '$ necro-restore.sh', c: 'var(--text-2)' },
    { t: 'reading latest snapshot · 12 panes', c: 'var(--text-3)' },
    { t: '↺ restoring tb-mobile:3  claude --resume a1b2c3', c: 'var(--azure)' },
    { t: '↺ restoring api:1        codex resume 9f8e7d', c: 'var(--azure)' },
    { t: '↺ restoring web:0        claude --resume 4d5e6f', c: 'var(--azure)' },
    { t: '✓ 12 sessions reanimated · 0 duplicates', c: 'var(--necro-green)' },
  ], []);

  const [n, setN] = useState(0);
  useEffect(() => {
    if (n >= script.length) {
      const r = setTimeout(() => setN(0), 2600);
      return () => clearTimeout(r);
    }
    const d = setTimeout(() => setN((x) => x + 1), n === 0 ? 500 : 650);
    return () => clearTimeout(d);
  }, [n, script.length]);

  return (
    <TerminalWindow title="~/dev — necromancer" glow bodyStyle={{ minHeight: 230 }}>
      {script.slice(0, n).map((line, i) => (
        <div key={i} style={{ color: line.c }}>{line.t}</div>
      ))}
      {n < script.length && (
        <div style={{ color: 'var(--necro-green)' }}><span className="cursor" /></div>
      )}
    </TerminalWindow>
  );
}

function Btn({ children, primary, glow, iconLeft, href }) {
  const [hov, setHov] = useState(false);
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 8,
        padding: '13px 24px', borderRadius: 'var(--radius-sm)',
        fontFamily: 'var(--font-mono)', fontSize: 14, fontWeight: 600,
        cursor: 'pointer', textDecoration: 'none', transition: 'all 160ms',
        ...(primary ? {
          background: hov ? 'var(--necro-green-bright)' : 'var(--necro-green)',
          color: 'var(--text-on-green)',
          boxShadow: glow ? 'var(--glow-green)' : 'none',
          border: 'none',
        } : {
          background: hov ? 'var(--surface-2)' : 'var(--surface-1)',
          color: 'var(--text-1)',
          border: '1px solid var(--line-strong)',
        }),
      }}
    >
      {iconLeft && <TerminalIcon />}
      {children}
    </a>
  );
}

function TerminalIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="4 17 10 11 4 5" /><line x1="12" y1="19" x2="20" y2="19" />
    </svg>
  );
}
