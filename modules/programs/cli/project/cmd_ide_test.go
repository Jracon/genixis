package main

import (
	"io"
	"strings"
	"testing"

	"genixis/project/internal/spec"
)

// The tmux, WezTerm, and nvim panes of the builder stay outside these tests;
// the scratch acceptance of issue #74 covers them. This file pins the pure
// decisions of the builder that survive without them.

// words splits a command line that shQuote built. Every word must be one
// simple quoted string: the paths of these tests hold no apostrophe.
func words(t *testing.T, line string) []string {
	t.Helper()
	var out []string
	for _, field := range strings.Fields(line) {
		inner := strings.TrimSuffix(strings.TrimPrefix(field, "'"), "'")
		if len(field) < 2 || !strings.HasPrefix(field, "'") || !strings.HasSuffix(field, "'") || strings.Contains(inner, "'") {
			t.Fatalf("word %q is not one simple quoted string", field)
		}
		out = append(out, inner)
	}
	return out
}

// dispatchArgs routes a call through the name of the binary: a symlink of
// the ide family selects the subcommand, the binary itself does not.
func TestDispatchArgs(t *testing.T) {
	cases := []struct {
		argv0 string
		args  []string
		want  string
	}{
		{"/nix/store/x-project-0.1.0/bin/project", []string{"ide-view", "f.md"}, "ide-view f.md"},
		{"/nix/store/x-project-0.1.0/bin/project", []string{"open", "demo"}, "open demo"},
		{"/etc/profiles/per-user/u/bin/ide-view", []string{"f.md"}, "ide-view f.md"},
		{"/etc/profiles/per-user/u/bin/ide-open", []string{"a", "b"}, "ide-open a b"},
		{"/etc/profiles/per-user/u/bin/ide-tab", []string{"@1", "2"}, "ide-tab @1 2"},
		{"/etc/profiles/per-user/u/bin/wezterm-attach", []string{"demo"}, "wezterm-attach demo"},
		{"/tmp/project-test", []string{"ide-view", "f.md"}, "ide-view f.md"},
	}
	for _, tc := range cases {
		got := strings.Join(dispatchArgs(tc.argv0, tc.args), " ")
		if got != tc.want {
			t.Errorf("%s %v: dispatch = %q, want %q", tc.argv0, tc.args, got, tc.want)
		}
	}
}

// The command line of the viewer pane names the binary and one subcommand
// word. The pane died on exit 2 while selfPath gave a symlink of the ide
// family: dispatchArgs put a second ide-view in front of the word that the
// line already carried, and cmdIdeView rejected the doubled word. The pane
// closed, the editor slot collapsed, and the nvim pane stayed behind in the
// throwaway session.
func TestViewerPaneCommandRoutesOnce(t *testing.T) {
	exe := "/nix/store/x-project-0.1.0/bin/project"
	line := viewerCommand(exe, "--run", "%7", "AGENTS.md")
	fields := words(t, line)
	if fields[0] != exe {
		t.Fatalf("first word = %q, want the binary %q", fields[0], exe)
	}
	doubled := dispatchArgs("/etc/profiles/per-user/u/bin/ide-view", fields[1:])
	if code := cmdIdeView(doubled[1:], io.Discard, io.Discard); code != spec.ArgError {
		t.Fatalf("doubled subcommand word = exit %d, want %d", code, spec.ArgError)
	}
	for _, argv0 := range []string{exe, selfPath()} {
		pane := dispatchArgs(argv0, fields[1:])
		if got, want := strings.Join(pane, " "), "ide-view --run %7 AGENTS.md"; got != want {
			t.Errorf("%s: dispatch of the pane command = %q, want %q", argv0, got, want)
		}
	}
}

// The stdin payload of the PostToolUse hook names the file the session wrote:
// file_path of Write and Edit, notebook_path of NotebookEdit, beside the cwd
// of the session. Bytes that are not JSON, or a payload that names no file,
// give no target, and the follow stays silent.
func TestFollowTarget(t *testing.T) {
	cases := []struct {
		name    string
		payload string
		file    string
		dir     string
	}{
		{"write", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":"/w/a.go","content":"x"}}`, "/w/a.go", "/w"},
		{"edit", `{"tool_name":"Edit","cwd":"/w","tool_input":{"file_path":"/w/a.go","old_string":"x","new_string":"y"}}`, "/w/a.go", "/w"},
		{"notebook", `{"tool_name":"NotebookEdit","cwd":"/w","tool_input":{"notebook_path":"/w/n.ipynb","new_source":"x"}}`, "/w/n.ipynb", "/w"},
		{"no file", `{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"ls"}}`, "", "/w"},
		{"not json", `not json`, "", ""},
	}
	for _, tc := range cases {
		file, dir := followTarget([]byte(tc.payload))
		if file != tc.file || dir != tc.dir {
			t.Errorf("%s: followTarget = (%q, %q), want (%q, %q)", tc.name, file, dir, tc.file, tc.dir)
		}
	}
}

// The follow never turns into a failure that a session sees: an empty payload,
// and a payload whose working directory no ide window holds, both end in exit
// 0 with nothing written.
func TestIdeFollowIsSilentWithoutTarget(t *testing.T) {
	if err := ideFollow(strings.NewReader("")); err != nil {
		t.Errorf("empty payload: ideFollow = %v, want nil", err)
	}
	payload := `{"tool_name":"Write","cwd":"` + t.TempDir() + `","tool_input":{"file_path":"/nowhere/a.go"}}`
	if err := ideFollow(strings.NewReader(payload)); err != nil {
		t.Errorf("no window for the directory: ideFollow = %v, want nil", err)
	}
}

// The ending of the detach path: how a finished session reaches its person.
// A GUI that can show a tab from this shell — the local one, or the one
// behind the socket forward of a remote host window (issue #141) — opens
// the tab; over a plain ssh login no GUI answers, and the hint names the
// command. The remote half of a delegated open or spawn prints no attach
// hint, and a direct run on the remote host keeps it (issue #136).
func TestDetachReaching(t *testing.T) {
	cases := []struct {
		name       string
		shown      bool
		gui        bool
		remoteHalf bool
		want       detachReach
	}{
		{"a terminal shows the session", true, false, false, reachShown},
		{"a shown session wins over every other case", true, true, true, reachShown},
		{"a reachable GUI opens the tab", false, true, false, reachHostTab},
		{"without a reachable GUI the hint names the command", false, false, false, reachHint},
		{"the remote half prints no hint with a GUI", false, true, true, reachQuiet},
		{"the remote half prints no hint without a GUI", false, false, true, reachQuiet},
	}
	for _, tc := range cases {
		got := detachReaching(tc.shown, tc.gui, tc.remoteHalf)
		if got != tc.want {
			t.Errorf("%s: detachReaching = %v, want %v", tc.name, got, tc.want)
		}
	}
}
