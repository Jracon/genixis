package ide

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The fixtures of this directory are fish's own output (see GENERATE.md and
// generate.fish). The tests here freeze the pure parts of the ide window
// builder against them: a window keeps its socket and its start script for
// its whole life, so these values are a consumer contract, not an
// implementation detail.

// FishEscape must return byte for byte what fish's `string escape --`
// returns, over the whole golden table: the raw, the quoted, and the
// backslash forms, the named and the caret control escapes, and the control
// characters that pass through raw.
func TestFishEscapeMatchesFishGoldens(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("testdata", "escape-cases.json"))
	if err != nil {
		t.Fatal(err)
	}
	var cases []string
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	golden, err := os.ReadFile(filepath.Join("testdata", "escape-golden.txt"))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(string(golden), "\n"), "\n")
	if len(lines) != len(cases) {
		t.Fatalf("%d cases but %d golden lines", len(cases), len(lines))
	}
	for i, input := range cases {
		if got := FishEscape(input); got != lines[i] {
			t.Errorf("FishEscape(%q) = %q, fish gave %q", input, got, lines[i])
		}
	}
}

// The claude start script is what the agent pane sources: its bytes are the
// frozen form of the fish implementation of __ide_claude.
func TestClaudeStartScriptMatchesFishGolden(t *testing.T) {
	golden, err := os.ReadFile(filepath.Join("testdata", "claude-start.txt"))
	if err != nil {
		t.Fatal(err)
	}
	sock := "/var/folders/5w/l20byfk56ql0pzm2klvb9xjr0000gn/T//nvim-ide-96324-80.sock"
	args := []string{
		"--continue",
		"--settings", `{"autoMemoryDirectory":"/home/dev/proj/.claude/memory","env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic","PROJECT_PLAN":"zai"},"apiKeyHelper":"cat '/run/agenix/zai_token'"}`,
		"--permission-mode", "acceptEdits",
		"--", `do the work on issue 74 (it's "phase 3")`,
	}
	got := ClaudeStartScript(ClaudeScript(sock), args)
	if !bytes.Equal(got, golden) {
		t.Errorf("start script bytes differ\n got: %q\nwant: %q", got, golden)
	}
	if source := ClaudePaneSource(ClaudeScript(sock)); source != " source "+ClaudeScript(sock) {
		t.Errorf("pane source = %q", source)
	}
}

// The socket of an editor pane: the TMPDIR value as it stands (a trailing
// slash gives the double slash of the frozen form), the % of the pane id
// gone, and /tmp only when TMPDIR is unset.
func TestSocketPath(t *testing.T) {
	t.Setenv("TMPDIR", "/var/folders/5w/T/")
	if got := SocketPath("96324-%81"); got != "/var/folders/5w/T//nvim-ide-96324-81.sock" {
		t.Errorf("SocketPath = %q", got)
	}
	t.Setenv("TMPDIR", "")
	if got := SocketPath("42-%0"); got != "/nvim-ide-42-0.sock" {
		t.Errorf("SocketPath with empty TMPDIR = %q", got)
	}
	if err := os.Unsetenv("TMPDIR"); err != nil {
		t.Fatal(err)
	}
	if got := TmpDir(); got != "/tmp" {
		t.Errorf("TmpDir without TMPDIR = %q", got)
	}
	if got := SessionFile("/tmp/nvim-ide-1-2.sock"); got != "/tmp/nvim-ide-1-2.vim" {
		t.Errorf("SessionFile = %q", got)
	}
	if got := ClaudeScript("/tmp/nvim-ide-1-2.sock"); got != "/tmp/nvim-ide-1-2-claude.fish" {
		t.Errorf("ClaudeScript = %q", got)
	}
	// a path that is not a socket name passes through unchanged
	if got := SessionFile("/tmp/other.txt"); got != "/tmp/other.txt" {
		t.Errorf("SessionFile of a non-socket = %q", got)
	}
}

// The layout proportions of an ide window, with every clamp: yazi 15% of the
// width at 24 through 40 columns, claude 30% with at least 40, the shell 20%
// of the height with at least 6 rows.
func TestLayoutSizes(t *testing.T) {
	for _, table := range []struct {
		width, height       int
		files, agent, shell int
	}{
		{200, 50, 30, 60, 10},
		{300, 80, 40, 90, 16},
		{400, 100, 40, 120, 20},
		{1000, 200, 40, 300, 40},
		{100, 24, 24, 40, 6},
		{160, 10, 24, 48, 6},
		{80, 30, 24, 40, 6},
		{24, 6, 24, 40, 6},
	} {
		files, agent, shell := LayoutSizes(table.width, table.height)
		if files != table.files || agent != table.agent || shell != table.shell {
			t.Errorf("LayoutSizes(%d, %d) = (%d, %d, %d), want (%d, %d, %d)",
				table.width, table.height, files, agent, shell, table.files, table.agent, table.shell)
		}
	}
}

// The seven @ide_* option writes of a finished window, as tmux argument
// vectors in emission order: the tmux hooks and the yazi openers read these
// options on any build.
func TestOptionWrites(t *testing.T) {
	got := OptionWrites("%81", "%82", "/Users/dev/proj", "%80", "zai", "%83", "/tmp/nvim-ide-96324-81.sock")
	want := [][]string{
		{"set-option", "-w", "-t", "%81", "@ide_agent", "%82"},
		{"set-option", "-w", "-t", "%81", "@ide_dir", "/Users/dev/proj"},
		{"set-option", "-w", "-t", "%81", "@ide_editor", "%81"},
		{"set-option", "-w", "-t", "%81", "@ide_files", "%80"},
		{"set-option", "-w", "-t", "%81", "@ide_plan", "zai"},
		{"set-option", "-w", "-t", "%81", "@ide_shell", "%83"},
		{"set-option", "-w", "-t", "%81", "@ide_sock", "/tmp/nvim-ide-96324-81.sock"},
	}
	if len(got) != len(want) {
		t.Fatalf("%d writes, want %d", len(got), len(want))
	}
	for i := range want {
		if strings.Join(got[i], " ") != strings.Join(want[i], " ") {
			t.Errorf("write %d = %v, want %v", i, got[i], want[i])
		}
	}
}

// The plan name comes out of the settings JSON the way jq read it: absent
// when the key is missing or the bytes are not JSON.
func TestExtractPlan(t *testing.T) {
	for _, table := range []struct {
		json string
		want string
	}{
		{`{"env":{"PROJECT_PLAN":"zai"}}`, "zai"},
		{`{"env":{"PROJECT_PLAN":""}}`, ""},
		{`{"env":{}}`, ""},
		{`{"autoMemoryDirectory":"/x"}`, ""},
		{`not json`, ""},
	} {
		if got := ExtractPlan(table.json); got != table.want {
			t.Errorf("ExtractPlan(%q) = %q, want %q", table.json, got, table.want)
		}
	}
}
