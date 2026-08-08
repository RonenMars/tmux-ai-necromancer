package tmux

import (
	"strings"
	"testing"
)

// fields is one pane's worth of list-panes output, in the order ListPanes asks
// for them.
var fields = []string{
	"%3", "work", "2", "editor", "/home/u/p", "claude",
	"6654,364x76,0,0,34", "0", "1", "1",
}

func assertOnePane(t *testing.T, out string, label string) {
	t.Helper()
	panes, dropped := parsePanes(out)
	if dropped != 0 {
		t.Fatalf("%s: dropped %d lines, want 0", label, dropped)
	}
	if len(panes) != 1 {
		t.Fatalf("%s: got %d panes, want 1", label, len(panes))
	}
	p := panes[0]
	if p.PaneID != "%3" || p.SessionName != "work" || p.WindowIndex != 2 ||
		p.CurrentCommand != "claude" || !p.PaneActive || !p.WindowActive || p.Zoomed {
		t.Fatalf("%s: parsed wrong: %+v", label, p)
	}
}

// tmux 3.7b emits the separator as a raw 0x1f byte.
func TestParsePanesRawSeparator(t *testing.T) {
	assertOnePane(t, strings.Join(fields, "\x1f")+"\n", "raw 0x1f")
}

// tmux 3.5/3.5a escape control bytes in format output, so the separator
// arrives as the four literal characters \037. Verified against a 3.5a built
// from source: `list-panes -F` returned zero raw 0x1f bytes and one literal
// per separator, which made every row fail the 10-field check and left the
// pane table empty with no error.
func TestParsePanesEscapedSeparator(t *testing.T) {
	assertOnePane(t, strings.Join(fields, `\037`)+"\n", "escaped \\037")
}

// A line that is malformed under both readings is counted, not silently
// dropped — an empty table must be distinguishable from a missing server.
func TestParsePanesCountsUnparseableLines(t *testing.T) {
	out := strings.Join(fields, "\x1f") + "\n" + "not-a-pane-record\n"
	panes, dropped := parsePanes(out)
	if len(panes) != 1 {
		t.Fatalf("got %d panes, want 1", len(panes))
	}
	if dropped != 1 {
		t.Fatalf("dropped=%d, want 1", dropped)
	}
}
