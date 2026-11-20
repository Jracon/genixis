package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"genixis/project/internal/spec"
)

// The tmux, WezTerm, and nvim panes of the builder stay outside these tests;
// the scratch acceptance of issue #74 covers them. This file pins the pure
// decisions of the builder that survive without them, and the swap-back of
// the viewer pane against a fake tmux.

// fakeTmux puts a tmux on PATH that records every call and plays one viewer
// pane: show-option answers the viewer the environment names, and
// display-message answers for it as TMUX_VIEWER_ALIVE says.
func fakeTmux(t *testing.T) string {
	t.Helper()
	s := &scratch{t: t}
	log := filepath.Join(t.TempDir(), "tmux.log")
	t.Setenv("TMUX_LOG", log)
	t.Setenv("TMUX_VIEWER", "%5")
	t.Setenv("TMUX_VIEWER_ALIVE", "1")
	s.fakeBin(t, "tmux", "#!/bin/sh\n"+
		"printf '%s\\n' \"$*\" >> \"$TMUX_LOG\"\n"+
		"case \"$1 $2\" in\n"+
		"\"show-option -pqv\") echo \"$TMUX_VIEWER\" ;;\n"+
		"\"display-message -p\") if [ \"$TMUX_VIEWER_ALIVE\" = 1 ]; then echo \"$TMUX_VIEWER\"; else exit 1; fi ;;\n"+
		"esac\n")
	return log
}

// The canonical swap-back: a live viewer pane swaps nvim home, clears the
// option, and closes the viewer pane, and a dead viewer pane clears the
// option without a swap. The reload path of ideCloseReload and the openers
// of the ide family all go through it, so no path leaves a stale @ide_viewer
// behind.
func TestRestoreEditor(t *testing.T) {
	log := fakeTmux(t)
	restoreEditor("%81")
	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"swap-pane -s %5 -t %81",
		"set-option -pu -t %81 @ide_viewer",
		"kill-pane -t %5",
	} {
		if !strings.Contains(string(data), want) {
			t.Errorf("the swap-back misses %q:\n%s", want, data)
		}
	}

	// a dead viewer pane: the option clears, nothing swaps
	t.Setenv("TMUX_VIEWER_ALIVE", "0")
	os.Remove(log)
	restoreEditor("%81")
	data, err = os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "swap-pane") {
		t.Errorf("a dead viewer pane swapped: %s", data)
	}
	if !strings.Contains(string(data), "set-option -pu -t %81 @ide_viewer") {
		t.Errorf("a dead viewer pane left its option set: %s", data)
	}
}

// words splits a command line that shell.Quote built. Every word must be
// one simple quoted string: the paths of these tests hold no apostrophe.
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
// give no target, and the follow stays silent. A file under .scratch of the
// working directory gives no target too: the payload path resolves against
// the cwd of the payload before the decision, so a relative spelling of a
// scratch path is caught (issue #351).
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
		{"scratch absolute", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":"/w/.scratch/pr-351.md"}}`, "", "/w"},
		{"scratch relative", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":".scratch/pr-351.md"}}`, "", "/w"},
		{"scratch relative under a dirty cwd", `{"tool_name":"Write","cwd":"/w/","tool_input":{"file_path":".scratch/pr-351.md"}}`, "", "/w/"},
		{"scratch spelled with dot dot", `{"tool_name":"Edit","cwd":"/w","tool_input":{"file_path":"../w/.scratch/pr-351.md"}}`, "", "/w"},
		{"scratch of another directory", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":"/other/.scratch/pr-351.md"}}`, "/other/.scratch/pr-351.md", "/w"},
		{"scratch nested below the top", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":"/w/sub/.scratch/a.md"}}`, "/w/sub/.scratch/a.md", "/w"},
		{"scratch like a prefix", `{"tool_name":"Write","cwd":"/w","tool_input":{"file_path":"/w/.scratchpad/a.go"}}`, "/w/.scratchpad/a.go", "/w"},
		{"scratch relative without a cwd", `{"tool_name":"Write","cwd":"","tool_input":{"file_path":".scratch/pr-351.md"}}`, ".scratch/pr-351.md", ""},
	}
	for _, tc := range cases {
		file, dir := followTarget([]byte(tc.payload))
		if file != tc.file || dir != tc.dir {
			t.Errorf("%s: followTarget = (%q, %q), want (%q, %q)", tc.name, file, dir, tc.file, tc.dir)
		}
	}
}

// The focus guard of the follow (issues 504 and 564): while a client of the
// session of an ide window sits at the editor pane, the follow stays silent,
// because its drop would swap the buffer under the cursor of the person or
// switch the tab page. A client sits at the pane when the pane sits in the
// ide window, that window is the active window of its session, the pane is
// the active pane of the window, and the session holds a client. The two
// flags alone stay set after the client leaves (issue 564), so the attached
// count carries that half of the decision. Every other shape of the
// `#{window_id} #{window_active} #{pane_active} #{session_attached}` display
// is no focus: another pane, another window, a session without a client, a
// pane that a read-only viewer (ide-view) moved into its throwaway session,
// or a display that failed.
func TestPaneFocus(t *testing.T) {
	cases := []struct {
		name    string
		display string
		want    bool
	}{
		{"a client sits at the editor pane", "@3 1 1 1", true},
		{"a second client sits in the session", "@3 1 1 2", true},
		{"another pane of the window is active", "@3 1 0 1", false},
		{"another window of the session is active", "@3 0 1 1", false},
		{"another window and another pane", "@3 0 0 1", false},
		{"the pane sits in another window", "@7 1 1 1", false},
		{"no client sits in the session", "@3 1 1 0", false},
		{"a failed display", "", false},
	}
	for _, tc := range cases {
		if got := paneFocus("@3", tc.display); got != tc.want {
			t.Errorf("%s: paneFocus = %v, want %v", tc.name, got, tc.want)
		}
	}
}

// The follow never turns into a failure that a session sees: an empty payload,
// a payload whose working directory no ide window holds, and a payload that
// names a scratch file, all end in exit 0 with nothing written.
func TestIdeFollowIsSilentWithoutTarget(t *testing.T) {
	if err := ideFollow(strings.NewReader("")); err != nil {
		t.Errorf("empty payload: ideFollow = %v, want nil", err)
	}
	payload := `{"tool_name":"Write","cwd":"` + t.TempDir() + `","tool_input":{"file_path":"/nowhere/a.go"}}`
	if err := ideFollow(strings.NewReader(payload)); err != nil {
		t.Errorf("no window for the directory: ideFollow = %v, want nil", err)
	}
	scratch := `{"tool_name":"Write","cwd":"` + t.TempDir() + `","tool_input":{"file_path":".scratch/pr-351.md"}}`
	if err := ideFollow(strings.NewReader(scratch)); err != nil {
		t.Errorf("scratch file: ideFollow = %v, want nil", err)
	}
}

// The ending of the detach path: how a finished session reaches its person.
// The GUI behind the socket forward of a remote host window (issue #141)
// opens the tab; a local shell and a plain ssh login have no GUI that
// answers, and the hint names the command (issue #520). The remote half of
// a delegated open or spawn prints no attach hint, and a direct run on the
// remote host keeps it (issue #136).
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
		{"the GUI behind a forward opens the tab", false, true, false, reachHostTab},
		{"a local shell and a plain ssh login get the hint", false, false, false, reachHint},
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

// The session name of `ide pop` builds from the live tmux window name, and
// the denylist of the ruling on issue #382 rules the whole assembled name
// (issue #565): a window name comes from outside this code, and behind a
// socket forward the name lands unquoted in the executed tab line of
// remoteSessionCommand. The test walks the class member by member, the way
// TestSessionNameDeniesTheRulingClass walks it for project names.
func TestPopSessionNameDeniesTheRulingClass(t *testing.T) {
	denied := "\"'`$;|&<>()*?[]{}.:\\"
	for _, r := range denied + "\t\n\f\r " {
		name := "a" + string(r) + "b"
		if got := popSessionName(name, "@3"); got != "pop-a_b-3" {
			t.Errorf("popSessionName(%q) = %q, want %q", name, got, "pop-a_b-3")
		}
	}
	// a run of denied bytes in the window name becomes one underscore, and
	// a denied byte at either edge of the name leaves the literals of the
	// assembly in place
	if got := popSessionName("a. :'b", "@3"); got != "pop-a_b-3" {
		t.Errorf("popSessionName of a run of denied bytes = %q, want %q", got, "pop-a_b-3")
	}
	if got := popSessionName("$a", "@3"); got != "pop-_a-3" {
		t.Errorf("popSessionName of a leading denied byte = %q, want %q", got, "pop-_a-3")
	}
	if got := popSessionName("a;", "@3"); got != "pop-a_-3" {
		t.Errorf("popSessionName of a trailing denied byte = %q, want %q", got, "pop-a_-3")
	}
	// the dot and the colon of a window name once mapped to a hyphen; the
	// ruling takes them into the class, so they collapse with the rest, the
	// way sessionName treats every other session name of this tool
	if got := popSessionName("a.b:c", "@3"); got != "pop-a_b_c-3" {
		t.Errorf("popSessionName of a window name with separators = %q, want %q", got, "pop-a_b_c-3")
	}
}

// The staying bytes of the ruling keep their place in the assembled name:
// the prefix, the separator, and the window id hold no class byte, and the
// at sign of the window id drops before the denylist, because it is the
// syntax of a tmux window id, not part of the name.
func TestPopSessionNameAssemblesTheWholeName(t *testing.T) {
	cases := []struct {
		name       string
		windowName string
		windowID   string
		want       string
	}{
		{"a window named for a branch", "ai/issue-565", "@12", "pop-ai/issue-565-12"},
		{"a typed title of staying bytes", "v2,0+%", "@3", "pop-v2,0+%-3"},
		{"a non-ASCII window name", "grün€", "@1", "pop-grün€-1"},
		{"an empty window name", "", "@3", "pop--3"},
		{"a window id without the at sign", "demo", "3", "pop-demo-3"},
	}
	for _, tc := range cases {
		if got := popSessionName(tc.windowName, tc.windowID); got != tc.want {
			t.Errorf("%s: popSessionName = %q, want %q", tc.name, got, tc.want)
		}
	}
}
