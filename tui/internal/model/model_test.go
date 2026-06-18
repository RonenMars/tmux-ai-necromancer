package model

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/tmux"
)

func TestRecordForPanePreservesCodexAgent(t *testing.T) {
	pane := tmux.Pane{
		PaneID:         "%4",
		SessionName:    "work",
		WindowIndex:    2,
		WindowName:     "repo",
		CWD:            "/tmp/repo",
		CurrentCommand: "codex",
	}

	rec := recordForPane(pane, "codex", "22222222-2222-2222-2222-222222222222")

	if rec.Agent != "codex" {
		t.Fatalf("want Agent codex, got %q", rec.Agent)
	}
	if rec.PrevCmd != "codex" {
		t.Fatalf("want PrevCmd codex, got %q", rec.PrevCmd)
	}
	if rec.UUIDSource != "latest-jsonl" {
		t.Fatalf("want UUIDSource latest-jsonl, got %q", rec.UUIDSource)
	}
}

func TestRecordForPaneClaudeUsesScrollbackSource(t *testing.T) {
	pane := tmux.Pane{
		PaneID:         "%2",
		SessionName:    "work",
		WindowIndex:    0,
		WindowName:     "main",
		CWD:            "/tmp/proj",
		CurrentCommand: "claude",
	}

	rec := recordForPane(pane, "claude", "11111111-1111-1111-1111-111111111111")

	if rec.UUIDSource != "scrollback" {
		t.Fatalf("want UUIDSource scrollback, got %q", rec.UUIDSource)
	}
}

func TestUUIDForAgentPrefersCodexMetadataOverScrollbackUUID(t *testing.T) {
	home := t.TempDir()
	cwd := filepath.Join(home, "workspace")
	dir := filepath.Join(home, ".codex", "sessions", "2026", "06", "18")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	want := "22222222-2222-2222-2222-222222222222"
	path := filepath.Join(dir, "rollout-new-"+want+".jsonl")
	line := `{"type":"session_meta","payload":{"id":"` + want + `","cwd":"` + cwd + `"}}` + "\n"
	if err := os.WriteFile(path, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, time.Unix(20, 0), time.Unix(20, 0)); err != nil {
		t.Fatal(err)
	}

	got, err := uuidForAgent("codex", "old 11111111-1111-1111-1111-111111111111", home, cwd, time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("want %q, got %q", want, got)
	}
}
