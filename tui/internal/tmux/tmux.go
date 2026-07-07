// Package tmux collects pane state from a running tmux server and
// mutates panes via send-keys.
package tmux

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
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
}

// ListPanes shells out to `tmux list-panes -a` and parses the result.
// Returns an empty slice (not nil, not error) when no tmux server is running.
func ListPanes() ([]Pane, error) {
	const sep = "\x1f" // ASCII unit separator — won't appear in tmux fields
	format := strings.Join([]string{
		"#{pane_id}",
		"#{session_name}",
		"#{window_index}",
		"#{window_name}",
		"#{pane_current_path}",
		"#{pane_current_command}",
	}, sep)

	cmd := exec.Command("tmux", "list-panes", "-a", "-F", format)
	out, err := cmd.Output()
	if err != nil {
		if isNoServer(err) {
			return []Pane{}, nil
		}
		return nil, fmt.Errorf("tmux list-panes: %w", err)
	}

	var panes []Pane
	for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, sep)
		if len(fields) != 6 {
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
		})
	}
	return panes, nil
}

// CapturePane returns the last `lines` lines of the pane's visible content
// plus its history (top), via `tmux capture-pane -p -t <pane> -S -<lines>`.
// Use a positive number; 0 returns just the visible buffer.
func CapturePane(paneID string, lines int) (string, error) {
	args := []string{"capture-pane", "-p", "-t", paneID}
	if lines > 0 {
		args = append(args, "-S", fmt.Sprintf("-%d", lines))
	}
	out, err := exec.Command("tmux", args...).Output()
	if err != nil {
		if isNoServer(err) {
			return "", fmt.Errorf("tmux capture-pane: no server")
		}
		return "", fmt.Errorf("tmux capture-pane %s: %w", paneID, err)
	}
	return string(out), nil
}

// SendKeys sends one or more key/literal arguments to the target pane.
// Each variadic arg is a separate `tmux send-keys` token — pass "Enter"
// for the Enter key, "/exit" for the literal string, etc.
func SendKeys(paneID string, keys ...string) error {
	args := append([]string{"send-keys", "-t", paneID}, keys...)
	cmd := exec.Command("tmux", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("tmux send-keys %s: %w (%s)", paneID, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// PaneCurrentCommand returns the foreground command of a single pane,
// e.g. "claude", "zsh", "node". Useful for polling after /exit.
func PaneCurrentCommand(paneID string) (string, error) {
	out, err := exec.Command(
		"tmux", "display-message", "-p", "-t", paneID, "#{pane_current_command}",
	).Output()
	if err != nil {
		if isNoServer(err) {
			return "", fmt.Errorf("tmux display-message: no server")
		}
		return "", fmt.Errorf("tmux display-message %s: %w", paneID, err)
	}
	return strings.TrimSpace(string(out)), nil
}
