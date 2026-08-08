// Nav — top marketing bar. Logo + links + auth actions.
function Nav({ active = 'Home', onNav }) {
  const { Button } = window.DesignSystem_7d9b63;
  const links = ['Home', 'Features', 'Resources', 'Terminal'];
  return (
    <header style={{
      position: 'sticky', top: 0, zIndex: 50,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '16px 40px',
      background: 'rgba(10,10,20,0.72)', backdropFilter: 'blur(12px)',
      borderBottom: '1px solid var(--border-subtle)',
    }}>
      <a href="#" onClick={(e)=>{e.preventDefault();onNav&&onNav('Home');}} style={{ display: 'flex', alignItems: 'center', gap: '12px', textDecoration: 'none' }}>
        <img src="../../assets/logo-mark.png" alt="" style={{ height: '38px', filter: 'drop-shadow(0 0 8px rgba(0,255,140,0.35))' }} />
        <span style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '15px', lineHeight: 1.05, color: 'var(--necro-green)' }}>
          tmux-<span style={{ color: 'var(--azure-circuit)' }}>ai</span>-<br/>necromancer
        </span>
      </a>
      <nav style={{ display: 'flex', alignItems: 'center', gap: '32px' }}>
        {links.map((l) => (
          <a key={l} href="#" onClick={(e)=>{e.preventDefault();onNav&&onNav(l);}}
            style={{
              fontFamily: 'var(--font-body)', fontWeight: 600, fontSize: '14px',
              textDecoration: 'none', paddingBottom: '4px',
              color: active === l ? 'var(--necro-green)' : 'var(--text-secondary)',
              borderBottom: active === l ? '2px solid var(--necro-green)' : '2px solid transparent',
            }}>{l}</a>
        ))}
      </nav>
      <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
        <Button variant="ghost" size="sm" style={{ border: 'none' }}>Log In</Button>
        <Button variant="primary" size="sm">Sign Up</Button>
      </div>
    </header>
  );
}
Object.assign(window, { Nav });
