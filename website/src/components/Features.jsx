function SectionHead({ eyebrow, title, sub }) {
  return (
    <div style={{ maxWidth: 640 }}>
      <div className="eyebrow" style={{ marginBottom: 14 }}>{eyebrow}</div>
      <h2 style={{
        margin: 0, fontFamily: 'var(--font-display)', fontWeight: 700,
        fontSize: 'clamp(26px, 3vw, 36px)', letterSpacing: '-0.02em', lineHeight: 1.1,
        color: 'var(--text-1)',
      }}>{title}</h2>
      {sub && <p style={{ margin: '14px 0 0', fontSize: 16, color: 'var(--text-3)', lineHeight: 1.6 }}>{sub}</p>}
    </div>
  );
}

export { SectionHead };

const ICONS = {
  'folder-check': (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2z"/>
      <polyline points="9 13 11 15 15 11"/>
    </svg>
  ),
  brain: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96-.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24 2.5 2.5 0 0 1 1.98-3A2.5 2.5 0 0 1 9.5 2Z"/><path d="M14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96-.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24 2.5 2.5 0 0 0-1.98-3A2.5 2.5 0 0 0 14.5 2Z"/>
    </svg>
  ),
  database: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4.03 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4.03 3 9 3s9-1.34 9-3"/>
    </svg>
  ),
  'timer-reset': (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 2h4"/><path d="M12 14v-4"/><path d="M4 13a8 8 0 0 1 8-7 8 8 0 1 1-5.3 14L4 17"/><path d="M9 17H4v5"/>
    </svg>
  ),
};

const items = [
  { icon: 'folder-check', title: 'Automatic Checkpointing', body: 'Every 5 minutes, walks every tmux pane and records each agent + resumable session id to a snapshot. Runs in the background, off the status bar.' },
  { icon: 'brain', title: 'AI Agent Continuity', body: 'Resumes the exact conversation per agent — claude --resume, codex resume — so context survives the crash, not just the layout.' },
  { icon: 'database', title: 'Process Serialization', body: 'Session ids captured two ways: scraped from scrollback on clean exit, or a filesystem fallback that finds the most-recent transcript.' },
  { icon: 'timer-reset', title: 'Boot-Time Reanimation', body: 'prep / resume wrappers pair with tmux-resurrect + continuum to bring the whole layout — and every agent — back after a reboot.' },
];

export default function Features() {
  return (
    <section id="features" style={{ padding: '80px 28px', maxWidth: 1200, margin: '0 auto' }}>
      <SectionHead eyebrow="// what it does" title="Four moves between dead and alive" />
      <div className="grid-features" style={{
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 18, marginTop: 44,
      }}>
        {items.map((it) => (
          <div key={it.title} style={{
            padding: '22px',
            background: 'var(--surface-1)',
            border: '1px solid var(--line)',
            borderRadius: 'var(--radius-md)',
            transition: 'border-color 180ms, background 180ms',
            cursor: 'default',
          }}
            onMouseEnter={(e) => {
              e.currentTarget.style.borderColor = 'var(--line-green)';
              e.currentTarget.style.background = 'var(--surface-2)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.borderColor = 'var(--line)';
              e.currentTarget.style.background = 'var(--surface-1)';
            }}
          >
            <span style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              width: 44, height: 44, borderRadius: 'var(--radius-md)',
              background: 'rgba(0,255,140,0.08)', border: '1px solid var(--line-green)',
              color: 'var(--necro-green)', marginBottom: 18,
            }}>
              {ICONS[it.icon]}
            </span>
            <h3 style={{
              margin: '0 0 8px', fontFamily: 'var(--font-display)', fontWeight: 700,
              fontSize: 17, color: 'var(--text-1)', lineHeight: 1.2,
            }}>{it.title}</h3>
            <p style={{ margin: 0, fontSize: 13.5, lineHeight: 1.55, color: 'var(--text-3)' }}>{it.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
