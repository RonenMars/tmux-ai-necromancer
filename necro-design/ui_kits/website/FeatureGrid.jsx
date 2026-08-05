// FeatureGrid — the four-up capability grid below the hero.
function FeatureGrid() {
  const { FeatureCard } = window.DesignSystem_7d9b63;
  const items = [
    { icon: 'folder-check', accent: 'green', title: 'Automatic Session Checkpointing', body: 'Walks every tmux pane on a timer and records each agent + resumable session id — in the background, off the status bar.' },
    { icon: 'brain-circuit', accent: 'azure', title: 'AI Agent Continuity', body: 'Preserves and resumes live Claude Code & Codex loops across crashes and machine restarts. One adapter file per agent.' },
    { icon: 'database', accent: 'green', title: 'Process Serialization', body: 'Auto-saves tmux windows, panes, and directory states to a JSONL snapshot. Idempotent restore fills gaps, never duplicates.' },
    { icon: 'timer-reset', accent: 'azure', title: 'Boot-Time Reanimation', body: 'Pairs with tmux-resurrect + continuum to bring your whole layout — and every agent — back automatically after a reboot.' },
  ];
  return (
    <section style={{ maxWidth: 'var(--container-wide)', margin: '0 auto', padding: '24px 40px 72px' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }}>
        {items.map((it) => (
          <FeatureCard key={it.title} accent={it.accent} title={it.title}
            icon={<i data-lucide={it.icon} style={{ width: 26, height: 26 }}></i>}>
            {it.body}
          </FeatureCard>
        ))}
      </div>
    </section>
  );
}
Object.assign(window, { FeatureGrid });
