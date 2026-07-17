package snapshot_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/snapshot"
)

// Round-trip: write a minimal JSONL, LoadFile it back, verify fields.
func TestLoadFile_RoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sample.jsonl")
	line := `{"pane_id":"%9","session":"2","window_index":1,"window_name":"omh","cwd":"/tmp","prev_cmd":"claude","uuid":"abc-123","captured_at":"2026-01-01T00:00:00Z","first_user":"hi","last_assistant":"hello","dest_session":"","dest_window_name":""}` + "\n"
	if err := os.WriteFile(path, []byte(line), 0644); err != nil {
		t.Fatal(err)
	}
	recs, err := snapshot.LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 1 {
		t.Fatalf("want 1 record, got %d", len(recs))
	}
	r := recs[0]
	if r.PaneID != "%9" || r.UUID != "abc-123" || r.WindowIndex != 1 {
		t.Fatalf("unexpected record: %+v", r)
	}
}

// LoadLatest must handle a missing directory gracefully (no error).
func TestLoadLatest_MissingDir(t *testing.T) {
	recs, path, err := snapshot.LoadLatest("/definitely/not/a/real/path/xyz")
	if err != nil {
		t.Fatalf("want nil error for missing dir, got %v", err)
	}
	if recs != nil || path != "" {
		t.Fatalf("want empty result, got recs=%v path=%q", recs, path)
	}
}

func TestLoadLatest_PrefersNewestFileOverall(t *testing.T) {
	dir := t.TempDir()
	oldEnriched := filepath.Join(dir, "2026-01-01T00-00-00Z.enriched.jsonl")
	newPlain := filepath.Join(dir, "2026-01-02T00-00-00Z.idle-only.jsonl")
	if err := os.WriteFile(oldEnriched, []byte(`{"pane_id":"%1"}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(newPlain, []byte(`{"pane_id":"%2"}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(oldEnriched, time.Unix(10, 0), time.Unix(10, 0)); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(newPlain, time.Unix(20, 0), time.Unix(20, 0)); err != nil {
		t.Fatal(err)
	}

	recs, path, err := snapshot.LoadLatest(dir)
	if err != nil {
		t.Fatal(err)
	}
	if path != newPlain {
		t.Fatalf("want newest plain path %q, got %q", newPlain, path)
	}
	if len(recs) != 1 || recs[0].PaneID != "%2" {
		t.Fatalf("unexpected records: %+v", recs)
	}
}

// ExtractResumeUUID covers the realistic shapes Claude prints on /exit.
func TestExtractResumeUUID(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "typical exit line",
			in:   "Bye! To resume this session run claude --resume 3fb28a80-62ac-4f76-8748-9d6944764f4b\n",
			want: "3fb28a80-62ac-4f76-8748-9d6944764f4b",
		},
		{
			name: "no uuid at all",
			in:   "see you later\n",
			want: "",
		},
		{
			name: "ignores uuid outside resume line",
			in:   "request id 11111111-1111-1111-1111-111111111111\n",
			want: "",
		},
		{
			name: "picks the LAST uuid in scrollback",
			in: "old session was 11111111-1111-1111-1111-111111111111\n" +
				"new session: claude --resume 22222222-2222-2222-2222-222222222222\n",
			want: "22222222-2222-2222-2222-222222222222",
		},
		{
			name: "rejects non-hex tokens",
			in:   "garbage gggggggg-gggg-gggg-gggg-gggggggggggg\n",
			want: "",
		},
		{
			name: "tolerates ANSI escape junk around the uuid",
			in:   "\x1b[1mclaude --resume\x1b[0m abcd1234-ef56-7890-1234-567890abcdef end",
			want: "abcd1234-ef56-7890-1234-567890abcdef",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := snapshot.ExtractResumeUUID(tc.in)
			if got != tc.want {
				t.Fatalf("want %q, got %q", tc.want, got)
			}
		})
	}
}

// AppendRecord must create parent dirs and serialize each call as one
// JSON Lines entry that LoadFile can read back.
func TestAppendRecord_RoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nested", "out.jsonl")
	r1 := snapshot.Record{PaneID: "%1", UUID: "u1", Session: "s", CWD: "/tmp"}
	r2 := snapshot.Record{PaneID: "%2", UUID: "u2", Session: "s", CWD: "/tmp"}
	if err := snapshot.AppendRecord(path, r1); err != nil {
		t.Fatal(err)
	}
	if err := snapshot.AppendRecord(path, r2); err != nil {
		t.Fatal(err)
	}
	recs, err := snapshot.LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 2 || recs[0].PaneID != "%1" || recs[1].UUID != "u2" {
		t.Fatalf("unexpected records: %+v", recs)
	}
}

// LoadLatest picks the most recently modified snapshot, which may be an
// autosave that is still being written — its trailing line is then a partial
// record. necro-restore.sh skips malformed records; the TUI must too, or one
// bad line blanks the whole viewer.
func TestLoadFileSkipsMalformedLines(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "snap.jsonl")

	good1 := `{"pane_id":"%1","session":"a","window_index":0,"cwd":"/tmp","agent":"claude","uuid":"u1"}`
	good2 := `{"pane_id":"%2","session":"b","window_index":1,"cwd":"/tmp","agent":"codex","uuid":"u2"}`
	partial := `{"pane_id":"%3","session":"c","cw` // truncated mid-write

	content := good1 + "\n" + partial + "\n" + good2 + "\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	recs, err := snapshot.LoadFile(path)
	if err != nil {
		t.Fatalf("LoadFile returned error for a snapshot with one bad line: %v", err)
	}
	if len(recs) != 2 {
		t.Fatalf("got %d records, want 2 (both good lines, bad line skipped)", len(recs))
	}
	if recs[0].PaneID != "%1" || recs[1].PaneID != "%2" {
		t.Errorf("got panes %q/%q, want %%1/%%2", recs[0].PaneID, recs[1].PaneID)
	}
}
