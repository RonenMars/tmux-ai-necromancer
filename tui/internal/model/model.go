// Package model is the Bubble Tea application state.
package model

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/table"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/snapshot"
	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/tmux"
)

// snapshotDir resolves the snapshot directory, honoring the
// NECROMANCER_SNAPSHOT_DIR env var and falling back to the legacy default
// (~/.claude/tmux-snapshots) so existing snapshots stay readable.
func snapshotDir() string {
	if d := os.Getenv("NECROMANCER_SNAPSHOT_DIR"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".claude", "tmux-snapshots")
}

// viewMode is the top-level UI mode dispatched in Update/View.
type viewMode int

const (
	modeTable   viewMode = iota // pane list (Phase 4 default)
	modeReview                  // scrollback preview + [e/s/b] prompt
	modeExiting                 // /exit sent, polling for shell to return
)

// Model holds all UI state.
type Model struct {
	table        table.Model
	panes        []tmux.Pane
	bySnapshotID map[string]snapshot.Record
	snapshotPath string // path of the latest loaded snapshot (read)
	status       string
	err          error
	width        int
	height       int

	// Phase 5 fields.
	mode            viewMode
	selectedPane    *tmux.Pane        // pane under review / exiting
	scrollback      string            // last capture-pane output for review screen
	captured        map[string]string // pane_id -> uuid, this session's exits
	sessionFile     string            // append target; lazy-created on first capture
	dryRun          bool              // if true, log instead of mutating tmux
	exitElapsed     int               // seconds elapsed in modeExiting
	exitDeadlineHit bool              // 20s timed out
}

// Options configures the TUI on startup.
type Options struct {
	DryRun bool // log mutations instead of executing them
}

// New builds the initial model. It does not load data — that happens on Init.
func New(opts Options) Model {
	cols := []table.Column{
		{Title: "Pane", Width: 5},
		{Title: "Session", Width: 12},
		{Title: "Win", Width: 4},
		{Title: "Window name", Width: 24},
		{Title: "Cmd", Width: 8},
		{Title: "UUID", Width: 10},
		{Title: "CWD", Width: 40},
	}
	t := table.New(
		table.WithColumns(cols),
		table.WithFocused(true),
		table.WithHeight(20),
	)
	st := table.DefaultStyles()
	st.Header = st.Header.
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color("240")).
		BorderBottom(true).
		Bold(true)
	st.Selected = st.Selected.
		Foreground(lipgloss.Color("229")).
		Background(lipgloss.Color("57")).
		Bold(false)
	t.SetStyles(st)

	return Model{
		table:    t,
		captured: map[string]string{},
		dryRun:   opts.DryRun,
	}
}

type dataMsg struct {
	panes        []tmux.Pane
	records      []snapshot.Record
	snapshotPath string
	err          error
}

// scrollbackMsg arrives when we've captured the scrollback for the review
// screen on a single pane.
type scrollbackMsg struct {
	paneID string
	text   string
	err    error
}

// tickMsg fires once per second while we're polling for the shell to
// return after sending /exit.
type tickMsg struct{}

// exitDoneMsg fires when polling finishes (success, timeout, or fatal error).
type exitDoneMsg struct {
	paneID   string
	agent    string
	uuid     string
	timedOut bool
	err      error
}

// Init loads tmux state and the latest snapshot on startup.
func (m Model) Init() tea.Cmd {
	return loadCmd()
}

func loadCmd() tea.Cmd {
	return func() tea.Msg {
		panes, err := tmux.ListPanes()
		if err != nil {
			return dataMsg{err: err}
		}
		dir := snapshotDir()
		recs, path, err := snapshot.LoadLatest(dir)
		return dataMsg{
			panes:        panes,
			records:      recs,
			snapshotPath: path,
			err:          err,
		}
	}
}

// captureScrollbackCmd fetches the last N lines of a pane's scrollback so
// the user can preview what's there before pressing /exit.
func captureScrollbackCmd(paneID string) tea.Cmd {
	return func() tea.Msg {
		text, err := tmux.CapturePane(paneID, 50)
		return scrollbackMsg{paneID: paneID, text: text, err: err}
	}
}

// tickCmd schedules a tickMsg one second from now. Used to poll
// pane_current_command while we wait for /exit to complete.
func tickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} })
}

// runExitCmd sends /exit + Enter to the pane, polls until the shell
// returns or 20 seconds elapse, captures the scrollback, and extracts
// the UUID. Runs in a tea.Cmd goroutine — never block the UI thread.
type agentSpec struct {
	name     string
	exitKeys string
}

// agentForCommand mirrors the bash adapters' matching rules (lib/agents/*.sh).
// Keep the two in sync: tmux reports the native binary's truncated basename
// (e.g. "codex-aarch64-a" for codex-aarch64-apple-darwin), not the "codex"
// wrapper, so an exact-match-only check silently fails to see real Codex panes.
func agentForCommand(s string) (agentSpec, bool) {
	cmd := strings.TrimSpace(s)
	switch {
	case cmd == "claude":
		return agentSpec{name: "claude", exitKeys: "/exit"}, true
	case cmd == "codex" || strings.HasPrefix(cmd, "codex-"):
		return agentSpec{name: "codex", exitKeys: "/quit"}, true
	default:
		return agentSpec{}, false
	}
}

func runExitCmd(pane tmux.Pane, agent agentSpec, dryRun bool) tea.Cmd {
	return func() tea.Msg {
		if dryRun {
			return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, uuid: "dry-run-no-uuid"}
		}
		// Record the time before sending the exit command so LatestCodexSessionID
		// can filter to rollouts written at or after this moment, avoiding
		// a stale session in the same directory being picked up by mistake.
		exitStart := time.Now()
		// 1. Send the agent's exit command + Enter.
		if err := tmux.SendKeys(pane.PaneID, agent.exitKeys, "Enter"); err != nil {
			return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, err: err}
		}
		// 2. Poll up to 20s for the pane's foreground to leave the agent.
		const maxWait = 20 * time.Second
		const pollEvery = 500 * time.Millisecond
		deadline := time.Now().Add(maxWait)
		for time.Now().Before(deadline) {
			time.Sleep(pollEvery)
			cmd, err := tmux.PaneCurrentCommand(pane.PaneID)
			if err != nil {
				return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, err: err}
			}
			if strings.TrimSpace(cmd) != agent.name {
				goto captured
			}
		}
		return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, timedOut: true}
	captured:
		// 3. Capture scrollback and pull the UUID out.
		text, err := tmux.CapturePane(pane.PaneID, 100)
		if err != nil {
			return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, err: err}
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, err: err}
		}
		uuid, err := uuidForAgent(agent.name, text, home, pane.CWD, exitStart)
		if err != nil {
			return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, err: err}
		}
		return exitDoneMsg{paneID: pane.PaneID, agent: agent.name, uuid: uuid}
	}
}

func uuidForAgent(agent, scrollback, home, cwd string, since time.Time) (string, error) {
	if agent == "codex" {
		return snapshot.LatestCodexSessionID(home, cwd, since)
	}
	return snapshot.ExtractResumeUUID(scrollback), nil
}

// Update handles input and incoming messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Window resize applies in every mode.
	if ws, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = ws.Width
		m.height = ws.Height
		h := ws.Height - 6
		if h < 5 {
			h = 5
		}
		m.table.SetHeight(h)
		return m, nil
	}

	// Universal quit on Ctrl-C from any mode.
	if k, ok := msg.(tea.KeyMsg); ok && k.String() == "ctrl+c" {
		return m, tea.Quit
	}

	// dataMsg always reloads the table (and might arrive while in another
	// mode after an exit-and-reload chain).
	if d, ok := msg.(dataMsg); ok {
		return m.handleDataMsg(d), nil
	}

	switch m.mode {
	case modeReview:
		return m.updateReview(msg)
	case modeExiting:
		return m.updateExiting(msg)
	default:
		return m.updateTable(msg)
	}
}

func (m Model) handleDataMsg(d dataMsg) Model {
	if d.err != nil {
		m.err = d.err
		m.status = fmt.Sprintf("error: %v", d.err)
		return m
	}
	m.panes = d.panes
	m.bySnapshotID = snapshot.IndexByPaneID(d.records)
	m.snapshotPath = d.snapshotPath
	m.rebuildRows()
	switch {
	case len(m.panes) == 0:
		m.status = "no tmux server / no panes"
	case d.snapshotPath == "":
		m.status = fmt.Sprintf("%d panes loaded · no snapshots found", len(m.panes))
	default:
		m.status = fmt.Sprintf("%d panes · snapshot: %s",
			len(m.panes), filepath.Base(d.snapshotPath))
	}
	return m
}

func (m Model) updateTable(msg tea.Msg) (tea.Model, tea.Cmd) {
	if k, ok := msg.(tea.KeyMsg); ok {
		switch k.String() {
		case "q":
			return m, tea.Quit
		case "r":
			m.status = "reloading…"
			return m, loadCmd()
		case "e", "enter":
			return m.beginReview()
		}
	}
	var cmd tea.Cmd
	m.table, cmd = m.table.Update(msg)
	return m, cmd
}

// beginReview switches to the review screen for the currently selected agent
// pane. Otherwise sets a status hint and stays put.
func (m Model) beginReview() (tea.Model, tea.Cmd) {
	idx := m.table.Cursor()
	pane := m.paneAtRow(idx)
	if pane == nil {
		m.status = "no pane selected"
		return m, nil
	}
	if pane.PaneID == os.Getenv("TMUX_PANE") {
		m.status = "refusing to exit the TUI's own pane"
		return m, nil
	}
	if _, ok := agentForCommand(pane.CurrentCommand); !ok {
		m.status = fmt.Sprintf("pane %s is running '%s', not a supported agent", pane.PaneID, pane.CurrentCommand)
		return m, nil
	}
	m.selectedPane = pane
	m.scrollback = "loading scrollback…"
	m.mode = modeReview
	return m, captureScrollbackCmd(pane.PaneID)
}

// paneAtRow maps a sorted-table row index back to the corresponding Pane.
// Returns nil if out of range. Mirrors the sort order used in rebuildRows.
func (m Model) paneAtRow(idx int) *tmux.Pane {
	sorted := sortedPanes(m.panes)
	if idx < 0 || idx >= len(sorted) {
		return nil
	}
	return &sorted[idx]
}

func sortedPanes(panes []tmux.Pane) []tmux.Pane {
	out := make([]tmux.Pane, len(panes))
	copy(out, panes)
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].SessionName != out[j].SessionName {
			return out[i].SessionName < out[j].SessionName
		}
		if out[i].WindowIndex != out[j].WindowIndex {
			return out[i].WindowIndex < out[j].WindowIndex
		}
		return out[i].PaneID < out[j].PaneID
	})
	return out
}

func (m Model) updateReview(msg tea.Msg) (tea.Model, tea.Cmd) {
	if s, ok := msg.(scrollbackMsg); ok {
		// Only accept if it's for the pane we're reviewing — stale captures
		// from a previous review can be ignored.
		if m.selectedPane != nil && s.paneID == m.selectedPane.PaneID {
			if s.err != nil {
				m.scrollback = fmt.Sprintf("(error capturing scrollback: %v)", s.err)
			} else {
				m.scrollback = s.text
			}
		}
		return m, nil
	}
	if k, ok := msg.(tea.KeyMsg); ok {
		switch k.String() {
		case "b", "esc":
			m.mode = modeTable
			m.selectedPane = nil
			m.scrollback = ""
			return m, nil
		case "s":
			m.mode = modeTable
			m.status = fmt.Sprintf("skipped %s", m.selectedPane.PaneID)
			m.selectedPane = nil
			return m, nil
		case "e":
			return m.beginExit()
		}
	}
	return m, nil
}

// beginExit sends /exit to the reviewed pane and switches to modeExiting.
func (m Model) beginExit() (tea.Model, tea.Cmd) {
	if m.selectedPane == nil {
		m.mode = modeTable
		return m, nil
	}
	agent, ok := agentForCommand(m.selectedPane.CurrentCommand)
	if !ok {
		m.mode = modeTable
		m.status = fmt.Sprintf("pane %s is no longer a supported agent", m.selectedPane.PaneID)
		return m, nil
	}
	m.mode = modeExiting
	m.exitElapsed = 0
	m.exitDeadlineHit = false
	m.status = fmt.Sprintf("sending %s to %s%s",
		agent.exitKeys, m.selectedPane.PaneID, dryRunSuffix(m.dryRun))
	return m, tea.Batch(
		runExitCmd(*m.selectedPane, agent, m.dryRun),
		tickCmd(),
	)
}

func dryRunSuffix(dry bool) string {
	if dry {
		return " (dry-run)"
	}
	return ""
}

func (m Model) updateExiting(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		// Keep ticking until the exit command resolves.
		m.exitElapsed++
		return m, tickCmd()
	case exitDoneMsg:
		return m.finishExit(msg), loadCmd() // reload table to reflect new pane state
	}
	return m, nil
}

func (m Model) finishExit(msg exitDoneMsg) Model {
	m.selectedPane = nil
	m.mode = modeTable

	if msg.err != nil {
		m.status = fmt.Sprintf("exit failed for %s: %v", msg.paneID, msg.err)
		return m
	}
	if msg.timedOut {
		m.exitDeadlineHit = true
		m.status = fmt.Sprintf("timed out waiting for shell on %s", msg.paneID)
		return m
	}
	if msg.uuid == "" {
		if msg.agent == "codex" {
			m.status = fmt.Sprintf("exited %s but no Codex rollout found matching pane CWD", msg.paneID)
		} else {
			m.status = fmt.Sprintf("exited %s but no UUID found in scrollback", msg.paneID)
		}
		return m
	}
	// Success.
	m.captured[msg.paneID] = msg.uuid
	if err := m.persistCapture(msg.paneID, msg.agent, msg.uuid); err != nil {
		m.status = fmt.Sprintf("captured %s=%s but write failed: %v", msg.paneID, shortUUID(msg.uuid), err)
		return m
	}
	m.status = fmt.Sprintf("captured %s → %s%s",
		msg.paneID, shortUUID(msg.uuid), dryRunSuffix(m.dryRun))
	return m
}

// persistCapture appends a snapshot record to the current session's
// snapshot file. Lazy-creates the path on first call.
func (m *Model) persistCapture(paneID, agent, uuid string) error {
	if m.dryRun {
		return nil
	}
	if m.sessionFile == "" {
		dir := snapshotDir()
		m.sessionFile = snapshot.NewSnapshotPath(dir)
	}
	// Find the pane to fill its full context.
	var pane *tmux.Pane
	for i := range m.panes {
		if m.panes[i].PaneID == paneID {
			pane = &m.panes[i]
			break
		}
	}
	if pane == nil {
		return fmt.Errorf("pane %s no longer in state", paneID)
	}
	rec := recordForPane(*pane, agent, uuid)
	return snapshot.AppendRecord(m.sessionFile, rec)
}

func uuidSource(agent string) string {
	if agent == "codex" {
		return "latest-jsonl"
	}
	return "scrollback"
}

func recordForPane(pane tmux.Pane, agent, uuid string) snapshot.Record {
	return snapshot.Record{
		PaneID:      pane.PaneID,
		Session:     pane.SessionName,
		WindowIndex: pane.WindowIndex,
		WindowName:  pane.WindowName,
		CWD:         pane.CWD,
		PrevCmd:     agent,
		Agent:       agent,
		UUID:        uuid,
		UUIDSource:  uuidSource(agent),
		CapturedAt:  time.Now().UTC().Format(time.RFC3339),
	}
}

func (m *Model) rebuildRows() {
	rows := make([]table.Row, 0, len(m.panes))

	// Stable order: session, window index, pane id.
	sorted := make([]tmux.Pane, len(m.panes))
	copy(sorted, m.panes)
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].SessionName != sorted[j].SessionName {
			return sorted[i].SessionName < sorted[j].SessionName
		}
		if sorted[i].WindowIndex != sorted[j].WindowIndex {
			return sorted[i].WindowIndex < sorted[j].WindowIndex
		}
		return sorted[i].PaneID < sorted[j].PaneID
	})

	for _, p := range sorted {
		uuid := ""
		if rec, ok := m.bySnapshotID[p.PaneID]; ok && rec.UUID != "" {
			uuid = shortUUID(rec.UUID)
		}
		rows = append(rows, table.Row{
			p.PaneID,
			truncate(p.SessionName, 12),
			fmt.Sprintf("%d", p.WindowIndex),
			truncate(p.WindowName, 24),
			truncate(p.CurrentCommand, 8),
			uuid,
			truncate(shortenHome(p.CWD), 40),
		})
	}
	m.table.SetRows(rows)
}

// View renders the screen.
func (m Model) View() string {
	switch m.mode {
	case modeReview:
		return m.viewReview()
	case modeExiting:
		return m.viewExiting()
	default:
		return m.viewTable()
	}
}

var (
	headerStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	dimStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	warnStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	codeBox     = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color("240")).
			Padding(0, 1)
)

func (m Model) viewTable() string {
	title := "necromancer-tui · pane viewer"
	if m.dryRun {
		title += " (dry-run)"
	}
	return lipgloss.JoinVertical(
		lipgloss.Left,
		headerStyle.Render(title),
		m.table.View(),
		dimStyle.Render(m.status),
		dimStyle.Render("↑/↓ move · e exit selected agent · r reload · q quit"),
	)
}

func (m Model) viewReview() string {
	p := m.selectedPane
	title := fmt.Sprintf("review · %s · %s:%d · %s",
		p.PaneID, p.SessionName, p.WindowIndex, p.WindowName)
	meta := fmt.Sprintf("cwd: %s   cmd: %s", shortenHome(p.CWD), p.CurrentCommand)

	body := m.scrollback
	if body == "" {
		body = "(scrollback empty)"
	}
	// Cap rendered scrollback so it always fits.
	body = lastNLines(body, 20)

	dry := ""
	if m.dryRun {
		dry = warnStyle.Render("  [dry-run: no /exit will actually be sent]")
	}
	return lipgloss.JoinVertical(
		lipgloss.Left,
		headerStyle.Render(title),
		dimStyle.Render(meta),
		codeBox.Render(body),
		dimStyle.Render("e exit & capture · s skip · b back"+dry),
	)
}

func (m Model) viewExiting() string {
	p := m.selectedPane
	title := fmt.Sprintf("exiting · %s · waiting %ds", p.PaneID, m.exitElapsed)
	return lipgloss.JoinVertical(
		lipgloss.Left,
		headerStyle.Render(title),
		dimStyle.Render(m.status),
		dimStyle.Render("(this can take up to 20s while the agent exits)"),
	)
}

// lastNLines returns the last n lines of s. Used to keep the review
// scrollback bounded to the visible area.
func lastNLines(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) <= n {
		return strings.Join(lines, "\n")
	}
	return strings.Join(lines[len(lines)-n:], "\n")
}

func truncate(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	if n <= 1 {
		return string(runes[:n])
	}
	return string(runes[:n-1]) + "…"
}

func shortUUID(uuid string) string {
	runes := []rune(uuid)
	if len(runes) <= 8 {
		return uuid
	}
	return string(runes[:8])
}

func shortenHome(p string) string {
	if home, err := os.UserHomeDir(); err == nil {
		if len(p) >= len(home) && p[:len(home)] == home {
			return "~" + p[len(home):]
		}
	}
	return p
}
