/* @ds-bundle: {"format":4,"namespace":"DesignSystem_7d9b63","components":[{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"Input","sourcePath":"components/controls/Input.jsx"},{"name":"Badge","sourcePath":"components/display/Badge.jsx"},{"name":"KeyCap","sourcePath":"components/display/KeyCap.jsx"},{"name":"KeyCombo","sourcePath":"components/display/KeyCap.jsx"},{"name":"Card","sourcePath":"components/surfaces/Card.jsx"},{"name":"FeatureCard","sourcePath":"components/surfaces/FeatureCard.jsx"},{"name":"TerminalWindow","sourcePath":"components/surfaces/TerminalWindow.jsx"}],"sourceHashes":{"components/controls/Button.jsx":"f32cc6495eda","components/controls/Input.jsx":"e7cd72b33ea7","components/display/Badge.jsx":"79cb4bfa1df7","components/display/KeyCap.jsx":"5638d0ffac68","components/surfaces/Card.jsx":"63a88c3e673d","components/surfaces/FeatureCard.jsx":"3a0e0c2f1a54","components/surfaces/TerminalWindow.jsx":"98123767285e","ui_kits/website/FeatureGrid.jsx":"d5dfbc89209d","ui_kits/website/Footer.jsx":"ca81db31ecfa","ui_kits/website/Hero.jsx":"3850b171fccd","ui_kits/website/InstallShowcase.jsx":"be8b1dbff5ba","ui_kits/website/Keybindings.jsx":"c876d13c4e9e","ui_kits/website/Nav.jsx":"745220cdfe45"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.DesignSystem_7d9b63 = window.DesignSystem_7d9b63 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Button — primary action control for tmux-ai-necromancer.
 * Green fill is the "alive"/primary action; azure is secondary; ghost is
 * low-emphasis; danger is destructive (kill/delete).
 */
function Button({
  variant = 'primary',
  size = 'md',
  disabled = false,
  glow = false,
  iconLeft = null,
  iconRight = null,
  type = 'button',
  onClick,
  children,
  style = {},
  ...rest
}) {
  const sizes = {
    sm: {
      padding: '7px 14px',
      fontSize: '0.8125rem',
      gap: '6px'
    },
    md: {
      padding: '11px 22px',
      fontSize: '0.9375rem',
      gap: '8px'
    },
    lg: {
      padding: '15px 30px',
      fontSize: '1.0625rem',
      gap: '10px'
    }
  };
  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontFamily: 'var(--font-display)',
    fontWeight: 'var(--fw-bold)',
    lineHeight: 1,
    letterSpacing: '0.01em',
    border: '1px solid transparent',
    borderRadius: 'var(--radius-md)',
    cursor: disabled ? 'not-allowed' : 'pointer',
    opacity: disabled ? 0.45 : 1,
    transition: 'transform var(--dur-fast) var(--ease-out), background var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out), border-color var(--dur-base) var(--ease-out)',
    whiteSpace: 'nowrap',
    ...sizes[size]
  };
  const variants = {
    primary: {
      background: 'var(--necro-green)',
      color: 'var(--text-on-green)',
      boxShadow: glow ? 'var(--glow-green-md)' : 'none'
    },
    secondary: {
      background: 'transparent',
      color: 'var(--azure-circuit)',
      borderColor: 'var(--border-azure)',
      boxShadow: glow ? 'var(--glow-azure-sm)' : 'none'
    },
    ghost: {
      background: 'transparent',
      color: 'var(--text-secondary)',
      borderColor: 'var(--border-default)'
    },
    danger: {
      background: 'var(--signal-red)',
      color: '#240606'
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    disabled: disabled,
    onClick: onClick,
    style: {
      ...base,
      ...variants[variant],
      ...style
    },
    onMouseDown: e => {
      if (!disabled) e.currentTarget.style.transform = 'translateY(1px)';
    },
    onMouseUp: e => {
      e.currentTarget.style.transform = 'translateY(0)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.transform = 'translateY(0)';
    }
  }, rest), iconLeft ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      fontSize: '1.1em'
    }
  }, iconLeft) : null, children, iconRight ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      fontSize: '1.1em'
    }
  }, iconRight) : null);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Input — text field with terminal-flavored styling. Optional leading prompt
 * glyph and label. Focus produces a green ring.
 */
function Input({
  label,
  prompt = false,
  prefixGlyph = '›',
  invalid = false,
  type = 'text',
  id,
  style = {},
  containerStyle = {},
  ...rest
}) {
  const [focused, setFocused] = React.useState(false);
  const borderColor = invalid ? 'var(--border-red)' : focused ? 'var(--border-green)' : 'var(--border-default)';
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'block',
      ...containerStyle
    }
  }, label ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      fontFamily: 'var(--font-mono)',
      fontSize: 'var(--fs-caption)',
      textTransform: 'uppercase',
      letterSpacing: 'var(--ls-wider)',
      color: 'var(--text-muted)',
      marginBottom: '8px'
    }
  }, label) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
      background: 'var(--surface-inset)',
      border: `1px solid ${borderColor}`,
      borderRadius: 'var(--radius-md)',
      padding: '0 12px',
      boxShadow: focused && !invalid ? 'var(--glow-green-sm)' : 'none',
      transition: 'border-color var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out)'
    }
  }, prompt ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-mono)',
      color: 'var(--necro-green)',
      fontWeight: 700
    }
  }, prefixGlyph) : null, /*#__PURE__*/React.createElement("input", _extends({
    id: id,
    type: type,
    onFocus: () => setFocused(true),
    onBlur: () => setFocused(false),
    style: {
      flex: 1,
      background: 'transparent',
      border: 'none',
      outline: 'none',
      color: 'var(--text-primary)',
      fontFamily: 'var(--font-mono)',
      fontSize: 'var(--fs-small)',
      padding: '11px 0',
      ...style
    }
  }, rest))));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Input.jsx", error: String((e && e.message) || e) }); }

// components/display/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Badge — compact status/label chip. Tracks the brand's three states:
 * alive (green), data (azure), dead (red), plus neutral/dormant.
 */
function Badge({
  tone = 'alive',
  dot = false,
  pulse = false,
  style = {},
  children,
  ...rest
}) {
  const tones = {
    alive: {
      fg: 'var(--necro-green)',
      bd: 'var(--border-green)',
      bg: 'rgba(0,255,140,0.08)'
    },
    data: {
      fg: 'var(--azure-circuit)',
      bd: 'var(--border-azure)',
      bg: 'rgba(0,212,255,0.08)'
    },
    dead: {
      fg: 'var(--red-400)',
      bd: 'var(--border-red)',
      bg: 'rgba(255,77,77,0.08)'
    },
    dormant: {
      fg: 'var(--text-muted)',
      bd: 'var(--border-default)',
      bg: 'rgba(255,255,255,0.03)'
    }
  };
  const t = tones[tone] || tones.alive;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '7px',
      fontFamily: 'var(--font-mono)',
      fontSize: 'var(--fs-caption)',
      fontWeight: 600,
      letterSpacing: 'var(--ls-wide)',
      textTransform: 'uppercase',
      color: t.fg,
      background: t.bg,
      border: `1px solid ${t.bd}`,
      borderRadius: 'var(--radius-pill)',
      padding: '4px 12px',
      lineHeight: 1.2,
      ...style
    }
  }, rest), dot ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: '7px',
      height: '7px',
      borderRadius: '50%',
      background: t.fg,
      flex: 'none',
      boxShadow: tone === 'alive' ? '0 0 8px var(--green-glow)' : tone === 'data' ? '0 0 8px var(--azure-glow)' : 'none',
      animation: pulse ? 'necroPulse 1.4s var(--ease-in-out) infinite' : 'none'
    }
  }) : null, children, pulse ? /*#__PURE__*/React.createElement("style", null, `@keyframes necroPulse{0%,100%{opacity:1}50%{opacity:0.35}}`) : null);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/Badge.jsx", error: String((e && e.message) || e) }); }

// components/display/KeyCap.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KeyCap — a single keyboard key rendered as a terminal keycap. Compose with
 * <KeyCombo> for "Prefix + n" style bindings. Matches the keybindings section
 * of the brand sheet.
 */
function KeyCap({
  tone = 'neutral',
  size = 'md',
  style = {},
  children,
  ...rest
}) {
  const tones = {
    neutral: {
      fg: 'var(--text-secondary)',
      bd: 'var(--border-strong)',
      bg: 'var(--surface-raised)'
    },
    green: {
      fg: 'var(--necro-green)',
      bd: 'var(--border-green)',
      bg: 'rgba(0,255,140,0.06)'
    },
    azure: {
      fg: 'var(--azure-circuit)',
      bd: 'var(--border-azure)',
      bg: 'rgba(0,212,255,0.06)'
    }
  };
  const sizes = {
    sm: {
      padding: '4px 10px',
      fontSize: '0.8125rem',
      minWidth: '28px'
    },
    md: {
      padding: '8px 16px',
      fontSize: '1rem',
      minWidth: '40px'
    },
    lg: {
      padding: '12px 22px',
      fontSize: '1.375rem',
      minWidth: '56px'
    }
  };
  const t = tones[tone] || tones.neutral;
  return /*#__PURE__*/React.createElement("kbd", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-mono)',
      fontWeight: 700,
      color: t.fg,
      background: t.bg,
      border: `1px solid ${t.bd}`,
      borderBottomWidth: '3px',
      borderRadius: 'var(--radius-md)',
      ...sizes[size],
      ...style
    }
  }, rest), children);
}

/** KeyCombo — lays out keycaps joined by a "+". */
function KeyCombo({
  keys = [],
  size = 'md',
  style = {},
  ...rest
}) {
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '12px',
      ...style
    }
  }, rest), keys.map((k, i) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: i
  }, i > 0 ? /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--text-muted)',
      fontFamily: 'var(--font-mono)',
      fontSize: '1.1em'
    }
  }, "+") : null, /*#__PURE__*/React.createElement(KeyCap, {
    tone: k.tone,
    size: size
  }, k.label))));
}
Object.assign(__ds_scope, { KeyCap, KeyCombo });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/KeyCap.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Card — base surface container. The brand's cards are flat dark panels with a
 * hairline border (no heavy rounding). Set glow/accent for emphasis.
 */
function Card({
  accent = 'none',
  glow = false,
  interactive = false,
  padding = 'var(--space-6)',
  style = {},
  children,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const accents = {
    none: {},
    green: {
      borderColor: 'var(--border-green)'
    },
    azure: {
      borderColor: 'var(--border-azure)'
    }
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      background: 'var(--surface-card)',
      border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--radius-lg)',
      padding,
      transition: 'transform var(--dur-base) var(--ease-out), border-color var(--dur-base) var(--ease-out), box-shadow var(--dur-base) var(--ease-out)',
      boxShadow: glow ? 'var(--glow-green-md)' : 'var(--shadow-md)',
      ...accents[accent],
      ...(interactive && hover ? {
        transform: 'translateY(-3px)',
        borderColor: 'var(--border-green)',
        boxShadow: 'var(--glow-green-md)'
      } : null),
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/Card.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/FeatureCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * FeatureCard — icon + title + description tile used in the marketing feature
 * grid. Icon is supplied as a ReactNode (e.g. a Lucide <i data-lucide>).
 */
function FeatureCard({
  icon = null,
  title,
  children,
  accent = 'green',
  align = 'left',
  style = {},
  ...rest
}) {
  const color = accent === 'azure' ? 'var(--azure-circuit)' : 'var(--necro-green)';
  return /*#__PURE__*/React.createElement(__ds_scope.Card, _extends({
    interactive: true,
    accent: "none",
    padding: "var(--space-6)",
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-4)',
      alignItems: align === 'center' ? 'center' : 'flex-start',
      textAlign: align,
      ...style
    }
  }, rest), icon ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: '52px',
      height: '52px',
      borderRadius: 'var(--radius-md)',
      color,
      background: accent === 'azure' ? 'rgba(0,212,255,0.07)' : 'rgba(0,255,140,0.07)',
      border: `1px solid ${accent === 'azure' ? 'var(--border-azure)' : 'var(--border-green)'}`
    }
  }, icon) : null, /*#__PURE__*/React.createElement("h3", {
    style: {
      margin: 0,
      fontFamily: 'var(--font-display)',
      fontWeight: 'var(--fw-bold)',
      fontSize: 'var(--fs-h5)',
      color: 'var(--text-primary)',
      lineHeight: 'var(--lh-snug)'
    }
  }, title), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      fontFamily: 'var(--font-body)',
      fontSize: 'var(--fs-small)',
      lineHeight: 'var(--lh-relaxed)',
      color: 'var(--text-secondary)'
    }
  }, children));
}
Object.assign(__ds_scope, { FeatureCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/FeatureCard.jsx", error: String((e && e.message) || e) }); }

// components/surfaces/TerminalWindow.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * TerminalWindow — the signature surface. macOS-style chrome (traffic lights),
 * optional title, and a near-black body for monospace content. Use `glow` for
 * the hero "reanimation" treatment.
 */
function TerminalWindow({
  title = '',
  glow = false,
  statusLeft = '',
  statusRight = '',
  bodyStyle = {},
  style = {},
  children,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      background: 'var(--surface-terminal)',
      border: '1px solid var(--border-green)',
      borderRadius: 'var(--radius-lg)',
      overflow: 'hidden',
      boxShadow: glow ? 'var(--glow-green-lg), var(--shadow-lg)' : 'var(--shadow-lg)',
      fontFamily: 'var(--font-mono)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
      padding: '10px 14px',
      background: 'var(--surface-terminal-chrome)',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: '7px'
    }
  }, /*#__PURE__*/React.createElement("i", {
    style: {
      width: 12,
      height: 12,
      borderRadius: '50%',
      background: '#ff5f57'
    }
  }), /*#__PURE__*/React.createElement("i", {
    style: {
      width: 12,
      height: 12,
      borderRadius: '50%',
      background: '#febc2e'
    }
  }), /*#__PURE__*/React.createElement("i", {
    style: {
      width: 12,
      height: 12,
      borderRadius: '50%',
      background: '#28c840'
    }
  })), title ? /*#__PURE__*/React.createElement("span", {
    style: {
      marginLeft: '8px',
      fontSize: 'var(--fs-caption)',
      color: 'var(--text-muted)',
      letterSpacing: 'var(--ls-wide)'
    }
  }, title) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 'var(--space-5)',
      fontSize: 'var(--fs-small)',
      lineHeight: 'var(--lh-relaxed)',
      color: 'var(--text-terminal)',
      minHeight: '120px',
      ...bodyStyle
    }
  }, children), statusLeft || statusRight ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      padding: '6px 14px',
      background: 'rgba(0,255,140,0.06)',
      borderTop: '1px solid var(--border-green)',
      fontSize: 'var(--fs-caption)',
      color: 'var(--necro-green)'
    }
  }, /*#__PURE__*/React.createElement("span", null, statusLeft), /*#__PURE__*/React.createElement("span", null, statusRight)) : null);
}
Object.assign(__ds_scope, { TerminalWindow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/surfaces/TerminalWindow.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/FeatureGrid.jsx
try { (() => {
// FeatureGrid — the four-up capability grid below the hero.
function FeatureGrid() {
  const {
    FeatureCard
  } = window.DesignSystem_7d9b63;
  const items = [{
    icon: 'folder-check',
    accent: 'green',
    title: 'Automatic Session Checkpointing',
    body: 'Walks every tmux pane on a timer and records each agent + resumable session id — in the background, off the status bar.'
  }, {
    icon: 'brain-circuit',
    accent: 'azure',
    title: 'AI Agent Continuity',
    body: 'Preserves and resumes live Claude Code & Codex loops across crashes and machine restarts. One adapter file per agent.'
  }, {
    icon: 'database',
    accent: 'green',
    title: 'Process Serialization',
    body: 'Auto-saves tmux windows, panes, and directory states to a JSONL snapshot. Idempotent restore fills gaps, never duplicates.'
  }, {
    icon: 'timer-reset',
    accent: 'azure',
    title: 'Boot-Time Reanimation',
    body: 'Pairs with tmux-resurrect + continuum to bring your whole layout — and every agent — back automatically after a reboot.'
  }];
  return /*#__PURE__*/React.createElement("section", {
    style: {
      maxWidth: 'var(--container-wide)',
      margin: '0 auto',
      padding: '24px 40px 72px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(4, 1fr)',
      gap: '20px'
    }
  }, items.map(it => /*#__PURE__*/React.createElement(FeatureCard, {
    key: it.title,
    accent: it.accent,
    title: it.title,
    icon: /*#__PURE__*/React.createElement("i", {
      "data-lucide": it.icon,
      style: {
        width: 26,
        height: 26
      }
    })
  }, it.body))));
}
Object.assign(window, {
  FeatureGrid
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/FeatureGrid.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Footer.jsx
try { (() => {
// Footer — supported agents table + links.
function Footer() {
  const {
    Badge
  } = window.DesignSystem_7d9b63;
  const agents = [{
    name: 'Claude Code',
    store: '~/.claude/projects/<cwd>/<uuid>.jsonl',
    resume: 'claude --resume <uuid>'
  }, {
    name: 'Codex',
    store: '~/.codex/sessions/<date>/rollout-*-<uuid>.jsonl',
    resume: 'codex resume <uuid>'
  }];
  return /*#__PURE__*/React.createElement("footer", {
    style: {
      borderTop: '1px solid var(--border-subtle)',
      background: 'var(--bg-sunken)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--container-max)',
      margin: '0 auto',
      padding: '56px 40px 40px'
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'var(--fs-h4)',
      color: 'var(--text-primary)',
      margin: '0 0 6px'
    }
  }, "Supported agents"), /*#__PURE__*/React.createElement("p", {
    style: {
      color: 'var(--text-muted)',
      margin: '0 0 22px',
      fontSize: '14px'
    }
  }, "Want another? It's one adapter file."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '180px 1fr 1fr',
      gap: '0',
      fontFamily: 'var(--font-mono)',
      fontSize: '13px',
      border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--radius-md)',
      overflow: 'hidden'
    }
  }, ['Agent', 'Transcript store', 'Resume'].map(h => /*#__PURE__*/React.createElement("div", {
    key: h,
    style: {
      padding: '12px 16px',
      background: 'var(--surface-raised)',
      color: 'var(--text-muted)',
      textTransform: 'uppercase',
      letterSpacing: '0.1em',
      fontSize: '11px',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, h)), agents.map(a => /*#__PURE__*/React.createElement(React.Fragment, {
    key: a.name
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 16px',
      color: 'var(--necro-green)',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, a.name), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 16px',
      color: 'var(--text-secondary)',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, a.store), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 16px',
      color: 'var(--azure-circuit)',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, a.resume)))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginTop: '40px',
      paddingTop: '24px',
      borderTop: '1px solid var(--border-subtle)',
      flexWrap: 'wrap',
      gap: '16px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-mark.png",
    alt: "",
    style: {
      height: '32px'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: '13px',
      color: 'var(--text-muted)'
    }
  }, "MIT \xB7 github.com/RonenMars/tmux-ai-necromancer")), /*#__PURE__*/React.createElement(Badge, {
    tone: "alive",
    dot: true,
    pulse: true
  }, "autosave running"))));
}
Object.assign(window, {
  Footer
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Footer.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Hero.jsx
try { (() => {
// Hero — wordmark, tagline, CTAs, and the signature split-pane terminal that
// flows a dead session into a reanimated one.
function Hero({
  onRestore,
  restoring
}) {
  const {
    Button,
    Badge,
    TerminalWindow
  } = window.DesignSystem_7d9b63;
  return /*#__PURE__*/React.createElement("section", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1.05fr',
      gap: '56px',
      alignItems: 'center',
      padding: '72px 40px 56px',
      maxWidth: 'var(--container-wide)',
      margin: '0 auto'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Badge, {
    tone: "data",
    dot: true,
    style: {
      marginBottom: '24px'
    }
  }, "TPM-compatible \xB7 multi-agent"), /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: 0,
      fontFamily: 'var(--font-display)',
      fontWeight: 900,
      fontSize: 'clamp(40px, 5vw, 72px)',
      lineHeight: 1.02,
      letterSpacing: '-0.02em',
      color: 'var(--necro-green)'
    }
  }, "tmux-", /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--azure-circuit)'
    }
  }, "ai"), "-necromancer"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '20px 0 0',
      maxWidth: '460px',
      fontSize: '19px',
      lineHeight: 1.55,
      color: 'var(--text-secondary)'
    }
  }, "Resurrecting dead coding agents. Never lose your agent's train of thought \u2014 restore your entire terminal exactly where you left off."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '16px',
      marginTop: '36px',
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "lg",
    glow: true,
    iconLeft: "\u203A",
    onClick: onRestore
  }, restoring ? 'Reanimating…' : 'Restore Session'), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "lg"
  }, "Read the Docs")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: '28px',
      fontFamily: 'var(--font-mono)',
      fontSize: '13px',
      color: 'var(--text-muted)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--necro-green)'
    }
  }, "$"), " set -g @plugin 'RonenMars/tmux-ai-necromancer'")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '0'
    }
  }, /*#__PURE__*/React.createElement(TerminalWindow, {
    title: "necromancer \u2014 session 0",
    glow: true,
    statusLeft: "[necromancer] reanimating",
    statusRight: "2 panes \xB7 ~/dev",
    style: {
      flex: 1
    },
    bodyStyle: {
      minHeight: '300px',
      padding: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateRows: '1fr 1fr',
      height: '300px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1.2fr',
      borderBottom: '1px solid var(--border-green)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px',
      borderRight: '1px solid var(--border-green)',
      color: 'var(--text-muted)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--necro-green)'
    }
  }, "\u203A"), " ", /*#__PURE__*/React.createElement("span", {
    style: {
      background: 'var(--necro-green)',
      color: 'var(--surface-terminal)'
    }
  }, "\xA0")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'rgba(0,255,140,0.04)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 700,
      letterSpacing: '0.18em',
      color: 'var(--necro-green)',
      textShadow: 'var(--text-glow-green)',
      animation: restoring ? 'heroBlink 0.9s steps(2) infinite' : 'none'
    }
  }, "RESTORING"))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1.2fr'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px',
      borderRight: '1px solid var(--border-green)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--necro-green)'
    }
  }, "\u203A")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px',
      fontSize: '12px',
      color: 'var(--azure-circuit)',
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("div", null, "\u2192 claude --resume a1b2c3"), /*#__PURE__*/React.createElement("div", null, "\u2192 codex resume 9f8e7d"), /*#__PURE__*/React.createElement("div", {
    style: {
      color: 'var(--text-muted)'
    }
  }, "\u2192 12 panes / 4 sessions"))))), /*#__PURE__*/React.createElement("div", {
    style: {
      width: '64px',
      height: '2px',
      background: 'linear-gradient(90deg, var(--azure-circuit), transparent)',
      flex: 'none'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: '120px',
      flex: 'none'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      border: '1px solid var(--border-azure)',
      borderRadius: '8px',
      background: 'var(--surface-terminal)',
      padding: '12px',
      boxShadow: 'var(--glow-azure-sm)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '5px',
      marginBottom: '12px'
    }
  }, /*#__PURE__*/React.createElement("i", {
    style: {
      width: 7,
      height: 7,
      borderRadius: '50%',
      background: '#ff5f57'
    }
  }), /*#__PURE__*/React.createElement("i", {
    style: {
      width: 7,
      height: 7,
      borderRadius: '50%',
      background: '#febc2e'
    }
  }), /*#__PURE__*/React.createElement("i", {
    style: {
      width: 7,
      height: 7,
      borderRadius: '50%',
      background: '#28c840'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      color: 'var(--necro-green)',
      fontSize: '22px'
    }
  }, "\u203A_")), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: '11px',
      color: 'var(--text-muted)',
      marginTop: '8px',
      textAlign: 'center'
    }
  }, "Claude Code V2."))), /*#__PURE__*/React.createElement("style", null, `@keyframes heroBlink{0%,100%{opacity:1}50%{opacity:0.25}}`));
}
Object.assign(window, {
  Hero
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Hero.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/InstallShowcase.jsx
try { (() => {
// InstallShowcase — tabbed install instructions (code block) beside a live
// snapshot/session list with restore + delete actions.
function InstallShowcase() {
  const {
    Card,
    Badge,
    Button
  } = window.DesignSystem_7d9b63;
  const [tab, setTab] = React.useState('TPM');
  const [sessions, setSessions] = React.useState([{
    id: 'a1b2c3',
    name: 'tb-mobile',
    agent: 'claude',
    cwd: '~/dev/threadbase',
    state: 'alive'
  }, {
    id: '9f8e7d',
    name: 'web-platform',
    agent: 'codex',
    cwd: '~/dev/web',
    state: 'data'
  }, {
    id: 'c4d5e6',
    name: 'necromancer',
    agent: 'claude',
    cwd: '~/dev/necro',
    state: 'dormant'
  }]);
  const code = {
    TPM: `# ~/.tmux.conf
set -g @plugin 'RonenMars/tmux-ai-necromancer'

# then press prefix + I to install
# autosave starts immediately`,
    Manual: `git clone https://github.com/RonenMars/\\
  tmux-ai-necromancer \\
  ~/.tmux/plugins/tmux-ai-necromancer

run-shell ~/.tmux/plugins/\\
  tmux-ai-necromancer/tmux-ai-necromancer.tmux`,
    Config: `set -g @necromancer_interval      '5'
set -g @necromancer_max_snapshots '20'
set -g @necromancer_agents 'claude codex'
set -g @necromancer_restore_key   'R'`
  };
  return /*#__PURE__*/React.createElement("section", {
    style: {
      maxWidth: 'var(--container-max)',
      margin: '0 auto',
      padding: '24px 40px 80px',
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: '28px',
      alignItems: 'start'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'var(--fs-h3)',
      color: 'var(--text-primary)',
      margin: '0 0 18px'
    }
  }, "Install in one line"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '8px',
      marginBottom: '14px'
    }
  }, ['TPM', 'Manual', 'Config'].map(t => /*#__PURE__*/React.createElement("button", {
    key: t,
    onClick: () => setTab(t),
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: '13px',
      cursor: 'pointer',
      padding: '7px 14px',
      borderRadius: 'var(--radius-sm)',
      border: '1px solid ' + (tab === t ? 'var(--border-green)' : 'var(--border-default)'),
      background: tab === t ? 'rgba(0,255,140,0.08)' : 'transparent',
      color: tab === t ? 'var(--necro-green)' : 'var(--text-muted)'
    }
  }, t))), /*#__PURE__*/React.createElement("pre", {
    style: {
      margin: 0,
      background: 'var(--surface-terminal)',
      border: '1px solid var(--border-green)',
      borderRadius: 'var(--radius-lg)',
      padding: '20px',
      fontFamily: 'var(--font-mono)',
      fontSize: '13px',
      lineHeight: 1.7,
      color: 'var(--text-terminal)',
      overflow: 'auto',
      boxShadow: 'var(--shadow-md)'
    }
  }, code[tab])), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'var(--fs-h3)',
      color: 'var(--text-primary)',
      margin: '0 0 18px'
    }
  }, "Snapshot"), /*#__PURE__*/React.createElement(Card, {
    padding: "var(--space-4)",
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '10px'
    }
  }, sessions.map(s => /*#__PURE__*/React.createElement("div", {
    key: s.id,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '14px',
      padding: '12px 14px',
      background: 'var(--surface-inset)',
      border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--radius-md)'
    }
  }, /*#__PURE__*/React.createElement(Badge, {
    tone: s.state,
    dot: true,
    pulse: s.state === 'alive',
    style: {
      flex: 'none'
    }
  }, s.agent), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: '14px',
      color: 'var(--text-primary)'
    }
  }, s.name), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: '12px',
      color: 'var(--text-muted)',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, s.cwd, " \xB7 ", s.id)), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "sm",
    onClick: () => setSessions(x => x.map(y => y.id === s.id ? {
      ...y,
      state: 'alive'
    } : y)),
    style: {
      flex: 'none'
    }
  }, "Restore"), /*#__PURE__*/React.createElement(Button, {
    variant: "danger",
    size: "sm",
    onClick: () => setSessions(x => x.filter(y => y.id !== s.id)),
    style: {
      flex: 'none'
    }
  }, "Delete"))), sessions.length === 0 ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '24px',
      textAlign: 'center',
      color: 'var(--text-muted)',
      fontFamily: 'var(--font-mono)',
      fontSize: '13px'
    }
  }, "No snapshots \u2014 the void is empty.") : null)));
}
Object.assign(window, {
  InstallShowcase
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/InstallShowcase.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Keybindings.jsx
try { (() => {
// Keybindings — documents the prefix bindings with keycaps.
function Keybindings() {
  const {
    KeyCombo,
    Card
  } = window.DesignSystem_7d9b63;
  const rows = [{
    combo: [{
      label: 'Prefix'
    }, {
      label: 'a',
      tone: 'green'
    }, {
      label: 'i',
      tone: 'green'
    }],
    name: 'Restore',
    desc: 'Reanimate the latest snapshot (popup)'
  }, {
    combo: [{
      label: 'Prefix'
    }, {
      label: 'I',
      tone: 'azure'
    }],
    name: 'Install',
    desc: 'Install the plugin via TPM'
  }];
  return /*#__PURE__*/React.createElement("section", {
    style: {
      maxWidth: 'var(--container-max)',
      margin: '0 auto',
      padding: '32px 40px 72px'
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      fontSize: 'var(--fs-h3)',
      color: 'var(--text-primary)',
      margin: '0 0 8px'
    }
  }, "Keybindings"), /*#__PURE__*/React.createElement("p", {
    style: {
      color: 'var(--text-muted)',
      margin: '0 0 28px',
      fontFamily: 'var(--font-mono)',
      fontSize: '14px'
    }
  }, "Set in ", /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--azure-circuit)'
    }
  }, "~/.tmux.conf"), " before TPM loads."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(2, 1fr)',
      gap: '18px'
    }
  }, rows.map(r => /*#__PURE__*/React.createElement(Card, {
    key: r.name,
    interactive: true,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '18px'
    }
  }, /*#__PURE__*/React.createElement(KeyCombo, {
    keys: r.combo,
    size: "md"
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 700,
      color: 'var(--text-primary)',
      fontSize: '16px'
    }
  }, r.name), /*#__PURE__*/React.createElement("div", {
    style: {
      color: 'var(--text-secondary)',
      fontSize: '13px',
      marginTop: '4px'
    }
  }, r.desc))))));
}
Object.assign(window, {
  Keybindings
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Keybindings.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Nav.jsx
try { (() => {
// Nav — top marketing bar. Logo + links + auth actions.
function Nav({
  active = 'Home',
  onNav
}) {
  const {
    Button
  } = window.DesignSystem_7d9b63;
  const links = ['Home', 'Features', 'Resources', 'Terminal'];
  return /*#__PURE__*/React.createElement("header", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 50,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '16px 40px',
      background: 'rgba(10,10,20,0.72)',
      backdropFilter: 'blur(12px)',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, /*#__PURE__*/React.createElement("a", {
    href: "#",
    onClick: e => {
      e.preventDefault();
      onNav && onNav('Home');
    },
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px',
      textDecoration: 'none'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-mark.png",
    alt: "",
    style: {
      height: '38px',
      filter: 'drop-shadow(0 0 8px rgba(0,255,140,0.35))'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-display)',
      fontWeight: 800,
      fontSize: '15px',
      lineHeight: 1.05,
      color: 'var(--necro-green)'
    }
  }, "tmux-", /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--azure-circuit)'
    }
  }, "ai"), "-", /*#__PURE__*/React.createElement("br", null), "necromancer")), /*#__PURE__*/React.createElement("nav", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '32px'
    }
  }, links.map(l => /*#__PURE__*/React.createElement("a", {
    key: l,
    href: "#",
    onClick: e => {
      e.preventDefault();
      onNav && onNav(l);
    },
    style: {
      fontFamily: 'var(--font-body)',
      fontWeight: 600,
      fontSize: '14px',
      textDecoration: 'none',
      paddingBottom: '4px',
      color: active === l ? 'var(--necro-green)' : 'var(--text-secondary)',
      borderBottom: active === l ? '2px solid var(--necro-green)' : '2px solid transparent'
    }
  }, l))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '14px'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "sm",
    style: {
      border: 'none'
    }
  }, "Log In"), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "sm"
  }, "Sign Up")));
}
Object.assign(window, {
  Nav
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Nav.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.KeyCap = __ds_scope.KeyCap;

__ds_ns.KeyCombo = __ds_scope.KeyCombo;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.FeatureCard = __ds_scope.FeatureCard;

__ds_ns.TerminalWindow = __ds_scope.TerminalWindow;

})();
