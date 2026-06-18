package snapshot

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// LatestCodexSessionID returns the id from the most recently modified rollout
// file whose session_meta cwd matches cwd.
//
// Pass a non-zero since to restrict to files modified at or after that time.
// Callers should pass the moment just before sending /quit so that stale
// rollouts from an earlier run in the same directory are excluded — the
// rollout for the session that just exited will always be newer.
//
// Codex stores rollouts under ~/.codex/sessions/YYYY/MM/DD.
func LatestCodexSessionID(home, cwd string, since time.Time) (string, error) {
	root := filepath.Join(home, ".codex", "sessions")
	type entry struct {
		path string
		mod  int64
	}
	var entries []entry
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		name := d.Name()
		if !strings.HasPrefix(name, "rollout-") || !strings.HasSuffix(name, ".jsonl") {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		// Apply time filter at walk time to minimise the candidate set when
		// since is set (the common case from runExitCmd).
		if !since.IsZero() && info.ModTime().Before(since) {
			return nil
		}
		entries = append(entries, entry{path: path, mod: info.ModTime().UnixNano()})
		return nil
	})
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}

	// Sort newest-first, then linearly scan for a CWD match. The cap is applied
	// after sorting so a matching rollout is never skipped in favour of a large
	// number of unrelated recent files.
	sort.Slice(entries, func(i, j int) bool { return entries[i].mod > entries[j].mod })
	const maxChecked = 2000
	for i, e := range entries {
		if i >= maxChecked {
			break
		}
		id, ok := codexMetaForCWD(e.path, cwd)
		if ok {
			return id, nil
		}
	}
	return "", nil
}

// normPath resolves symlinks so that paths like /var and /private/var on macOS
// compare equal.
func normPath(p string) string {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r
	}
	return p
}

// codexMetaForCWD reads the first line of a rollout file and checks whether
// its session_meta cwd matches. Codex always writes session_meta as line 1.
func codexMetaForCWD(path, cwd string) (string, bool) {
	f, err := os.Open(path)
	if err != nil {
		return "", false
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	if !sc.Scan() {
		return "", false
	}
	var obj struct {
		Payload struct {
			ID  string `json:"id"`
			CWD string `json:"cwd"`
		} `json:"payload"`
		ID  string `json:"id"`
		CWD string `json:"cwd"`
	}
	if err := json.Unmarshal(sc.Bytes(), &obj); err != nil {
		return "", false
	}
	id, gotCWD := obj.Payload.ID, obj.Payload.CWD
	if gotCWD == "" {
		id, gotCWD = obj.ID, obj.CWD
	}
	// Normalize both paths before comparing so that symlink spellings
	// (e.g. /var vs /private/var on macOS) match correctly.
	return id, id != "" && normPath(gotCWD) == normPath(cwd)
}
