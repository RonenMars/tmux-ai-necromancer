// Package debuglog writes opt-in structured diagnostic events for the TUI.
package debuglog

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type event struct {
	Time   string            `json:"time"`
	Phase  string            `json:"phase"`
	Action string            `json:"action"`
	Fields map[string]string `json:"fields,omitempty"`
}

// Enabled uses the same controls as the shell scripts. An explicit environment
// value wins over the tmux option so one TUI invocation can be traced safely.
func Enabled() bool {
	if value, ok := os.LookupEnv("NECROMANCER_DEBUG"); ok {
		return enabledValue(value)
	}
	out, err := exec.Command("tmux", "show-option", "-gqv", "@necromancer_debug").Output()
	return err == nil && enabledValue(string(out))
}

func enabledValue(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "on", "true", "yes":
		return true
	default:
		return false
	}
}

func logDir() string {
	if dir := os.Getenv("NECROMANCER_LOG_DIR"); dir != "" {
		return dir
	}
	if out, err := exec.Command("tmux", "show-option", "-gqv", "@necromancer_log_dir").Output(); err == nil {
		if dir := strings.TrimSpace(string(out)); dir != "" {
			if dir == "~" || strings.HasPrefix(dir, "~/") {
				if home, homeErr := os.UserHomeDir(); homeErr == nil {
					return filepath.Join(home, strings.TrimPrefix(dir, "~/"))
				}
			}
			return dir
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".tmux-ai-necromancer-logs")
}

// Event appends one JSONL record without changing the TUI's stdout or stderr.
func Event(phase, action string, fields map[string]string) {
	if !Enabled() {
		return
	}
	dir := logDir()
	if dir == "" || os.MkdirAll(dir, 0o755) != nil {
		return
	}
	f, err := os.OpenFile(filepath.Join(dir, "tui.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_ = json.NewEncoder(f).Encode(event{
		Time: time.Now().UTC().Format(time.RFC3339Nano), Phase: phase, Action: action, Fields: fields,
	})
}
