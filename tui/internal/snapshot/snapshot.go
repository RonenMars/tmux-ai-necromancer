// Package snapshot reads JSONL snapshot files produced by claude-snapshot.sh
// and matches their records back to live tmux panes by pane_id.
package snapshot

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Record matches one line in a snapshot .jsonl.
type Record struct {
	PaneID         string `json:"pane_id"`
	Session        string `json:"session"`
	WindowIndex    int    `json:"window_index"`
	WindowName     string `json:"window_name"`
	CWD            string `json:"cwd"`
	PrevCmd        string `json:"prev_cmd"`
	Agent          string `json:"agent"`
	UUID           string `json:"uuid"`
	CapturedAt     string `json:"captured_at"`
	FirstUser      string `json:"first_user"`
	LastAssistant  string `json:"last_assistant"`
	DestSession    string `json:"dest_session"`
	DestWindowName string `json:"dest_window_name"`
}

// LoadFile reads a single .jsonl file. Returns an empty slice for an empty
// or missing file (callers can choose whether that's an error).
func LoadFile(path string) ([]Record, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var recs []Record
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20) // 1 MiB per line; transcripts can be long
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var r Record
		if err := json.Unmarshal([]byte(line), &r); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		recs = append(recs, r)
	}
	return recs, sc.Err()
}

// LoadLatest finds the most recently modified *.jsonl in dir (skipping
// .enriched.jsonl unless it's the only thing) and returns its records.
// dir is typically ~/.claude/tmux-snapshots.
func LoadLatest(dir string) ([]Record, string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, "", nil
		}
		return nil, "", err
	}

	type cand struct {
		path string
		mod  int64
	}
	var enriched, plain []cand
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".jsonl") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		c := cand{filepath.Join(dir, e.Name()), info.ModTime().Unix()}
		if strings.HasSuffix(e.Name(), ".enriched.jsonl") {
			enriched = append(enriched, c)
		} else {
			plain = append(plain, c)
		}
	}

	// Prefer enriched when available — it has first_user/last_assistant.
	pick := enriched
	if len(pick) == 0 {
		pick = plain
	}
	if len(pick) == 0 {
		return nil, "", nil
	}
	sort.Slice(pick, func(i, j int) bool { return pick[i].mod > pick[j].mod })
	recs, err := LoadFile(pick[0].path)
	return recs, pick[0].path, err
}

// IndexByPaneID builds a fast lookup keyed by pane_id (e.g. "%9").
func IndexByPaneID(recs []Record) map[string]Record {
	out := make(map[string]Record, len(recs))
	for _, r := range recs {
		out[r.PaneID] = r
	}
	return out
}

// uuidRE matches Claude's exit-line UUIDs. Claude prints something like
//
//	claude --resume 3fb28a80-62ac-4f76-8748-9d6944764f4b
//
// after /exit; we extract that token. The pattern allows arbitrary
// surrounding text and prefers the last match in the scrollback so a
// fresh exit shadows older transcripts left on screen.
var uuidRE = regexp.MustCompile(`[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`)

// ExtractResumeUUID scans the given scrollback text for a Claude resume
// UUID. Returns "" if no candidate is found. Picks the last match — the
// most recently printed one — so old "to resume run claude --resume X"
// lines from earlier sessions don't shadow the new one.
func ExtractResumeUUID(scrollback string) string {
	matches := uuidRE.FindAllString(scrollback, -1)
	if len(matches) == 0 {
		return ""
	}
	return matches[len(matches)-1]
}

// AppendRecord appends one record to path as a single JSONL line.
// Creates the file (and parent dirs) if missing. Used by the TUI to
// build up a snapshot incrementally as each Claude is exited.
func AppendRecord(path string, r Record) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	return enc.Encode(r)
}

// NewSnapshotPath returns a fresh path for a new snapshot in the
// canonical directory, named by UTC timestamp. Does not create the file.
func NewSnapshotPath(dir string) string {
	ts := time.Now().UTC().Format("2006-01-02T15-04-05Z")
	return filepath.Join(dir, ts+".jsonl")
}
