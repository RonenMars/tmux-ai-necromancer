package tmux_test

import (
	"testing"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/tmux"
)

// Smoke test: tmux.ListPanes must not error on a machine with or without
// a running tmux server. (Empty slice is valid when no server is running.)
func TestListPanes_NoError(t *testing.T) {
	if _, err := tmux.ListPanes(); err != nil {
		t.Fatalf("ListPanes: %v", err)
	}
}
