package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/model"
)

func main() {
	var dryRun bool
	flag.BoolVar(&dryRun, "dry-run", false, "log mutations instead of executing /exit and send-keys against tmux")
	flag.Parse()

	p := tea.NewProgram(
		model.New(model.Options{DryRun: dryRun}),
		tea.WithAltScreen(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
