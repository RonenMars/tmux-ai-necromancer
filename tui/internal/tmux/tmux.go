// Package tmux collects pane state from a running tmux server and
// mutates panes via send-keys.
package tmux

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/debuglog"
)

// isNoServer detects the well-known stderr fragment that tmux prints
// when no server is up.
func isNoServer(err error) bool {
	if ee, ok := err.(*exec.ExitError); ok {
		stderr := string(ee.Stderr)
		return strings.Contains(stderr, "no server running") ||
			(strings.Contains(stderr, "error connecting to ") &&
				strings.Contains(stderr, "No such file or directory"))
	}
	return false
}

// Pane is the snapshot-relevant projection of one tmux pane.
type Pane struct {
	PaneID         string // %N
	SessionName    string
	WindowIndex    int
	WindowName     string
	CWD            string
	CurrentCommand string
	WindowLayout   string // tmux layout string; saved (unzoomed) even while zoomed
	Zoomed         bool   // window_zoomed_flag
	PaneActive     bool   // pane_active — this pane is its window's active pane
	WindowActive   bool   // window_active — this window is its session's current one
}

// ListPanes shells out to `tmux list-panes -a` and parses the result.
// Returns an empty slice (not nil, not error) when no tmux server is running.
func ListPanes() ([]Pane, error) {
	debuglog.Event("tmux", "list_panes_start", nil)
	const sep = "\x1f" // ASCII unit separator — won't appear in tmux fields
	format := strings.Join([]string{
		"#{pane_id}",
		"#{session_name}",
		"#{window_index}",
		"#{window_name}",
		"#{pane_current_path}",
		"#{pane_current_command}",
		"#{window_layout}",
		"#{window_zoomed_flag}",
		"#{pane_active}",
		"#{window_active}",
	}, sep)

	cmd := exec.Command("tmux", "list-panes", "-a", "-F", format)
	out, err := cmd.Output()
	if err != nil {
		if isNoServer(err) {
			debuglog.Event("tmux", "list_panes_complete", map[string]string{"panes": "0", "server": "absent"})
			return []Pane{}, nil
		}
		debuglog.Event("tmux", "list_panes_error", map[string]string{"error": err.Error()})
		return nil, fmt.Errorf("tmux list-panes: %w", err)
	}

	panes, dropped := parsePanes(string(out))
	debuglog.Event("tmux", "list_panes_complete", map[string]string{
		"panes":   strconv.Itoa(len(panes)),
		"dropped": strconv.Itoa(dropped),
	})
	return panes, nil
}

// escapedSep is what tmux 3.5a emits in place of a raw sep byte: it escapes
// control bytes in format output, so the separator arrives as these four
// characters and a plain Split yields one field per line. Measured on
// binaries built from source: 3.5a emits zero raw 0x1f bytes; 3.6 and 3.7b
// emit the byte. Both are handled so the pane table is not silently empty on
// the older release.
const escapedSep = `\037`

// parsePanes turns `list-panes -F` output into panes, returning the number of
// lines that could not be parsed. Split out from ListPanes so the escaped-
// separator behaviour is testable without a live tmux server.
func parsePanes(out string) ([]Pane, int) {
	const sep = "\x1f"
	var panes []Pane
	dropped := 0
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, sep)
		if len(fields) != 10 {
			fields = strings.Split(strings.ReplaceAll(line, escapedSep, sep), sep)
		}
		if len(fields) != 10 {
			// Counted rather than dropped in silence: the symptom is an empty
			// table, identical to "no server running".
			dropped++
			continue
		}
		idx, _ := strconv.Atoi(fields[2])
		panes = append(panes, Pane{
			PaneID:         fields[0],
			SessionName:    fields[1],
			WindowIndex:    idx,
			WindowName:     fields[3],
			CWD:            fields[4],
			CurrentCommand: fields[5],
			WindowLayout:   fields[6],
			Zoomed:         fields[7] == "1",
			PaneActive:     fields[8] == "1",
			WindowActive:   fields[9] == "1",
		})
	}
	return panes, dropped
}

// CapturePane returns the last `lines` lines of the pane's visible content
// plus its history (top), via `tmux capture-pane -p -t <pane> -S -<lines>`.
// Use a positive number; 0 returns just the visible buffer.
func CapturePane(paneID string, lines int) (string, error) {
	debuglog.Event("tmux", "capture_pane_start", map[string]string{"pane": paneID, "lines": strconv.Itoa(lines)})
	args := []string{"capture-pane", "-p", "-t", paneID}
	if lines > 0 {
		args = append(args, "-S", fmt.Sprintf("-%d", lines))
	}
	out, err := exec.Command("tmux", args...).Output()
	if err != nil {
		if isNoServer(err) {
			debuglog.Event("tmux", "capture_pane_error", map[string]string{"pane": paneID, "error": "no_server"})
			return "", fmt.Errorf("tmux capture-pane: no server")
		}
		debuglog.Event("tmux", "capture_pane_error", map[string]string{"pane": paneID, "error": err.Error()})
		return "", fmt.Errorf("tmux capture-pane %s: %w", paneID, err)
	}
	debuglog.Event("tmux", "capture_pane_complete", map[string]string{"pane": paneID})
	return string(out), nil
}

// SendKeys sends one or more key/literal arguments to the target pane.
// Each variadic arg is a separate `tmux send-keys` token — pass "Enter"
// for the Enter key, "/exit" for the literal string, etc.
func SendKeys(paneID string, keys ...string) error {
	debuglog.Event("tmux", "send_keys_start", map[string]string{"pane": paneID, "key_count": strconv.Itoa(len(keys))})
	args := append([]string{"send-keys", "-t", paneID}, keys...)
	cmd := exec.Command("tmux", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		debuglog.Event("tmux", "send_keys_error", map[string]string{"pane": paneID, "error": err.Error()})
		return fmt.Errorf("tmux send-keys %s: %w (%s)", paneID, err, strings.TrimSpace(string(out)))
	}
	debuglog.Event("tmux", "send_keys_complete", map[string]string{"pane": paneID})
	return nil
}

// PaneCurrentCommand returns the foreground command of a single pane,
// e.g. "claude", "zsh", "node". Useful for polling after /exit.
func PaneCurrentCommand(paneID string) (string, error) {
	debuglog.Event("tmux", "pane_command_start", map[string]string{"pane": paneID})
	out, err := exec.Command(
		"tmux", "display-message", "-p", "-t", paneID, "#{pane_current_command}",
	).Output()
	if err != nil {
		if isNoServer(err) {
			debuglog.Event("tmux", "pane_command_error", map[string]string{"pane": paneID, "error": "no_server"})
			return "", fmt.Errorf("tmux display-message: no server")
		}
		debuglog.Event("tmux", "pane_command_error", map[string]string{"pane": paneID, "error": err.Error()})
		return "", fmt.Errorf("tmux display-message %s: %w", paneID, err)
	}
	debuglog.Event("tmux", "pane_command_complete", map[string]string{"pane": paneID})
	return strings.TrimSpace(string(out)), nil
}
