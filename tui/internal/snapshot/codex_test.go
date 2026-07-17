package snapshot

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLatestCodexSessionIDMatchesCWDNewestFirst(t *testing.T) {
	home := t.TempDir()
	cwd := filepath.Join(home, "workspace")
	if err := os.MkdirAll(filepath.Join(home, ".codex", "sessions", "2026", "06", "18"), 0o755); err != nil {
		t.Fatal(err)
	}

	oldID := "11111111-1111-1111-1111-111111111111"
	newID := "22222222-2222-2222-2222-222222222222"
	writeRollout := func(name, id string, mod time.Time) {
		path := filepath.Join(home, ".codex", "sessions", "2026", "06", "18", name)
		line := `{"type":"session_meta","payload":{"id":"` + id + `","cwd":"` + cwd + `"}}` + "\n"
		if err := os.WriteFile(path, []byte(line), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, mod, mod); err != nil {
			t.Fatal(err)
		}
	}
	writeRollout("rollout-old-"+oldID+".jsonl", oldID, time.Unix(10, 0))
	writeRollout("rollout-new-"+newID+".jsonl", newID, time.Unix(20, 0))

	got, err := LatestCodexSessionID(home, cwd, time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if got != newID {
		t.Fatalf("want %q, got %q", newID, got)
	}
}

func TestLatestCodexSessionIDSinceFiltersStaleSession(t *testing.T) {
	home := t.TempDir()
	cwd := filepath.Join(home, "workspace")
	dir := filepath.Join(home, ".codex", "sessions", "2026", "06", "18")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}

	staleID := "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	freshID := "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	staleTime := time.Unix(100, 0)
	freshTime := time.Unix(200, 0)

	writeRollout := func(name, id string, mod time.Time) {
		p := filepath.Join(dir, name)
		line := `{"type":"session_meta","payload":{"id":"` + id + `","cwd":"` + cwd + `"}}` + "\n"
		if err := os.WriteFile(p, []byte(line), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(p, mod, mod); err != nil {
			t.Fatal(err)
		}
	}
	writeRollout("rollout-stale-"+staleID+".jsonl", staleID, staleTime)
	writeRollout("rollout-fresh-"+freshID+".jsonl", freshID, freshTime)

	// since = 150 → stale file (mod 100) excluded; fresh file (mod 200) matches.
	got, err := LatestCodexSessionID(home, cwd, time.Unix(150, 0))
	if err != nil {
		t.Fatal(err)
	}
	if got != freshID {
		t.Fatalf("want %q (fresh), got %q", freshID, got)
	}

	// since = zero → both visible; newest (fresh) wins.
	got2, err := LatestCodexSessionID(home, cwd, time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if got2 != freshID {
		t.Fatalf("want %q (fresh), got %q", freshID, got2)
	}
}

// Codex canonicalizes cwd to lowercase and macOS's filesystem is
// case-insensitive, so a pane in .../tb-PRs-follow has its rollout recorded as
// .../tb-prs-follow. EvalSymlinks resolves links but does NOT canonicalize
// case, so an exact string compare misses the session entirely.
// lib/agents/codex.sh case-folds for this reason; the TUI must match.
func TestLatestCodexSessionIDMatchesCWDCaseInsensitively(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".codex", "sessions", "2026", "07", "17")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}

	id := "abcdabcd-1111-2222-3333-444444444444"
	// Rollout records the lowercased cwd, as Codex writes it.
	line := `{"type":"session_meta","payload":{"id":"` + id + `","cwd":"` +
		filepath.Join(home, "work", "tb-prs-follow") + `"}}` + "\n"
	f := filepath.Join(dir, "rollout-2026-07-17T00-00-00-"+id+".jsonl")
	if err := os.WriteFile(f, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}

	// The pane's cwd carries the original mixed-case spelling.
	got, err := LatestCodexSessionID(home, filepath.Join(home, "work", "tb-PRs-follow"), time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if got != id {
		t.Errorf("LatestCodexSessionID with mixed-case cwd = %q, want %q", got, id)
	}
}
