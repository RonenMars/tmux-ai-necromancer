package debuglog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEventWritesOnlyWhenDebugIsEnabled(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("NECROMANCER_LOG_DIR", dir)
	t.Setenv("NECROMANCER_DEBUG", "off")
	Event("load", "start", nil)
	if _, err := os.Stat(filepath.Join(dir, "tui.log")); !os.IsNotExist(err) {
		t.Fatalf("disabled logging created file: %v", err)
	}

	t.Setenv("NECROMANCER_DEBUG", "on")
	Event("load", "complete", map[string]string{"panes": "2"})
	contents, err := os.ReadFile(filepath.Join(dir, "tui.log"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(contents), `"phase":"load"`) || !strings.Contains(string(contents), `"action":"complete"`) {
		t.Fatalf("missing structured event: %s", contents)
	}
}
