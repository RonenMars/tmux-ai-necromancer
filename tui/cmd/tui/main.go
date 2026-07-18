package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/debuglog"
	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/model"
)

func main() {
	var dryRun bool
	flag.BoolVar(&dryRun, "dry-run", false, "log mutations instead of executing /exit and send-keys against tmux")
	flag.Parse()
	debuglog.Event("run", "start", map[string]string{"dry_run": fmt.Sprint(dryRun)})

	p := tea.NewProgram(
		model.New(model.Options{DryRun: dryRun}),
		tea.WithAltScreen(),
	)
	if _, err := p.Run(); err != nil {
		debuglog.Event("run", "error", map[string]string{"error": err.Error()})
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	debuglog.Event("run", "complete", nil)
}
