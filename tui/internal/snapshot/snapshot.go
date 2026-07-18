// Package snapshot reads JSONL snapshot files produced by necro-snapshot.sh
// and matches their records back to live tmux panes by pane_id.
package snapshot

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/RonenMars/tmux-ai-necromancer/tui/internal/debuglog"
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
	UUIDSource     string `json:"uuid_source,omitempty"`
	CapturedAt     string `json:"captured_at"`
	FirstUser      string `json:"first_user"`
	LastAssistant  string `json:"last_assistant"`
	DestSession    string `json:"dest_session"`
	DestWindowName string `json:"dest_window_name"`
}

// LoadFile reads a single .jsonl file. Returns an empty slice for an empty
// or missing file (callers can choose whether that's an error).
func LoadFile(path string) ([]Record, error) {
	debuglog.Event("snapshot", "load_file_start", map[string]string{"path": path})
	f, err := os.Open(path)
	if err != nil {
		debuglog.Event("snapshot", "load_file_error", map[string]string{"path": path, "error": err.Error()})
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
			// Skip the bad line rather than failing the whole snapshot:
			// necro-restore.sh tolerates malformed records, and LoadLatest
			// may well pick an autosave that is still being written, whose
			// trailing line is a partial record. Aborting here would blank
			// the viewer over one unparseable line out of hundreds.
			continue
		}
		recs = append(recs, r)
	}
	err = sc.Err()
	if err != nil {
		debuglog.Event("snapshot", "load_file_error", map[string]string{"path": path, "error": err.Error()})
		return recs, err
	}
	debuglog.Event("snapshot", "load_file_complete", map[string]string{"path": path, "records": strconv.Itoa(len(recs))})
	return recs, nil
}

// LoadLatest finds the most recently modified *.jsonl in dir and returns its records.
// dir is typically ~/.claude/tmux-snapshots.
func LoadLatest(dir string) ([]Record, string, error) {
	debuglog.Event("snapshot", "load_latest_start", map[string]string{"directory": dir})
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			debuglog.Event("snapshot", "load_latest_complete", map[string]string{"records": "0", "reason": "directory_missing"})
			return nil, "", nil
		}
		debuglog.Event("snapshot", "load_latest_error", map[string]string{"error": err.Error()})
		return nil, "", err
	}

	type cand struct {
		path string
		mod  int64
	}
	var candidates []cand
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".jsonl") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		c := cand{filepath.Join(dir, e.Name()), info.ModTime().Unix()}
		candidates = append(candidates, c)
	}

	if len(candidates) == 0 {
		debuglog.Event("snapshot", "load_latest_complete", map[string]string{"records": "0", "reason": "no_snapshots"})
		return nil, "", nil
	}
	sort.Slice(candidates, func(i, j int) bool { return candidates[i].mod > candidates[j].mod })
	recs, err := LoadFile(candidates[0].path)
	if err != nil {
		debuglog.Event("snapshot", "load_latest_error", map[string]string{"path": candidates[0].path, "error": err.Error()})
	} else {
		debuglog.Event("snapshot", "load_latest_complete", map[string]string{"path": candidates[0].path, "records": strconv.Itoa(len(recs))})
	}
	return recs, candidates[0].path, err
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
	var last string
	for _, line := range strings.Split(scrollback, "\n") {
		if !strings.Contains(strings.ToLower(line), "resume") {
			continue
		}
		matches := uuidRE.FindAllString(line, -1)
		if len(matches) > 0 {
			last = matches[len(matches)-1]
		}
	}
	return last
}

// AppendRecord appends one record to path as a single JSONL line.
// Creates the file (and parent dirs) if missing. Used by the TUI to
// build up a snapshot incrementally as each agent is exited.
func AppendRecord(path string, r Record) error {
	debuglog.Event("snapshot", "append_start", map[string]string{"path": path, "pane": r.PaneID, "agent": r.Agent})
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		debuglog.Event("snapshot", "append_error", map[string]string{"path": path, "error": err.Error()})
		return err
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		debuglog.Event("snapshot", "append_error", map[string]string{"path": path, "error": err.Error()})
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	if err := enc.Encode(r); err != nil {
		debuglog.Event("snapshot", "append_error", map[string]string{"path": path, "error": err.Error()})
		return err
	}
	debuglog.Event("snapshot", "append_complete", map[string]string{"path": path, "pane": r.PaneID, "agent": r.Agent})
	return nil
}

// NewSnapshotPath returns a fresh path for a new snapshot in the
// canonical directory, named by UTC timestamp. Does not create the file.
func NewSnapshotPath(dir string) string {
	ts := time.Now().UTC().Format("2006-01-02T15-04-05Z")
	return filepath.Join(dir, ts+".jsonl")
}
