package main

import (
	"slices"
	"strings"
	"testing"
)

// The view window of a headless leg (issue #116): the pane command quotes
// the attach target for the default shell of tmux — the session id that
// `claude --bg` printed, else the session name (issue #208) — the tmux
// vectors add the window to the session of the project or make that
// session, and the option sweep of `project close` reads @leg_dir. The tmux
// calls themselves stay outside the tests; the scratch acceptance covers
// them.

func TestLegViewCommandQuotesTheTarget(t *testing.T) {
	got, ok := legViewCommand("/nix/store/claude-bin/claude", "7c5dcf5d")
	if !ok {
		t.Fatalf("the command of a session id was refused")
	}
	want := "/nix/store/claude-bin/claude attach '7c5dcf5d'"
	if got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
	got, ok = legViewCommand("/nix/store/claude-bin/claude", "genixis: ai/issue-116")
	if !ok {
		t.Fatalf("the command of a plain session name was refused")
	}
	want = "/nix/store/claude-bin/claude attach 'genixis: ai/issue-116'"
	if got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
	// a name with a double quote stays one literal word in every shell
	if _, ok := legViewCommand("/bin/claude", `demo "two": ai/x`); !ok {
		t.Errorf("a name with a double quote was refused")
	}
	// a single quote and a backslash have no form that fish, sh, and bash
	// read the same way, and an empty half is no command at all
	for _, tc := range [][2]string{
		{"/bin/claude", "it's: ai/x"},
		{"/bin/claude", `back\slash: ai/x`},
		{"", "genixis: ai/issue-116"},
		{"/bin/claude", ""},
	} {
		if got, ok := legViewCommand(tc[0], tc[1]); ok {
			t.Errorf("legViewCommand(%q, %q) = %q, want a refusal", tc[0], tc[1], got)
		}
	}
}

// The pane attaches by the session id whenever the spawn captured one, so
// no other listed session can take the attach (issue #208).
func TestLegViewTargetPicksTheSessionID(t *testing.T) {
	if got := legViewTarget("genixis: ai/issue-208", "7c5dcf5d"); got != "7c5dcf5d" {
		t.Errorf("target with an id = %q, want the id", got)
	}
	if got := legViewTarget("genixis: ai/issue-208", ""); got != "genixis: ai/issue-208" {
		t.Errorf("target without an id = %q, want the name", got)
	}
}

func TestLegViewNewWindowArgs(t *testing.T) {
	command := "/bin/claude attach '7c5dcf5d'"
	got := legViewNewWindowArgs("genixis", "ai/issue-116", "/home/dev/projects/genixis/ai-issue-116", command)
	want := []string{
		"new-window", "-d", "-P", "-F", "#{window_id}",
		"-t", "=genixis:", "-n", "ai/issue-116",
		"-c", "/home/dev/projects/genixis/ai-issue-116",
		command,
	}
	if !slices.Equal(got, want) {
		t.Errorf("new-window vector = %q, want %q", got, want)
	}
}

func TestLegViewNewSessionArgs(t *testing.T) {
	command := "/bin/claude attach 'b0a1c2d3'"
	got := legViewNewSessionArgs("demo", "feat/x", "/tmp/demo/feat-x", "120", "40", command)
	want := []string{
		"new-session", "-d", "-P", "-F", "#{window_id}",
		"-s", "demo", "-n", "feat/x", "-c", "/tmp/demo/feat-x",
		"-x", "120", "-y", "40",
		command,
	}
	if !slices.Equal(got, want) {
		t.Errorf("new-session vector = %q, want %q", got, want)
	}
}

// The parser reads the id out of the block that `claude --bg` prints, in
// every documented shape, and answers "" for an output that holds no id, so
// the caller falls back to the session name (issue #208). The block itself
// is the documented print of the agent-view page of the Claude Code docs.
func TestParseSessionID(t *testing.T) {
	documented := "backgrounded · 7c5dcf5d · flaky-test-fix\n" +
		"  claude agents             list sessions\n" +
		"  claude attach 7c5dcf5d    open in this terminal\n" +
		"  claude logs 7c5dcf5d      show recent output\n" +
		"  claude stop 7c5dcf5d      stop this session\n"
	for _, tc := range []struct {
		name string
		out  string
		want string
	}{
		{"the documented block", documented, "7c5dcf5d"},
		{"no name segment", "backgrounded · 0a1b2c3d\n", "0a1b2c3d"},
		{"a service line above the block", "Starting background service…\n" + documented, "7c5dcf5d"},
		{"output of both streams", "noise on stderr\n" + documented + "more noise\n", "7c5dcf5d"},
		{"only the attach hint", "  claude attach 9f8e7d6c    open in this terminal\n", "9f8e7d6c"},
		{"no id anywhere", "claude started, good luck\n", ""},
		{
			"an unquotable id is no id",
			"backgrounded · it's · demo: feat/x\n  claude attach it's    open in this terminal\n",
			"",
		},
		{"an empty id segment is no id", "backgrounded ·  · demo: feat/x\n", ""},
		{"a wrapped id is no id", "backgrounded · " + strings.Repeat("d", 101) + " · demo\n", ""},
	} {
		if got := parseSessionID(tc.out); got != tc.want {
			t.Errorf("%s: parseSessionID = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// The sweep of `project close` reads one "id value" line per window: an
// unset option leaves the value empty, a value with spaces stays one value,
// and only the exact worktree matches.
func TestWindowsWithOption(t *testing.T) {
	lines := []string{
		"@1 /home/dev/projects/genixis/ai-issue-116",
		"@2 /home/dev/projects/genixis/ai-review-118",
		"@3 ",
		"@4 /home/dev/projects/genixis/main",
		"@5 /home/me/my projects/demo/feat-x",
	}
	got := windowsWithOption(lines, "/home/dev/projects/genixis/ai-issue-116")
	if len(got) != 1 || got[0] != "@1" {
		t.Errorf("windows of the worktree = %q, want [@1]", got)
	}
	got = windowsWithOption(lines, "/home/me/my projects/demo/feat-x")
	if len(got) != 1 || got[0] != "@5" {
		t.Errorf("windows of a value with spaces = %q, want [@5]", got)
	}
	if got := windowsWithOption(lines, ""); len(got) != 0 {
		t.Errorf("the empty value matched windows: %q", got)
	}
	if got := windowsWithOption([]string{"@6"}, "/any"); len(got) != 0 {
		t.Errorf("a line without a value matched: %q", got)
	}
}
