import { useState } from 'react';

export default function Nav() {
  const [hover, setHover] = useState(null);
  const links = [
    { label: 'Home', href: '#top' },
    { label: 'Features', href: '#features' },
    { label: 'Resources', href: '#resources' },
    { label: 'Terminal', href: '#terminal' },
  ];

  return (
    <header style={{
      position: 'sticky', top: 0, zIndex: 100,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 28px', height: 64,
      background: 'var(--glass-bg)', backdropFilter: 'blur(14px)',
      WebkitBackdropFilter: 'blur(14px)',
      borderBottom: '1px solid var(--line-faint)',
    }}>
      <a href="#top" style={{ display: 'flex', alignItems: 'center', gap: 11, textDecoration: 'none' }}>
        <img src="/skull-mark.png" alt="" width="34" height="34" style={{ borderRadius: 'var(--radius-sm)', border: '1px solid var(--line)' }} />
        <span style={{
          fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: 16,
          letterSpacing: '-0.02em', color: 'var(--necro-green)', textTransform: 'lowercase',
        }}>
          tmux-<span style={{ color: 'var(--azure)' }}>ai</span>-necromancer
        </span>
      </a>

      <nav style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        {links.map((l) => {
          const active = l.label === 'Home';
          const on = hover === l.label;
          return (
            <a key={l.label} href={l.href}
              onMouseEnter={() => setHover(l.label)} onMouseLeave={() => setHover(null)}
              style={{
                position: 'relative', padding: '8px 14px', textDecoration: 'none',
                fontFamily: 'var(--font-ui)', fontSize: 14, fontWeight: 500,
                color: active ? 'var(--necro-green)' : on ? 'var(--text-1)' : 'var(--text-3)',
                transition: 'color 160ms',
              }}>
              {l.label}
              {active && <span style={{
                position: 'absolute', left: 14, right: 14, bottom: 2, height: 2,
                background: 'var(--necro-green)', boxShadow: 'var(--glow-green-sm)', borderRadius: 2,
              }} />}
            </a>
          );
        })}
      </nav>
    </header>
  );
}

