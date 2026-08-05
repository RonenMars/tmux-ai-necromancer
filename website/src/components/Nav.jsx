import { useState, useEffect } from 'react';

const links = [
  { label: 'Home', href: '#top' },
  { label: 'Features', href: '#features' },
  { label: 'Keybindings', href: '#resources' },
  { label: 'Install', href: '#terminal' },
];

export default function Nav() {
  const [hover, setHover] = useState(null);
  const [open, setOpen] = useState(false);

  // close on resize back to desktop
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 769px)');
    const handler = (e) => { if (e.matches) setOpen(false); };
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  // close on nav click
  const handleLink = () => setOpen(false);

  return (
    <>
      <header style={{
        position: 'sticky', top: 0, zIndex: 200,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 28px', height: 64,
        background: 'var(--glass-bg)', backdropFilter: 'blur(14px)',
        WebkitBackdropFilter: 'blur(14px)',
        borderBottom: '1px solid var(--line-faint)',
      }}>
        <a href="#top" style={{ display: 'flex', alignItems: 'center', gap: 11, textDecoration: 'none' }}>
          <img
            src="/logo-mark-nav.png"
            alt=""
            height="38"
            style={{ height: 38, width: 'auto', display: 'block', filter: 'drop-shadow(0 0 8px rgba(0,255,140,0.35))' }}
          />
          <span style={{
            fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: 16,
            letterSpacing: '-0.02em', color: 'var(--necro-green)', textTransform: 'lowercase',
          }}>
            tmux-<span style={{ color: 'var(--azure)' }}>ai</span>-necromancer
          </span>
        </a>

        {/* desktop nav */}
        <nav className="nav-links" style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
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

        {/* hamburger — mobile only */}
        <button
          className="hamburger"
          onClick={() => setOpen((o) => !o)}
          aria-label="Toggle menu"
          aria-expanded={open}
          style={{
            display: 'none', // shown via CSS
            flexDirection: 'column', justifyContent: 'center', alignItems: 'center',
            gap: 0, width: 44, height: 44, padding: 0,
            background: 'none', border: 'none', cursor: 'pointer',
          }}
        >
          <Bar open={open} i={0} />
          <Bar open={open} i={1} />
          <Bar open={open} i={2} />
        </button>
      </header>

      {/* mobile drawer */}
      <div
        className="mobile-drawer"
        style={{
          position: 'fixed', top: 64, left: 0, right: 0, zIndex: 199,
          background: 'rgba(10,10,20,0.97)', backdropFilter: 'blur(20px)',
          WebkitBackdropFilter: 'blur(20px)',
          borderBottom: '1px solid var(--line)',
          padding: open ? '24px 28px 32px' : '0 28px',
          maxHeight: open ? '320px' : '0',
          overflow: 'hidden',
          transition: 'max-height 320ms cubic-bezier(0.4,0,0.2,1), padding 320ms cubic-bezier(0.4,0,0.2,1)',
        }}
      >
        <nav style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {links.map((l, i) => (
            <a
              key={l.label}
              href={l.href}
              onClick={handleLink}
              style={{
                padding: '14px 0',
                fontFamily: 'var(--font-display)', fontSize: 22, fontWeight: 700,
                color: l.label === 'Home' ? 'var(--necro-green)' : 'var(--text-2)',
                textDecoration: 'none', letterSpacing: '-0.01em',
                borderBottom: i < links.length - 1 ? '1px solid var(--line-faint)' : 'none',
                transition: 'color 160ms',
                opacity: open ? 1 : 0,
                transform: open ? 'translateY(0)' : 'translateY(-8px)',
                transitionDelay: open ? `${i * 50}ms` : '0ms',
                display: 'block',
              }}
              onMouseEnter={(e) => e.currentTarget.style.color = 'var(--necro-green)'}
              onMouseLeave={(e) => e.currentTarget.style.color = l.label === 'Home' ? 'var(--necro-green)' : 'var(--text-2)'}
            >
              <span style={{ color: 'var(--text-4)', fontFamily: 'var(--font-mono)', fontSize: 12, marginRight: 10 }}>
                {String(i + 1).padStart(2, '0')}
              </span>
              {l.label}
            </a>
          ))}
        </nav>
      </div>

      {/* backdrop */}
      {open && (
        <div
          onClick={() => setOpen(false)}
          style={{
            position: 'fixed', inset: 0, zIndex: 198,
            background: 'rgba(0,0,0,0.4)',
            animation: 'fadeIn 200ms ease',
          }}
        />
      )}
    </>
  );
}

function Bar({ open, i }) {
  const transforms = {
    0: open ? 'translateY(9px) rotate(45deg)' : 'translateY(0) rotate(0)',
    1: open ? 'scaleX(0)' : 'scaleX(1)',
    2: open ? 'translateY(-9px) rotate(-45deg)' : 'translateY(0) rotate(0)',
  };
  return (
    <span style={{
      display: 'block', width: 22, height: 2, borderRadius: 2,
      background: 'var(--text-2)',
      margin: '3.5px 0',
      transition: 'transform 280ms cubic-bezier(0.4,0,0.2,1), opacity 200ms, background 160ms',
      transform: transforms[i],
      opacity: open && i === 1 ? 0 : 1,
      transformOrigin: 'center',
    }} />
  );
}
