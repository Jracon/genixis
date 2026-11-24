package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"genixis/project/internal/backend"
	"genixis/project/internal/settings"
	"genixis/project/internal/spec"
)

// The tests of this file call run() in process, with a scratch project that
// the helpers build under a temp HOME. They freeze the consumer contracts
// of the rewrite: the exit codes, the JSON envelopes of the machine-facing
// subcommands, the cd protocol of the fish stub, and the completion
// protocol. The ide window paths (tmux, WezTerm, nvim panes) stay outside
// these tests; the scratch acceptance of issue #74 covers them.

type scratch struct {
	t    *testing.T
	home string
	dir  string
	main string
}

func newScratch(t *testing.T) *scratch {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not available")
	}
	s := &scratch{t: t}
	s.home = t.TempDir()
	// darwin resolves TMPDIR through the /var symlink, and the tool and git
	// report worktrees at the resolved path: work from the resolved home, or
	// every path comparison against the tool output misses
	if resolved, err := filepath.EvalSymlinks(s.home); err == nil {
		s.home = resolved
	}
	t.Setenv("HOME", s.home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(s.home, ".config"))
	for _, pair := range [][2]string{
		{"GIT_AUTHOR_NAME", "test"},
		{"GIT_AUTHOR_EMAIL", "test@example"},
		{"GIT_COMMITTER_NAME", "test"},
		{"GIT_COMMITTER_EMAIL", "test@example"},
	} {
		t.Setenv(pair[0], pair[1])
	}
	// no inherited plan and no tmux in these tests
	t.Setenv("PROJECT_PLAN", "")
	t.Setenv("TMUX", "")

	// the memory gate reads a fixture with a healthy host, so no spawn or
	// ide test depends on the memory of the machine that runs the tests
	setMeminfo(t, 12<<20, 8<<20)

	s.dir = filepath.Join(s.home, "projects", "demo")
	s.main = filepath.Join(s.dir, "main")
	must(t, os.MkdirAll(s.main, 0o755))
	git(t, s.main, "init", "--quiet", "--initial-branch", "main")
	git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "initial")
	return s
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v in %s: %v: %s", args, dir, err, out)
	}
	return string(out)
}

// fakeBin gives the scratch a private PATH: bin holds the named executable
// script and a symlink to the real git, and nothing else. A binary that the
// path under test must not reach — tmux, so a spawn opens no view window on
// the server of the user — then finds no entry.
func (s *scratch) fakeBin(t *testing.T, name, script string) {
	t.Helper()
	bin := t.TempDir()
	path := filepath.Join(bin, name)
	must(t, os.WriteFile(path, []byte(script), 0o755))
	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Skip("git is not available")
	}
	must(t, os.Symlink(gitPath, filepath.Join(bin, "git")))
	t.Setenv("PATH", bin)
}

func (s *scratch) run(argv ...string) (int, string, string) {
	s.t.Helper()
	var stdout, stderr bytes.Buffer
	code := run(argv, &stdout, &stderr)
	return code, stdout.String(), stderr.String()
}

// invoke runs the binary through go it would not do; in process is enough.
func (s *scratch) envelope(argv ...string) (int, map[string]any, string) {
	s.t.Helper()
	code, stdout, stderr := s.run(argv...)
	var envelope map[string]any
	if err := json.Unmarshal([]byte(stdout), &envelope); err != nil {
		s.t.Fatalf("stdout is not one JSON envelope: %v: %q", err, stdout)
	}
	return code, envelope, stderr
}

// ---------------------------------------------------------------- exit codes

func TestUsageIsArgumentError(t *testing.T) {
	newScratch(t)
	code, _, _ := (&scratch{t: t}).run()
	if spec.ExitCode(code) != spec.ArgError {
		t.Fatalf("exit = %d, want %d", code, spec.ArgError)
	}
}

// ---------------------------------------------------------------------- help

// The help screens are the user documentation of the tool: the overview
// lists every command, and one screen answers for each command, whatever
// way it is asked for. The paths stay side-effect free, so a --help never
// builds a window or starts a session.
func TestHelpScreens(t *testing.T) {
	s := newScratch(t)

	// no arguments is an argument error, and the overview lands on stderr
	code, _, stderr := s.run()
	if spec.ExitCode(code) != spec.ArgError {
		t.Fatalf("exit = %d", code)
	}
	if !strings.Contains(stderr, "project help <command>") {
		t.Errorf("no-args stderr misses the help pointer: %q", stderr)
	}

	// --help, -h, and help print the same overview on stdout with exit 0
	overviews := make([]string, 3)
	for i, argv := range [][]string{{"--help"}, {"-h"}, {"help"}} {
		code, out, _ := s.run(argv...)
		if spec.ExitCode(code) != spec.Success {
			t.Fatalf("%v exit = %d", argv, code)
		}
		overviews[i] = out
		for _, want := range []string{
			"open", "add", "spawn", "list", "review", "board", "close", "discard", "clean",
			"convert", "lmk", "ask", "btw", "ide", "ide-layout", "ide-open", "ide-edit",
			"ide-tab", "ide-view", "wezterm-attach", "Exit codes",
		} {
			if !strings.Contains(out, want) {
				t.Errorf("%v output misses %q", argv, want)
			}
		}
	}
	if overviews[0] != overviews[1] || overviews[0] != overviews[2] {
		t.Errorf("the help verbs print different overviews")
	}

	// `help <command>` and `<command> --help` print the same screen
	code, viaHelp, _ := s.run("help", "spawn")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("help spawn exit = %d", code)
	}
	code, viaFlag, _ := s.run("spawn", "--help")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn --help exit = %d", code)
	}
	if viaHelp != viaFlag {
		t.Errorf("`help spawn` and `spawn --help` print different screens")
	}
	for _, want := range []string{
		"--from <base>", "--as <name>", "--plan <name>", "--identity <name>",
		"--permission-mode <mode>", "--headless", "<prompt...>", "Examples:",
	} {
		if !strings.Contains(viaHelp, want) {
			t.Errorf("spawn screen misses %q:\n%s", want, viaHelp)
		}
	}

	// every documented command answers, at its own name, with exit 0; the
	// ide verbs answer at their two-word name too
	for i := range commandDocs {
		name := commandDocs[i].name
		code, out, _ := s.run(append([]string{"help"}, strings.Fields(name)...)...)
		if spec.ExitCode(code) != spec.Success || out == "" {
			t.Errorf("help %s exit = %d", name, code)
		}
	}

	// unknown names are argument errors that name themselves
	code, _, stderr = s.run("frobnicate")
	if spec.ExitCode(code) != spec.ArgError || !strings.Contains(stderr, "unknown command frobnicate") {
		t.Errorf("frobnicate exit = %d, stderr = %q", code, stderr)
	}
	code, _, stderr = s.run("help", "frobnicate")
	if spec.ExitCode(code) != spec.ArgError || !strings.Contains(stderr, "no help for") {
		t.Errorf("help frobnicate exit = %d, stderr = %q", code, stderr)
	}

	// an argument error points at the screen of the command, not at a
	// one-line dump of every command
	code, _, stderr = s.run("add", s.dir)
	if spec.ExitCode(code) != spec.ArgError || !strings.Contains(stderr, "project help add") {
		t.Errorf("add exit = %d, stderr = %q", code, stderr)
	}
}

func TestAddNeedsBranch(t *testing.T) {
	s := newScratch(t)
	code, _, stderr := s.run("add", s.dir)
	if spec.ExitCode(code) != spec.ArgError {
		t.Fatalf("exit = %d, want %d: %s", code, spec.ArgError, stderr)
	}
}

func TestMissingProjectIsNotFound(t *testing.T) {
	s := newScratch(t)
	code, env, _ := s.envelope("add", filepath.Join(s.home, "projects", "nope"), "feat/x")
	if spec.ExitCode(code) != spec.NotFound {
		t.Fatalf("exit = %d, want %d", code, spec.NotFound)
	}
	if env["ok"] != false {
		t.Errorf("ok = %v", env["ok"])
	}
}

func TestDiscardRefusesOutsideTerminal(t *testing.T) {
	s := newScratch(t)
	t.Setenv("CLAUDECODE", "1")
	code, _, stderr := s.run("discard", "feat-x")
	if spec.ExitCode(code) != spec.PermissionDenied {
		t.Fatalf("exit = %d, want %d: %s", code, spec.PermissionDenied, stderr)
	}
}

// ------------------------------------------------------------------ envelopes

// failWriter answers an error on every write, so the emitter meets a stdout
// that cannot take the envelope.
type failWriter struct{}

func (failWriter) Write([]byte) (int, error) { return 0, errors.New("closed") }

// The one emitter behind the machine-facing commands: a failure reaches the
// envelope as code and detail and stderr as its diagnostic, the meta names
// the command, the tool, and the schema, and a stdout that cannot take the
// envelope answers the general error.
func TestEmitEnvelope(t *testing.T) {
	newScratch(t)
	started := time.Now().Add(-time.Second)
	var stdout, stderr bytes.Buffer
	code := emitEnvelope("add", &stdout, &stderr, started,
		map[string]any{"branch": "feat/x"}, errNotFound("no project %s", "/nope"), nil)
	if spec.ExitCode(code) != spec.NotFound {
		t.Fatalf("exit = %d, want %d", code, spec.NotFound)
	}
	var envelope map[string]any
	if err := json.Unmarshal(stdout.Bytes(), &envelope); err != nil {
		t.Fatalf("stdout is not one JSON envelope: %v: %q", err, stdout.String())
	}
	if envelope["ok"] != false {
		t.Errorf("ok = %v", envelope["ok"])
	}
	if errObj := envelope["error"].(map[string]any); errObj["code"] != "NOT_FOUND" {
		t.Errorf("error = %v", errObj)
	}
	meta := envelope["meta"].(map[string]any)
	if meta["command"] != "add" || meta["tool_version"] != version || meta["schema_version"] != "1.0" {
		t.Errorf("meta = %v", meta)
	}
	if meta["duration_ms"].(float64) < 900 {
		t.Errorf("duration_ms = %v, want the elapsed time", meta["duration_ms"])
	}
	if !strings.Contains(stderr.String(), "no project /nope") {
		t.Errorf("stderr = %q", stderr.String())
	}

	// a success carries its data, and a failed write answers the general error
	stdout.Reset()
	if code := emitEnvelope("list", &stdout, io.Discard, time.Now(), map[string]any{"dir": "/demo"}, nil, nil); spec.ExitCode(code) != spec.Success {
		t.Errorf("exit = %d, want %d", code, spec.Success)
	}
	if code := emitEnvelope("list", failWriter{}, io.Discard, time.Now(), nil, nil, nil); spec.ExitCode(code) != spec.GeneralError {
		t.Errorf("exit of a failed write = %d, want %d", code, spec.GeneralError)
	}
}

func TestAddEmitsOneEnvelope(t *testing.T) {
	s := newScratch(t)
	code, env, stderr := s.envelope("add", s.dir, "feat/x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if env["ok"] != true {
		t.Errorf("ok = %v", env["ok"])
	}
	data := env["data"].(map[string]any)
	wantTree := filepath.Join(s.dir, "feat-x")
	if data["worktree"] != wantTree || data["branch"] != "feat/x" {
		t.Errorf("data = %v", data)
	}
	meta := env["meta"].(map[string]any)
	if meta["command"] != "add" || meta["exit_code"] != float64(0) {
		t.Errorf("meta = %v", meta)
	}
	if w := env["warnings"].([]any); len(w) != 0 {
		t.Errorf("warnings = %v", w)
	}
	// the claim is idempotent: a second add reports the same worktree
	code, env, _ = s.envelope("add", s.dir, "feat/x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("second add exit = %d", code)
	}
	data = env["data"].(map[string]any)
	if data["worktree"] != wantTree {
		t.Errorf("second add data = %v", data)
	}
}

func TestListReadsTheFrontier(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	// work on feat/x, so the merge slot no longer accepts it: a branch at
	// the commit it started from counts as merged, exactly as close does
	git(t, filepath.Join(s.dir, "feat-x"), "commit", "--quiet", "--allow-empty", "--message", "work")
	// a merged branch without a worktree is a loose, merge-ready entry
	git(t, s.main, "branch", "done")
	code, env, stderr := s.envelope("list", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	data := env["data"].(map[string]any)
	if data["defaultBranch"] != "main" {
		t.Errorf("defaultBranch = %v", data["defaultBranch"])
	}
	branches := data["branches"].([]any)
	byName := map[string]map[string]any{}
	for _, entry := range branches {
		entry := entry.(map[string]any)
		byName[entry["branch"].(string)] = entry
	}
	held, ok := byName["feat/x"]
	if !ok || held["worktree"] != filepath.Join(s.dir, "feat-x") || held["merged"] != false {
		t.Errorf("feat/x entry = %v", held)
	}
	if loose, ok := byName["done"]; !ok || loose["merged"] != true || loose["worktree"] != "" {
		t.Errorf("done entry = %v", loose)
	}
}

// -------------------------------------------------------- the stale-base guard

// A spawn whose fetch fails must not start a leg on local main, which may
// be older than origin main (issue #100): it fails loudly with the exit
// code the dispatcher retries. A branch that already exists continues its
// own work, so it keeps the warning fallback, and so do add and open.
func TestSpawnRefusesStaleBaseWhenFetchFails(t *testing.T) {
	s := newScratch(t)
	// an origin that no fetch can reach: the remote exists, so the fetch
	// runs and fails, and origin/<default> never exists
	git(t, s.main, "remote", "add", "origin", filepath.Join(s.home, "unreachable"))

	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Unavailable {
		t.Fatalf("spawn exit = %d, want %d: %s", code, spec.Unavailable, stderr)
	}
	if errObj := env["error"].(map[string]any); errObj["code"] != "UNAVAILABLE" {
		t.Errorf("error = %v", errObj)
	}
	if _, err := os.Stat(filepath.Join(s.dir, "feat-x")); !os.IsNotExist(err) {
		t.Errorf("a refused spawn left a worktree behind")
	}

	// add keeps the fallback: the claim happens, with one warning
	code, env, _ = s.envelope("add", s.dir, "feat/y")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("add exit = %d, want %d", code, spec.Success)
	}
	warnings := env["warnings"].([]any)
	if len(warnings) != 1 || !strings.Contains(warnings[0].(map[string]any)["message"].(string), "couldn't fetch origin") {
		t.Errorf("add warnings = %v", warnings)
	}

	// a spawn on a branch that already exists continues its own work, so
	// the fetch cannot make its base staler: the spawn proceeds with the
	// warning (--print-settings returns before any session starts)
	git(t, s.main, "branch", "feat/z")
	code, stdout, stderr := s.run("spawn", s.dir, "feat/z", "--headless", "--print-settings", "x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn on an existing branch exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stdout, "permissions") || !strings.Contains(stderr, "couldn't fetch origin") {
		t.Errorf("stdout = %q, stderr = %q", stdout, stderr)
	}
}

// -------------------------------------------------------- the verified trunk

// --verified-trunk (issue #637) names a base the caller verified against
// origin: the claim runs no fetch of its own, so an origin no fetch can
// reach stops no spawn, no projectBase is recorded, and the flags --from
// and --verified-trunk never name one base together. add takes no
// verified base: a person reads the fetch warning instead.
func TestSpawnVerifiedTrunkSkipsTheFetch(t *testing.T) {
	s := newScratch(t)
	// an origin that no fetch can reach, as in the guard test above
	git(t, s.main, "remote", "add", "origin", filepath.Join(s.home, "unreachable"))

	code, _, stderr := s.run("spawn", s.dir, "feat/vt1", "--headless", "--print-settings",
		"--from", "main", "--verified-trunk", "main", "x")
	if spec.ExitCode(code) != spec.ArgError {
		t.Fatalf("two named bases exit = %d, want %d: %s", code, spec.ArgError, stderr)
	}

	code, _, stderr = s.run("add", s.dir, "feat/vt2", "--verified-trunk", "main")
	if spec.ExitCode(code) != spec.ArgError {
		t.Fatalf("add with a verified trunk exit = %d, want %d: %s", code, spec.ArgError, stderr)
	}

	code, _, stderr = s.run("spawn", s.dir, "feat/vt2", "--headless", "--print-settings",
		"--verified-trunk", "nosuch", "x")
	if spec.ExitCode(code) != spec.NotFound {
		t.Fatalf("unknown trunk exit = %d, want %d: %s", code, spec.NotFound, stderr)
	}

	// the ruled route: no fetch runs, so the unreachable origin refuses
	// nothing, and the branch starts at the local trunk, because no
	// origin/<trunk> ref exists
	code, stdout, stderr := s.run("spawn", s.dir, "feat/vt3", "--headless", "--print-settings",
		"--verified-trunk", "main", "x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("verified-trunk spawn exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stdout, "permissions") {
		t.Errorf("stdout = %q", stdout)
	}
	if strings.Contains(stderr, "couldn't fetch origin") {
		t.Errorf("a verified trunk still fetched: %q", stderr)
	}
	if got := gitBackend.ConfigGet(s.main, "branch.feat/vt3.projectBase"); got != "" {
		t.Errorf("projectBase of a verified trunk = %q, want none", got)
	}
}

// The origin tip wins over the local branch of a verified trunk: the caller
// verified the tip that its own fetch brought in, and the local branch may
// sit behind it.
func TestSpawnVerifiedTrunkStartsAtTheOriginTip(t *testing.T) {
	s := newScratch(t)
	git(t, s.home, "init", "--quiet", "--bare", "origin.git")
	origin := filepath.Join(s.home, "origin.git")
	git(t, s.main, "remote", "add", "origin", origin)
	git(t, s.main, "push", "--quiet", "origin", "main")
	// advance origin/main past the local main, from a branch of the clone
	git(t, s.main, "checkout", "--quiet", "-b", "tip")
	git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "tip")
	git(t, s.main, "push", "--quiet", "origin", "tip:main")
	git(t, s.main, "checkout", "--quiet", "main")

	code, _, stderr := s.run("spawn", s.dir, "feat/vt4", "--headless", "--print-settings",
		"--verified-trunk", "main", "x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("verified-trunk spawn exit = %d: %s", code, stderr)
	}
	head := strings.TrimSpace(git(t, filepath.Join(s.dir, "feat-vt4"), "rev-parse", "HEAD"))
	tip := strings.TrimSpace(git(t, s.main, "rev-parse", "tip"))
	if head != tip {
		t.Errorf("worktree head = %s, want the origin tip %s", head, tip)
	}
}

// -------------------------------------------------- the headless session id

// The stub claude of the headless tests: a `claude --bg` run prints the
// documented backgrounded block, and an `agents --json` run answers the
// session listing that the environment names, with the full session UUID in
// sessionId (issue #524).
func fakeClaudeScript(bg string, listing string) string {
	return "#!/bin/sh\n" +
		"if [ \"$1\" = agents ]; then\n" +
		"printf '%s' " + strconv.Quote(listing) + "\n" +
		"exit 0\n" +
		"fi\n" +
		bg
}

// A headless spawn captures the output of `claude --bg` and reads the
// session id out of it: the envelope carries the id beside the session
// name, the whole claude output still reaches the spawn's stderr (the
// machine contract of --headless), and the attach hint names the id. The
// spawn also resolves the full session UUID of the session from the
// listing, and the envelope carries it beside the id (issue #524). The
// scratch PATH holds a fake claude and no tmux, so the view window takes
// its no-tmux exit and the test opens nothing on a real server (issue
// #208).
func TestHeadlessSpawnCarriesTheSessionID(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", fakeClaudeScript(
		"printf 'backgrounded · 7c5dcf5d · demo: feat/x\\n'\n"+
			"printf '  claude attach 7c5dcf5d    open in this terminal\\n'\n"+
			"printf 'spun up\\n' >&2\n",
		`[{"id":"7c5dcf5d","kind":"background","name":"demo: feat/x",`+
			`"sessionId":"7c5dcf5d-3a5e-4f6a-9b2c-1d4e5f6a7b8c"},`+
			`{"id":"fg-1","kind":"interactive","name":"genixis: main"}]`,
	))
	s.run("add", s.dir, "feat/x")
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	data := env["data"].(map[string]any)
	if data["session"] != "demo: feat/x" || data["session_id"] != "7c5dcf5d" {
		t.Errorf("data = %v, want the session name and the id", data)
	}
	if data["session_uuid"] != "7c5dcf5d-3a5e-4f6a-9b2c-1d4e5f6a7b8c" {
		t.Errorf("data = %v, want the full session uuid of the listing", data)
	}
	// both streams of claude reach the spawn's stderr, whatever stream the
	// real print uses
	if !strings.Contains(stderr, "backgrounded · 7c5dcf5d") || !strings.Contains(stderr, "spun up") {
		t.Errorf("stderr holds no claude output: %q", stderr)
	}
	// the hint names the id, and the view window names its no-tmux exit
	if !strings.Contains(stderr, `claude attach "7c5dcf5d"`) {
		t.Errorf("the attach hint names no id: %q", stderr)
	}
	if !strings.Contains(stderr, "no tmux here") {
		t.Errorf("the view window opened anyway: %q", stderr)
	}
	if warnings := env["warnings"].([]any); len(warnings) != 0 {
		t.Errorf("warnings = %v, want none", warnings)
	}
}

// A claude that prints no id leaves the name as the only attach handle, and
// a listing that answers no json leaves the id as the only resume handle:
// the envelope holds neither extra field, one warning names each gap, and
// the attach hint falls back to the name (issues #208 and #524).
func TestHeadlessSpawnWithoutAnIDWarnsAndFallsBack(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", "#!/bin/sh\nprintf 'started, but no id in sight\\n'\n")
	s.run("add", s.dir, "feat/x")
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	data := env["data"].(map[string]any)
	if _, held := data["session_id"]; held {
		t.Errorf("data holds a session id: %v", data)
	}
	if _, held := data["session_uuid"]; held {
		t.Errorf("data holds a session uuid: %v", data)
	}
	codes := []string{}
	for _, warning := range env["warnings"].([]any) {
		codes = append(codes, warning.(map[string]any)["code"].(string))
	}
	if len(codes) != 2 || codes[0] != "NO_SESSION_ID" || codes[1] != "NO_SESSION_UUID" {
		t.Errorf("warnings = %v, want NO_SESSION_ID and NO_SESSION_UUID", codes)
	}
	if !strings.Contains(stderr, `claude attach "demo: feat/x"`) {
		t.Errorf("the attach hint names no session: %q", stderr)
	}
}

// The session name resolves the full UUID when claude prints no id: the
// listing carries the name beside the ids, so the envelope holds the uuid
// and only the missing id warns. A later leg can resume the session even
// though the view window attaches by name (issue #524).
func TestHeadlessSpawnResolvesTheUUIDByTheSessionName(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", fakeClaudeScript(
		"printf 'started, but no id in sight\\n'\n",
		`[{"id":"aa11","kind":"background","name":"demo: feat/x",`+
			`"sessionId":"aa11bb22-3c4d-5e6f-8091-2a3b4c5d6e7f"}]`,
	))
	s.run("add", s.dir, "feat/x")
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	data := env["data"].(map[string]any)
	if _, held := data["session_id"]; held {
		t.Errorf("data holds a session id: %v", data)
	}
	if data["session_uuid"] != "aa11bb22-3c4d-5e6f-8091-2a3b4c5d6e7f" {
		t.Errorf("data = %v, want the uuid of the named session", data)
	}
	warnings := env["warnings"].([]any)
	if len(warnings) != 1 || warnings[0].(map[string]any)["code"] != "NO_SESSION_ID" {
		t.Errorf("warnings = %v, want one NO_SESSION_ID", warnings)
	}
}

// A listing that names neither handle leaves the spawn without a uuid: the
// envelope carries the id alone, and one warning says that no later leg can
// resume this session (issue #524).
func TestHeadlessSpawnWithoutAUuidWarns(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", fakeClaudeScript(
		"printf 'backgrounded · 7c5dcf5d · demo: feat/x\\n'\n",
		`[{"id":"bg-35","kind":"background","name":"live-session",`+
			`"sessionId":"11111111-2222-3333-4444-555555555555"}]`,
	))
	s.run("add", s.dir, "feat/x")
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	data := env["data"].(map[string]any)
	if data["session_id"] != "7c5dcf5d" {
		t.Errorf("data = %v, want the id of the block", data)
	}
	if _, held := data["session_uuid"]; held {
		t.Errorf("data holds a session uuid: %v", data)
	}
	warnings := env["warnings"].([]any)
	if len(warnings) != 1 || warnings[0].(map[string]any)["code"] != "NO_SESSION_UUID" {
		t.Errorf("warnings = %v, want one NO_SESSION_UUID", warnings)
	}
}

// ------------------------------------------------------------- the resume flag

// A headless spawn with --resume <uuid> passes the uuid to claude beside
// the launch flags: claude --resume <uuid> --bg continues the session under
// its own id, or starts a copy under a new id with one note line (issue
// #524). The stub claude logs each call, so the test reads the exact claude
// argument line.
func TestHeadlessSpawnPassesTheResumeFlag(t *testing.T) {
	s := newScratch(t)
	log := filepath.Join(s.t.TempDir(), "claude.log")
	s.t.Setenv("FAKE_CLAUDE_LOG", log)
	s.fakeBin(t, "claude", "#!/bin/sh\n"+
		"printf '%s\\n' \"$*\" >>\"$FAKE_CLAUDE_LOG\"\n"+
		"if [ \"$1\" = agents ]; then exit 0; fi\n"+
		"printf 'backgrounded · 7c5dcf5d · demo: feat/x\\n'\n")
	s.run("add", s.dir, "feat/x")
	uuid := "7c5dcf5d-3a5e-4f6a-9b2c-1d4e5f6a7b8c"
	code, _, stderr := s.run("spawn", s.dir, "feat/x", "--headless",
		"--permission-mode", "dontAsk", "--resume", uuid, "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	calls := strings.Split(strings.TrimSpace(string(mustRead(t, log))), "\n")
	if len(calls) < 1 || !strings.Contains(calls[0], "--resume "+uuid+" -- work") {
		t.Errorf("claude call = %q, want the resume flag before the prompt", calls)
	}
	if strings.Contains(calls[0], "--resume "+uuid+" --resume") {
		t.Errorf("claude call repeats the resume flag: %q", calls[0])
	}
}

// The resume flag belongs to the headless route alone: add and open start
// no headless session, and a windowed spawn must not resume, because a
// resumed session keeps its launch flags, so the watched mode of a windowed
// launch may never reach a session that a plain launch started (issue
// #524). Each refusal is an argument error.
func TestResumeFlagRefusesTheOtherRoutes(t *testing.T) {
	s := newScratch(t)
	uuid := "7c5dcf5d-3a5e-4f6a-9b2c-1d4e5f6a7b8c"
	for _, argv := range [][]string{
		{"add", s.dir, "feat/x", "--resume", uuid},
		{"open", s.dir, "feat/x", "--resume", uuid},
		{"spawn", s.dir, "feat/x", "--resume", uuid, "work"},
	} {
		code, _, stderr := s.run(argv...)
		if spec.ExitCode(code) != spec.ArgError {
			t.Fatalf("%v exit = %d, want %d: %s", argv[:1], code, spec.ArgError, stderr)
		}
		if !strings.Contains(stderr, "--resume") {
			t.Errorf("%v stderr names no resume flag: %q", argv[:1], stderr)
		}
	}
}

// A spawn carries the rules of the tracked project layer of its worktree in
// the settings file, beside the spawn rules (issue 627): the settings file
// is the one layer that every session kind on record loaded, so the gate
// commands of a leg must not depend on the working-directory layer alone.
func TestHeadlessSpawnCarriesTheProjectRules(t *testing.T) {
	s := newScratch(t)
	log := filepath.Join(s.t.TempDir(), "claude.log")
	s.t.Setenv("FAKE_CLAUDE_LOG", log)
	s.fakeBin(t, "claude", "#!/bin/sh\n"+
		"printf '%s\\n' \"$*\" >>\"$FAKE_CLAUDE_LOG\"\n"+
		"if [ \"$1\" = agents ]; then exit 0; fi\n"+
		"printf 'backgrounded · 7c5dcf5d · demo: feat/x\\n'\n")
	s.run("add", s.dir, "feat/x")
	layerDir := filepath.Join(s.dir, "feat-x", ".claude")
	must(t, os.MkdirAll(layerDir, 0o755))
	must(t, os.WriteFile(filepath.Join(layerDir, "settings.json"),
		[]byte(`{"permissions":{"allow":["Bash(nix fmt -- --ci)","Write"],"deny":["Bash(rm *)"]}}`), 0o644))
	code, _, stderr := s.run("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	calls := strings.Split(strings.TrimSpace(string(mustRead(t, log))), "\n")
	permissions := settingsPayload(t, calls[0])
	allow, held := permissions["allow"].([]any)
	if !held {
		t.Fatalf("settings hold no allow list: %q", calls[0])
	}
	// the project rules ride first, in file order, before the spawn rules
	if allow[0] != "Bash(nix fmt -- --ci)" || allow[1] != "Write" {
		t.Errorf("allow head = %v, want the project rules in file order", allow)
	}
	reads := false
	for _, rule := range allow {
		if strings.HasPrefix(rule.(string), "Read(/") {
			reads = true
		}
	}
	if !reads {
		t.Errorf("allow = %v, want the spawn read rules beside the project rules", allow)
	}
	deny, held := permissions["deny"].([]any)
	if !held {
		t.Fatalf("settings hold no deny list: %q", calls[0])
	}
	if deny[0] != "Bash(rm *)" {
		t.Errorf("deny head = %v, want the project deny rule first", deny)
	}
	edits := false
	for _, rule := range deny {
		if strings.HasPrefix(rule.(string), "Edit(/") {
			edits = true
		}
	}
	if !edits {
		t.Errorf("deny = %v, want the spawn deny rules beside the project rule", deny)
	}
}

// A project settings file that exists but reads as no rule set warns, and the
// spawn still serves: the session then holds the spawn rules alone.
func TestSpawnWarnsOnUnreadableProjectRules(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", "#!/bin/sh\nprintf 'backgrounded · 7c5dcf5d · demo: feat/x\\n'\n")
	s.run("add", s.dir, "feat/x")
	layerDir := filepath.Join(s.dir, "feat-x", ".claude")
	must(t, os.MkdirAll(layerDir, 0o755))
	must(t, os.WriteFile(filepath.Join(layerDir, "settings.json"), []byte("{not json"), 0o644))
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("spawn exit = %d: %s", code, stderr)
	}
	found := false
	for _, warning := range env["warnings"].([]any) {
		if warning.(map[string]any)["code"] == "PROJECT_RULES_UNREADABLE" {
			found = true
		}
	}
	if !found {
		t.Errorf("warnings = %v, want one PROJECT_RULES_UNREADABLE", env["warnings"])
	}
}

// settingsPayload reads the permissions object out of the --settings argument
// that one logged claude call carries. The stub claude logs the joined
// argument line, so the payload ends at the next flag.
func settingsPayload(t *testing.T, call string) map[string]any {
	t.Helper()
	const flag = "--settings "
	start := strings.Index(call, flag)
	if start < 0 {
		t.Fatalf("claude call names no settings: %q", call)
	}
	start += len(flag)
	end := strings.Index(call[start:], " --permission-mode")
	if end < 0 {
		t.Fatalf("claude call names no permission mode: %q", call)
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(call[start:start+end]), &payload); err != nil {
		t.Fatalf("settings argument is no JSON object: %v: %q", err, call[start:start+end])
	}
	permissions, held := payload["permissions"].(map[string]any)
	if !held {
		t.Fatalf("settings hold no permissions object: %q", call[start:start+end])
	}
	return permissions
}

// A claude that fails still speaks: its output reaches the spawn's stderr
// before the error, so the dispatcher journal holds the cause.
func TestHeadlessSpawnEchoesAFailingClaude(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "claude", "#!/bin/sh\nprintf 'claude: no trust for this worktree\\n' >&2\nexit 3\n")
	s.run("add", s.dir, "feat/x")
	code, env, stderr := s.envelope("spawn", s.dir, "feat/x", "--headless", "--permission-mode", "dontAsk", "work")
	if spec.ExitCode(code) != spec.GeneralError {
		t.Fatalf("spawn exit = %d, want %d: %s", code, spec.GeneralError, stderr)
	}
	if errObj := env["error"].(map[string]any); errObj["code"] != "GENERAL_ERROR" {
		t.Errorf("error = %v", errObj)
	}
	if !strings.Contains(stderr, "no trust for this worktree") {
		t.Errorf("stderr holds no claude failure: %q", stderr)
	}
}

// ------------------------------------------------------------- close and clean

func TestCloseRefusesUncommittedWork(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	must(t, os.WriteFile(filepath.Join(s.dir, "feat-x", "file.txt"), []byte("work"), 0o644))
	code, _, stderr := s.run("close", filepath.Join(s.dir, "feat-x"))
	if spec.ExitCode(code) != spec.GeneralError {
		t.Fatalf("exit = %d, want %d: %s", code, spec.GeneralError, stderr)
	}
	if !strings.Contains(stderr, "uncommitted work") {
		t.Errorf("stderr = %q", stderr)
	}
}

// The refusal of a changed included file names the worktree and prints each
// file as its path inside it, the way the uncommitted-work refusal does:
// clean closes many worktrees in one run, so the tree must say which copy
// differs and where (issue #182).
func TestCloseRefusalNamesWorktreeOfIncludedFiles(t *testing.T) {
	s := newScratch(t)
	// temp/bin is an included copy: listed in .worktreeinclude and ignored
	// in git, so the changed copy in the worktree never counts as
	// uncommitted work
	must(t, os.WriteFile(filepath.Join(s.main, ".worktreeinclude"), []byte("temp/bin\n"), 0o644))
	must(t, os.WriteFile(filepath.Join(s.main, ".gitignore"), []byte("temp/bin\n"), 0o644))
	git(t, s.main, "add", ".gitignore", ".worktreeinclude")
	git(t, s.main, "commit", "--quiet", "--message", "include list")
	must(t, os.MkdirAll(filepath.Join(s.main, "temp"), 0o755))
	must(t, os.WriteFile(filepath.Join(s.main, "temp", "bin"), []byte("copy of main"), 0o644))
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	must(t, os.MkdirAll(filepath.Join(tree, "temp"), 0o755))
	must(t, os.WriteFile(filepath.Join(tree, "temp", "bin"), []byte("changed copy"), 0o644))
	code, _, stderr := s.run("close", tree)
	if spec.ExitCode(code) != spec.GeneralError {
		t.Fatalf("exit = %d, want %d: %s", code, spec.GeneralError, stderr)
	}
	if !strings.Contains(stderr, tree+" has included files that differ from main") {
		t.Errorf("stderr names no worktree: %q", stderr)
	}
	if !strings.Contains(stderr, filepath.Join(tree, "temp", "bin")) {
		t.Errorf("stderr lists no path inside the worktree: %q", stderr)
	}
	if _, err := os.Stat(tree); err != nil {
		t.Errorf("a refused close removed the worktree")
	}
}

func TestCloseRemovesMergedBranchAndWritesCDFile(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	// run from inside the worktree, so the cd protocol fires
	restore := chdir(t, tree)
	cdFile := filepath.Join(s.home, "cdfile")
	t.Setenv("PROJECT_CD_FILE", cdFile)
	code, _, stderr := s.run("close", tree)
	restore()
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Errorf("the worktree survived close")
	}
	if gitBackend.RefExists(s.main, "refs/heads/feat/x") {
		t.Errorf("the merged branch survived close")
	}
	raw, err := os.ReadFile(cdFile)
	must(t, err)
	if strings.TrimSpace(string(raw)) != s.main {
		t.Errorf("cd file = %q, want %q", raw, s.main)
	}
}

func TestCloseKeepsUnmergedBranch(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	git(t, tree, "commit", "--quiet", "--allow-empty", "--message", "work")
	t.Setenv("PROJECT_CD_FILE", "")
	code, _, stderr := s.run("close", tree)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Errorf("the worktree survived close")
	}
	if !gitBackend.RefExists(s.main, "refs/heads/feat/x") {
		t.Errorf("close deleted an unmerged branch")
	}
	if !strings.Contains(stderr, "kept branch feat/x") {
		t.Errorf("stderr = %q", stderr)
	}
}

func TestCleanClosesMergedAndDeletesLoose(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	// real work on both branches, merged into main: a branch with only its
	// creation in the reflog has no work yet, and clean skips it
	git(t, tree, "commit", "--quiet", "--allow-empty", "--message", "work")
	git(t, s.main, "merge", "--quiet", "--ff-only", "feat/x")
	git(t, s.main, "branch", "done")
	git(t, s.main, "checkout", "--quiet", "done")
	git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "more")
	git(t, s.main, "checkout", "--quiet", "main")
	git(t, s.main, "merge", "--quiet", "--ff-only", "done")
	code, _, stderr := s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if gitBackend.RefExists(s.main, "refs/heads/done") {
		t.Errorf("the loose merged branch survived clean")
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Errorf("the merged worktree survived clean")
	}
	if gitBackend.RefExists(s.main, "refs/heads/feat/x") {
		t.Errorf("the merged worktree branch survived clean")
	}
}

// -------------------------------------------------- the finished review leg

// reviewScratch builds the review-leg shape of the dispatcher: an origin
// that answers, a worker branch pushed as a pull request head, and reviewer
// branches pointed at the worker tip with plain git, with the worker branch
// as upstream (issue #130). The reviewer commits nothing, so each reviewer
// branch holds only its creation in the reflog.
func reviewScratch(t *testing.T) *scratch {
	t.Helper()
	s := newScratch(t)
	remote := filepath.Join(s.home, "remote", "demo.git")
	must(t, os.MkdirAll(filepath.Dir(remote), 0o755))
	git(t, filepath.Dir(remote), "init", "--quiet", "--bare", "--initial-branch", "main", "demo.git")
	git(t, s.main, "remote", "add", "origin", remote)
	git(t, s.main, "push", "--quiet", "origin", "main")
	// the worker branch: one commit ahead of main, pushed
	git(t, s.main, "checkout", "--quiet", "-b", "ai/issue-121")
	git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "work")
	git(t, s.main, "checkout", "--quiet", "main")
	git(t, s.main, "push", "--quiet", "origin", "ai/issue-121")
	// the reviewer branch with a worktree, and one without, both the way
	// the dispatcher makes them: pointed at the worker tip, upstream set
	for _, branch := range []string{"ai/review-127", "ai/review-129"} {
		git(t, s.main, "branch", "-f", branch, "refs/remotes/origin/ai/issue-121")
		git(t, s.main, "branch", "--set-upstream-to=origin/ai/issue-121", branch)
	}
	git(t, s.main, "worktree", "add", "--quiet", filepath.Join(s.dir, "ai-review-129"), "ai/review-129")
	return s
}

func TestCleanRemovesFinishedReviewLeg(t *testing.T) {
	s := reviewScratch(t)
	tree := filepath.Join(s.dir, "ai-review-129")
	// the forge merges the pull request and deletes the worker branch on
	// the remote, so the upstream of each reviewer branch reads gone
	git(t, s.main, "merge", "--quiet", "--no-ff", "-m", "merge the pull request", "ai/issue-121")
	git(t, s.main, "push", "--quiet", "origin", "main")
	git(t, s.main, "push", "--quiet", "origin", "--delete", "ai/issue-121")

	// dry-run prints the steps and changes nothing
	code, stdout, stderr := s.run("clean", "--dry-run", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("dry-run exit = %d: %s", code, stderr)
	}
	for _, want := range []string{
		"would close " + tree + " and delete branch ai/review-129",
		"would delete branch ai/review-127",
	} {
		if !strings.Contains(stdout, want) {
			t.Errorf("dry-run stdout = %q, want %q", stdout, want)
		}
	}
	if _, err := os.Stat(tree); err != nil {
		t.Fatalf("dry-run removed the worktree: %v", err)
	}
	for _, branch := range []string{"ai/review-127", "ai/review-129"} {
		if !gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Fatalf("dry-run removed branch %s", branch)
		}
	}

	code, _, stderr = s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Errorf("the finished review worktree survived clean")
	}
	for _, branch := range []string{"ai/review-127", "ai/review-129"} {
		if gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("the finished review branch %s survived clean", branch)
		}
	}
}

func TestCleanKeepsReviewLegThatDidNotFinish(t *testing.T) {
	s := reviewScratch(t)
	tree := filepath.Join(s.dir, "ai-review-129")
	// the pull request is merged, but the remote worker branch still
	// exists: the upstream of the reviewer branches is not gone
	git(t, s.main, "merge", "--quiet", "--no-ff", "-m", "merge the pull request", "ai/issue-121")
	git(t, s.main, "push", "--quiet", "origin", "main")
	// a claim that no session started: a new branch from origin/main with
	// --no-track, so it has no upstream and only its creation in the
	// reflog, while its tip is an ancestor of main and merely looks merged
	git(t, s.main, "fetch", "--quiet", "origin")
	git(t, s.main, "worktree", "add", "--quiet", "--no-track", "-b", "ai/issue-130", filepath.Join(s.dir, "ai-issue-130"), "origin/main")

	code, _, stderr := s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	for _, branch := range []string{"ai/review-127", "ai/review-129", "ai/issue-130"} {
		if !gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("clean deleted %s, which holds only its creation", branch)
		}
	}
	for _, path := range []string{tree, filepath.Join(s.dir, "ai-issue-130")} {
		if _, err := os.Stat(path); err != nil {
			t.Errorf("clean removed the worktree of a leg that did not finish: %v", err)
		}
	}
}

// --------------------------------------------------- the closed forge work

// fakeTea puts a tea script on PATH that answers the three list calls of
// clean with one fixed forge state.
func fakeTea(t *testing.T, home string) {
	t.Helper()
	bin := filepath.Join(home, "bin")
	must(t, os.MkdirAll(bin, 0o755))
	script := `#!/bin/sh
case "$1 $2 $4" in
"pulls list closed")
	echo '[{"index":"207","state":"closed","head":"ai/issue-198"},{"index":"206","state":"merged","head":"ai/issue-204"},{"index":"175","state":"closed","head":"ai/issue-174"},{"index":"171","state":"closed","head":"ai/issue-173"}]'
	;;
"pulls list open")
	echo '[{"index":"214","state":"open","head":"ai/issue-205"}]'
	;;
"issues list closed")
	echo '[{"index":"209","title":"the rework","state":"closed"},{"index":"205","title":"the other fix","state":"closed"},{"index":"211","title":"the attempt that never pushed","state":"closed"}]'
	;;
esac
`
	must(t, os.WriteFile(filepath.Join(bin, "tea"), []byte(script), 0o755))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// failingTea puts a tea script on PATH that fails every call.
func failingTea(t *testing.T, home string) {
	t.Helper()
	bin := filepath.Join(home, "bin")
	must(t, os.MkdirAll(bin, 0o755))
	must(t, os.WriteFile(filepath.Join(bin, "tea"), []byte("#!/bin/sh\nexit 1\n"), 0o755))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// closedScratch builds the shape of issue #210: an origin that answers, one
// worker branch per decision case, each with one commit, its push, its
// upstream, and its worktree, and the reviewer branch ai/review-207 of pull
// request #207 the way the dispatcher makes it. The fake tea of the fixture
// reports the forge state that the tests below name.
//
//	ai/issue-198  pull request #207 closed without a merge      goes
//	ai/review-207 the review of pull request #207               goes
//	ai/issue-209  issue #209 closed, no pull request of its own goes
//	ai/issue-205  issue #205 closed, but pull request #214 is
//	              still open on its head                       stays
//	ai/issue-204  pull request #206 merged                      stays
func closedScratch(t *testing.T) *scratch {
	t.Helper()
	s := newScratch(t)
	remote := filepath.Join(s.home, "remote", "demo.git")
	must(t, os.MkdirAll(filepath.Dir(remote), 0o755))
	git(t, filepath.Dir(remote), "init", "--quiet", "--bare", "--initial-branch", "main", "demo.git")
	git(t, s.main, "remote", "add", "origin", remote)
	git(t, s.main, "push", "--quiet", "origin", "main")
	for _, branch := range []string{"ai/issue-198", "ai/issue-209", "ai/issue-205", "ai/issue-204"} {
		git(t, s.main, "checkout", "--quiet", "-b", branch)
		git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "work")
		git(t, s.main, "push", "--quiet", "origin", branch)
		git(t, s.main, "branch", "--set-upstream-to=origin/"+branch, branch)
	}
	// the reviewer branch of the dispatcher: pointed at the worker tip with
	// plain git, the worker branch as upstream
	git(t, s.main, "branch", "ai/review-207", "refs/remotes/origin/ai/issue-198")
	git(t, s.main, "branch", "--set-upstream-to=origin/ai/issue-198", "ai/review-207")
	git(t, s.main, "checkout", "--quiet", "main")
	for _, branch := range []string{"ai/issue-198", "ai/issue-209", "ai/issue-205", "ai/issue-204", "ai/review-207"} {
		git(t, s.main, "worktree", "add", "--quiet", filepath.Join(s.dir, strings.ReplaceAll(branch, "/", "-")), branch)
	}
	fakeTea(t, s.home)
	return s
}

// One run of project clean with no flag closes the worktrees and deletes
// the branches of the work that the forge shows closed: the head branch and
// the review branch of a pull request that closed without a merge, and the
// branch of an issue that closed with no pull request of its own. An open
// pull request keeps its head branch, and a merged pull request claims
// nothing (issue #210).
func TestCleanClosesClosedForgeWork(t *testing.T) {
	s := closedScratch(t)
	gone := map[string]string{
		"ai/issue-198":  filepath.Join(s.dir, "ai-issue-198"),
		"ai/review-207": filepath.Join(s.dir, "ai-review-207"),
		"ai/issue-209":  filepath.Join(s.dir, "ai-issue-209"),
	}
	stays := map[string]string{
		"ai/issue-205": filepath.Join(s.dir, "ai-issue-205"),
		"ai/issue-204": filepath.Join(s.dir, "ai-issue-204"),
	}

	// dry-run lists the closed-entity steps and changes nothing
	code, stdout, stderr := s.run("clean", "--dry-run", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("dry-run exit = %d: %s", code, stderr)
	}
	for branch, tree := range gone {
		if !strings.Contains(stdout, "would close "+tree+" and delete branch "+branch) {
			t.Errorf("dry-run stdout misses %s: %q", branch, stdout)
		}
		if _, err := os.Stat(tree); err != nil {
			t.Fatalf("dry-run removed the worktree of %s: %v", branch, err)
		}
		if !gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Fatalf("dry-run removed the branch %s", branch)
		}
	}
	for branch := range stays {
		if strings.Contains(stdout, branch) {
			t.Errorf("dry-run stdout names the kept branch %s: %q", branch, stdout)
		}
	}

	code, _, stderr = s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	for branch, tree := range gone {
		if _, err := os.Stat(tree); !os.IsNotExist(err) {
			t.Errorf("the worktree of %s survived clean", branch)
		}
		if gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("the branch %s survived clean", branch)
		}
	}
	for branch, tree := range stays {
		if _, err := os.Stat(tree); err != nil {
			t.Errorf("clean removed the worktree of the kept branch %s: %v", branch, err)
		}
		if !gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("clean deleted the kept branch %s", branch)
		}
	}
}

// The unpushed-work guard of the closed-entity path: a branch ahead of its
// upstream stays and the run prints why, a branch that never pushed stays,
// and a branch whose remote branch is gone stays when its tip moved beyond
// the saved one. A branch at its saved upstream tip goes, and so does the
// rest of the closed work (issue #210).
func TestCleanKeepsUnpushedWorkOfClosedWork(t *testing.T) {
	s := closedScratch(t)
	remote := filepath.Join(s.home, "remote", "demo.git")
	// rework that no remote holds: the closed pull request cannot take it
	git(t, filepath.Join(s.dir, "ai-issue-198"), "commit", "--quiet", "--allow-empty", "--message", "unpushed rework")
	// a claimed branch that never pushed: it holds a commit no remote has
	git(t, s.main, "worktree", "add", "--quiet", "--no-track", "-b", "ai/issue-211", filepath.Join(s.dir, "ai-issue-211"), "main")
	git(t, filepath.Join(s.dir, "ai-issue-211"), "commit", "--quiet", "--allow-empty", "--message", "never pushed")
	// two claimed branches whose remote branch is gone: ai/issue-174 sits at
	// its saved upstream tip, ai/issue-173 moved beyond it
	for _, branch := range []string{"ai/issue-174", "ai/issue-173"} {
		git(t, s.main, "checkout", "--quiet", "-b", branch)
		git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "first attempt")
		git(t, s.main, "push", "--quiet", "origin", branch)
		git(t, s.main, "branch", "--set-upstream-to=origin/"+branch, branch)
		git(t, s.main, "checkout", "--quiet", "main")
		git(t, s.main, "worktree", "add", "--quiet", filepath.Join(s.dir, strings.ReplaceAll(branch, "/", "-")), branch)
		// the remote branch goes the way the forge removes it: without the
		// local clone knowing, so the fetch of clean prunes it
		git(t, remote, "branch", "-D", branch)
	}
	git(t, filepath.Join(s.dir, "ai-issue-173"), "commit", "--quiet", "--allow-empty", "--message", "beyond the remote tip")
	// a review worktree with uncommitted work stays open, and the run says so
	must(t, os.WriteFile(filepath.Join(s.dir, "ai-review-207", "note.txt"), []byte("review notes"), 0o644))

	code, _, stderr := s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	for branch, why := range map[string]string{
		"ai/issue-198": "kept ai/issue-198: pull request #207 closed without a merge, but its tip is ahead of refs/remotes/origin/ai/issue-198",
		"ai/issue-211": "kept ai/issue-211: issue #211 closed, but its work was never pushed",
		"ai/issue-173": "kept ai/issue-173: pull request #171 closed without a merge, but its remote branch is gone and it may hold unpushed work",
	} {
		if !strings.Contains(stderr, why) {
			t.Errorf("stderr misses the reason it kept %s: %q", branch, stderr)
		}
		if !gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("clean deleted %s, which holds unpushed work", branch)
		}
	}
	// the branch at its saved upstream tip goes, and so does the clean
	// closed work of the fixture
	for _, branch := range []string{"ai/issue-174", "ai/issue-209"} {
		if gitBackend.RefExists(s.main, "refs/heads/"+branch) {
			t.Errorf("the branch %s survived clean", branch)
		}
		if _, err := os.Stat(filepath.Join(s.dir, strings.ReplaceAll(branch, "/", "-"))); !os.IsNotExist(err) {
			t.Errorf("the worktree of %s survived clean", branch)
		}
	}
	// the dirty review worktree stays open, reported by its refusal
	if _, err := os.Stat(filepath.Join(s.dir, "ai-review-207")); err != nil {
		t.Errorf("clean removed the review worktree that holds uncommitted work: %v", err)
	}
	if !strings.Contains(stderr, filepath.Join(s.dir, "ai-review-207")+" has uncommitted work") {
		t.Errorf("stderr does not report the dirty review worktree: %q", stderr)
	}
	if !gitBackend.RefExists(s.main, "refs/heads/ai/review-207") {
		t.Errorf("clean deleted the branch of the worktree it kept open")
	}
}

// A tea that fails degrades to a warning: clean still cleans what git alone
// proves merged (issue #210).
func TestCleanWarnsWhenTeaFails(t *testing.T) {
	s := newScratch(t)
	failingTea(t, s.home)
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	git(t, tree, "commit", "--quiet", "--allow-empty", "--message", "work")
	git(t, s.main, "merge", "--quiet", "--ff-only", "feat/x")
	git(t, s.main, "branch", "done")
	git(t, s.main, "checkout", "--quiet", "done")
	git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "more")
	git(t, s.main, "checkout", "--quiet", "main")
	git(t, s.main, "merge", "--quiet", "--ff-only", "done")
	code, _, stderr := s.run("clean", s.dir)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stderr, "tea listed no open pull requests") {
		t.Errorf("stderr = %q", stderr)
	}
	if gitBackend.RefExists(s.main, "refs/heads/done") {
		t.Errorf("the loose merged branch survived clean")
	}
	if _, err := os.Stat(tree); !os.IsNotExist(err) {
		t.Errorf("the merged worktree survived clean")
	}
}

// ---------------------------------------------------------- the review flow

// reviewProject builds a project whose origin holds the head of one pull
// request. nextHead commits in main, pushes the commit as refs/pull/7/head,
// and returns its id, so a test moves the pull request forward the way a
// forge does.
func reviewProject(t *testing.T) (*scratch, func() string) {
	t.Helper()
	s := newScratch(t)
	remote := filepath.Join(s.home, "remote", "demo.git")
	must(t, os.MkdirAll(filepath.Dir(remote), 0o755))
	git(t, filepath.Dir(remote), "init", "--quiet", "--bare", "--initial-branch", "main", "demo.git")
	git(t, s.main, "remote", "add", "origin", remote)
	git(t, s.main, "push", "--quiet", "origin", "main")
	nextHead := func() string {
		git(t, s.main, "commit", "--quiet", "--allow-empty", "--message", "pull request head")
		git(t, s.main, "push", "--quiet", "origin", "HEAD:refs/pull/7/head")
		return strings.TrimSpace(git(t, s.main, "rev-parse", "HEAD"))
	}
	return s, nextHead
}

// The review sync is the whole state machine of the subcommand minus the
// ide window: a missing branch and worktree are made at the fetched head, a
// clean worktree follows a new head, a dirty one keeps its state, and a
// branch whose worktree closed moves to the current head before the new
// worktree checks it out.
func TestReviewSync(t *testing.T) {
	s, nextHead := reviewProject(t)
	branch := "review/pr-7"
	tree := filepath.Join(s.dir, "review-pr-7")
	var stderr bytes.Buffer
	headOf := func() string {
		return gitBackend.ResolveRef(s.main, "refs/heads/"+branch)
	}

	head := nextHead()
	if toolErr := reviewSync(&stderr, s.dir, branch, 7); toolErr != nil {
		t.Fatalf("first sync: %v", toolErr)
	}
	if got := headOf(); got != head {
		t.Fatalf("branch = %s, want the fetched head %s", got, head)
	}
	if info, err := os.Stat(tree); err != nil || !info.IsDir() {
		t.Fatalf("the review worktree is missing: %v", err)
	}

	head = nextHead()
	if toolErr := reviewSync(&stderr, s.dir, branch, 7); toolErr != nil {
		t.Fatalf("second sync: %v", toolErr)
	}
	if got := headOf(); got != head {
		t.Fatalf("branch = %s after a new head, want %s", got, head)
	}

	dirty := filepath.Join(tree, "uncommitted")
	must(t, os.WriteFile(dirty, []byte("work"), 0o644))
	stale := headOf()
	nextHead()
	stderr.Reset()
	if toolErr := reviewSync(&stderr, s.dir, branch, 7); toolErr != nil {
		t.Fatalf("third sync: %v", toolErr)
	}
	if got := headOf(); got != stale {
		t.Errorf("a dirty worktree must keep its head: %s, want %s", got, stale)
	}
	if !strings.Contains(stderr.String(), "uncommitted work") {
		t.Errorf("stderr = %q, want the warning about uncommitted work", stderr.String())
	}
	if _, err := os.Stat(dirty); err != nil {
		t.Errorf("the uncommitted file is gone: %v", err)
	}

	// the closed review: the branch stays without its worktree, and the next
	// run moves it to the current head before the worktree comes back
	must(t, os.Remove(dirty))
	git(t, s.main, "worktree", "remove", tree)
	head = nextHead()
	if toolErr := reviewSync(&stderr, s.dir, branch, 7); toolErr != nil {
		t.Fatalf("sync after close: %v", toolErr)
	}
	if got := headOf(); got != head {
		t.Fatalf("branch = %s after close, want the current head %s", got, head)
	}
	if info, err := os.Stat(tree); err != nil || !info.IsDir() {
		t.Fatalf("the worktree did not come back: %v", err)
	}
}

func TestReviewArguments(t *testing.T) {
	s := newScratch(t)
	for _, argv := range [][]string{{"review"}, {"review", "abc"}, {"review", "0"}, {"review", "--all"}} {
		code, _, stderr := s.run(argv...)
		if spec.ExitCode(code) != spec.ArgError {
			t.Errorf("%v exit = %d: %s, want the argument error", argv, code, stderr)
		}
	}
	code, _, stderr := s.run("review", filepath.Join(s.home, "projects", "nope"), "7")
	if spec.ExitCode(code) != spec.NotFound {
		t.Errorf("missing project exit = %d: %s", code, stderr)
	}
	// a fetch that cannot run makes the whole command unavailable: a review
	// needs the current head, and the run is retried
	git(t, s.main, "remote", "add", "origin", filepath.Join(s.home, "unreachable"))
	code, _, stderr = s.run("review", s.dir, "7")
	if spec.ExitCode(code) != spec.Unavailable {
		t.Errorf("unreachable origin exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stderr, "couldn't fetch refs/pull/7/head") {
		t.Errorf("stderr = %q, want the fetch failure", stderr)
	}
}

// ------------------------------------------------------------------- convert

func TestConvertMovesRepoIntoMain(t *testing.T) {
	s := newScratch(t)
	repo := filepath.Join(s.home, "projects", "plain")
	must(t, os.MkdirAll(repo, 0o755))
	git(t, repo, "init", "--quiet", "--initial-branch", "main")
	git(t, repo, "commit", "--quiet", "--allow-empty", "--message", "initial")
	cdFile := filepath.Join(s.home, "cdfile")
	t.Setenv("PROJECT_CD_FILE", cdFile)
	// run from inside the repo, so the cd protocol fires
	restore := chdir(t, repo)
	code, _, stderr := s.run("convert", repo)
	restore()
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	if _, err := os.Stat(filepath.Join(repo, "main", ".git")); err != nil {
		t.Fatalf("convert left no main/.git: %v", err)
	}
	if raw, err := os.ReadFile(cdFile); err != nil || strings.TrimSpace(string(raw)) != filepath.Join(repo, "main") {
		t.Errorf("cd file = %q (%v)", raw, err)
	}
	// the converted project is a project now
	if !isProjectDir(repo) {
		t.Errorf("the converted repo is not a project")
	}
}

// -------------------------------------------------------- the settings freeze

// The settings JSON that a spawn passes to claude must match the frozen
// bytes: this drives the whole assembly path, from the reads discovery to
// the marker order, and compares against the golden fixtures' builder.
func TestSpawnPrintSettingsMatchesFrozenShape(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	tree := filepath.Join(s.dir, "feat-x")
	gitDir, err := runCmd(tree, nil, "git", "rev-parse", "--absolute-git-dir")
	must(t, err)

	code, stdout, stderr := s.run("spawn", s.dir, "feat/x", "--headless", "--print-settings", "do nothing")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	got := strings.TrimSpace(stdout)

	reads := settings.DiscoverReads(gitDir, filepath.Join(s.main, ".git"))
	want := string(settings.Build(settings.Settings{
		MemoryDir:   filepath.Join(s.dir, ".claude", "memory"),
		Permissions: &settings.Permissions{Reads: reads, GitDir: filepath.Join(s.main, ".git")},
		Markers:     settings.SpawnMarkers(true),
		PlanName:    "",
	}))
	if got != want {
		at := 0
		for at < len(got) && at < len(want) && got[at] == want[at] {
			at++
		}
		end := at + 60
		if end > len(got) {
			end = len(got)
		}
		t.Errorf("settings bytes differ at %d of %d/%d\n got: %q\nwant: %q", at, len(got), len(want), got[at:end], want[at:end])
	}
	// the spawn markers in the frozen order and form, and the absolute-path
	// session rules with their leading //
	for _, needle := range []string{
		`"PROJECT_HEADLESS_SESSION":"1","PROJECT_SPAWN_SESSION":"1","PROJECT_PLAN":""`,
		`"Read(/` + gitDir + `)"`,
		`"Read(/` + gitDir + `/**)"`,
		`"Bash(ls ` + s.main + `/.git)"`,
		`"Edit(/` + s.main + `/.git)"`,
	} {
		if !strings.Contains(got, needle) {
			t.Errorf("settings miss %q", needle)
		}
	}
	// the worktree metadata allow rule comes first, main/.git entries after
	// it, and the worktrees/ directory of another worktree is absent
	firstAllow := strings.Index(got, `"allow":["Read(/`)
	if firstAllow < 0 || !strings.HasPrefix(got[firstAllow+len(`"allow":["Read(/`):], gitDir) {
		window := got
		if len(window) > 260 {
			window = window[:260]
		}
		t.Errorf("the first allow rule is not the worktree git dir (gitDir %q): %q", gitDir, window)
	}
	if strings.Contains(got, `/main/.git/worktrees/**","Read(//`) {
		t.Errorf("the allow rules include the worktrees directory itself: %s", got)
	}
}

// --print-settings answers the open paths too and stops before any window
// opens: the main path carries no permission block, the branch path carries
// the per-worktree reads. The spawn tests above pin the third path.
func TestOpenPrintSettings(t *testing.T) {
	s := newScratch(t)
	code, stdout, stderr := s.run("open", s.dir, "--print-settings")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("open main exit = %d: %s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if !strings.Contains(got, `"autoMemoryDirectory":"`+filepath.Join(s.dir, ".claude", "memory")+`"`) {
		t.Errorf("the main settings miss the memory directory: %s", got)
	}
	if strings.Contains(got, "permissions") {
		t.Errorf("the main path carries a permission block: %s", got)
	}

	s.run("add", s.dir, "feat/x")
	code, stdout, stderr = s.run("open", s.dir, "feat/x", "--print-settings")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("open branch exit = %d: %s", code, stderr)
	}
	got = strings.TrimSpace(stdout)
	if !strings.Contains(got, `"permissions":{"allow"`) {
		t.Errorf("the branch path carries no permission block: %s", got)
	}
}

// A plan file reaches the settings through the plan directory of the
// environment, with its env in file order and the token helper quoted.
func TestSpawnPrintSettingsWithPlan(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	token := filepath.Join(s.home, "token")
	must(t, os.WriteFile(token, []byte("tok"), 0o600))
	plans := filepath.Join(s.home, ".config", "project", "plans")
	must(t, os.MkdirAll(plans, 0o755))
	must(t, os.WriteFile(filepath.Join(plans, "zai.json"), []byte(
		`{"env":{"ANTHROPIC_BASE_URL":"https://example/api","ANTHROPIC_DEFAULT_SONNET_MODEL":"m"},"tokenFile":"`+token+`"}`), 0o644))

	code, stdout, stderr := s.run("spawn", s.dir, "feat/x", "--headless", "--plan", "zai", "--print-settings", "x")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d: %s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	for _, needle := range []string{
		`"ANTHROPIC_BASE_URL":"https://example/api"`,
		`"apiKeyHelper":"cat '` + token + `'"`,
		`"PROJECT_PLAN":"zai"`,
	} {
		if !strings.Contains(got, needle) {
			t.Errorf("settings miss %s", needle)
		}
	}
	// an unknown plan stops before any session starts
	code, _, _ = s.run("spawn", s.dir, "feat/x", "--headless", "--plan", "nope", "--print-settings", "x")
	if spec.ExitCode(code) != spec.NotFound {
		t.Errorf("unknown plan exit = %d, want %d", code, spec.NotFound)
	}
}

// ---------------------------------------------------------------- completions

func TestCompletionProtocol(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")

	// the projects of ~/projects, one line each: the completed tokens, then
	// the token under the cursor after --
	code, stdout, _ := s.run("__complete", "project", "open", "--", "")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	if strings.TrimSpace(stdout) != "demo\tproject" {
		t.Errorf("project completions = %q", stdout)
	}
	// a partial project name still completes the projects
	code, stdout, _ = s.run("__complete", "project", "open", "--", "de")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	if strings.TrimSpace(stdout) != "demo\tproject" {
		t.Errorf("partial project completions = %q", stdout)
	}

	// the branches of a project: the worktree first, then loose branches,
	// then remote ones, never the branch that main/ has checked out
	git(t, s.main, "branch", "loose")
	code, stdout, _ = s.run("__complete", "project", "open", "demo", "--", "")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	want := []string{
		"feat/x\tworktree feat-x",
		"loose\tbranch",
	}
	if len(lines) != len(want) {
		t.Fatalf("branch completions = %q", lines)
	}
	for i := range want {
		if lines[i] != want[i] {
			t.Errorf("completion %d = %q, want %q", i, lines[i], want[i])
		}
	}

	// --from also lists the branch of main/ itself: it resolves the project
	// of the current directory, and from-mode lists main's own worktree
	restore := chdir(t, s.dir)
	code, stdout, _ = s.run("__complete", "from")
	restore()
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	if !strings.Contains(stdout, "main\tworktree main") {
		t.Errorf("from completions = %q", stdout)
	}

	// close lists the worktrees of the project of the current directory
	restore = chdir(t, s.dir)
	code, stdout, _ = s.run("__complete", "project", "close", "--", "")
	restore()
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	if strings.TrimSpace(stdout) != "feat-x\tbranch feat/x" {
		t.Errorf("close completions = %q", stdout)
	}

	// the plan mode lists none and every plan file, in the fish format
	code, stdout, _ = s.run("__complete", "plan")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d", code)
	}
	if !strings.HasPrefix(stdout, "none\tstart without a plan\n") {
		t.Errorf("plan completions = %q", stdout)
	}
}

// --------------------------------------------------------- the window paths

// The on-screen paths of issue #520 run against a fake tmux that logs every
// call: a local shell attaches the session in its own terminal and switches
// its tmux client, and a shell behind the socket forward of a remote host
// window keeps its client where it is. The wezterm calls of the forward
// paths fail at the exec in these tests (see fakeTmux), so the tab
// mechanics of the machinery stay with their own finders (wezterm_test.go)
// and with the manual test steps of issue 520; here the tests pin which
// branch of the window paths each shell class takes.

// fakeTmux gives the scratch a private PATH whose tmux is a fake: it logs
// every call, answers the display formats and the window options from the
// answer files that the tests plant, counts the panes of its -P calls, and
// adds each new-session to the window table that list-windows reads. A
// command that carries the
// darwin -N prefix answers as one without it, so one run of the tests covers
// darwin, where no client may start the launchd-owned server, and Linux
// alike. git and cat stay real. env
// stays out on purpose: every wezterm call of the window layer goes through
// `env`, so it fails at the exec and no test run can reach the wezterm of a
// GUI host, which would answer with a window of its own (a fake wezterm on
// PATH cannot win: the sanitized environment of a forward names the system
// directories first, issue 160).
func (s *scratch) fakeTmux(t *testing.T) string {
	t.Helper()
	bin := t.TempDir()
	script := `#!/bin/sh
# the fake tmux: the target sits after -t, the format is the last word
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
# darwin sends new-session and start-server behind -N, so no client starts a
# server that launchd owns (docs/cli.md): the log keeps the full command, and
# the dispatch answers the command behind the flag exactly as one without it
if [ "$1" = "-N" ]; then
  shift
fi
target=
prev=
for a in "$@"; do
  if [ "$prev" = "-t" ]; then
    target=$a
  fi
  prev=$a
done
case "$1" in
display-message)
  eval "fmt=\$$#"
  if [ -f "$FAKE_TMUX_ANSWERS/$target/$fmt" ]; then
    cat "$FAKE_TMUX_ANSWERS/$target/$fmt"
  elif [ "$fmt" = '#{pid}-#{pane_id}' ]; then
    printf '4211-%s\n' "$target"
  fi
  exit 0
  ;;
show-option)
  eval "opt=\$$#"
  if [ -f "$FAKE_TMUX_ANSWERS/$target/$opt" ]; then
    cat "$FAKE_TMUX_ANSWERS/$target/$opt"
  fi
  exit 0
  ;;
has-session)
  exit 1
  ;;
list-windows)
  cat "$FAKE_TMUX_WINDOWS"
  exit 0
  ;;
new-session | split-window)
  case " $* " in
  *" -P "*)
    n=$(cat "$FAKE_TMUX_PANES" 2>/dev/null || printf '0')
    n=$((n + 1))
    printf '%s' "$n" > "$FAKE_TMUX_PANES"
    printf '%%%d\n' "$n"
    ;;
  esac
  if [ "$1" = "new-session" ]; then
    d=
    prev=
    for a in "$@"; do
      if [ "$prev" = "-c" ]; then
        d=$a
      fi
      prev=$a
    done
    printf '@1 %s\n' "$d" >> "$FAKE_TMUX_WINDOWS"
  fi
  exit 0
  ;;
esac
exit 0
`
	must(t, os.WriteFile(filepath.Join(bin, "tmux"), []byte(script), 0o755))
	for _, name := range []string{"git", "cat"} {
		path, err := exec.LookPath(name)
		if err != nil {
			t.Skipf("%s is not available", name)
		}
		must(t, os.Symlink(path, filepath.Join(bin, name)))
	}
	t.Setenv("PATH", bin)
	// no inherited login state: the forward tests set their own, and the
	// delegation marker of a session that runs the tests would turn every
	// ideOpen into a remote half
	t.Setenv("SSH_CONNECTION", "")
	t.Setenv("WEZTERM_UNIX_SOCKET", "")
	t.Setenv("PROJECT_GUI_SOCKET", "")
	t.Setenv("PROJECT_REMOTE_ARGV", "")
	t.Setenv("FAKE_TMUX_LOG", filepath.Join(bin, "tmux.log"))
	t.Setenv("FAKE_TMUX_ANSWERS", filepath.Join(bin, "answers"))
	t.Setenv("FAKE_TMUX_PANES", filepath.Join(bin, "panes"))
	t.Setenv("FAKE_TMUX_WINDOWS", filepath.Join(bin, "windows"))
	must(t, os.MkdirAll(filepath.Join(bin, "answers"), 0o755))
	must(t, os.WriteFile(filepath.Join(bin, "windows"), nil, 0o644))
	return filepath.Join(bin, "tmux.log")
}

// tmuxAnswer plants the answer of one display format or window option for one
// target, the empty target naming the current session or pane.
func (s *scratch) tmuxAnswer(t *testing.T, target, format, answer string) {
	t.Helper()
	dir := filepath.Join(os.Getenv("FAKE_TMUX_ANSWERS"), target)
	must(t, os.MkdirAll(dir, 0o755))
	must(t, os.WriteFile(filepath.Join(dir, format), []byte(answer), 0o644))
}

// forwardShell puts the environment of a shell behind the socket forward of
// a remote host window in place: the login came over ssh, WEZTERM_UNIX_SOCKET
// names a socket, and PROJECT_GUI_SOCKET names the socket of the GUI on the
// machine that owns the window, in a home form so the sanitized environment
// of a forward derives HOME and USER from it (issue #160). The socket
// refuses connections, so a wezterm call that does escape the tests fails
// fast instead of waiting on a socket that no test answers. Its path stays
// short: darwin caps a socket path at 104 bytes, the directory of t.TempDir
// names the test, and both temp roots the suite runs under — the plain
// TMPDIR of darwin and the sandbox of the nix build — are deep enough to
// overflow that cap with the test name in the path.
func forwardShell(t *testing.T) {
	t.Helper()
	dir, err := os.MkdirTemp("", "gui")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	path := filepath.Join(dir, "sock")
	fd, err := syscall.Socket(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(fd)
	if err := syscall.Bind(fd, &syscall.SockaddrUnix{Name: path}); err != nil {
		t.Fatal(err)
	}
	if err := syscall.Listen(fd, 1); err != nil {
		t.Fatal(err)
	}
	// the closed listener leaves the socket file behind: isSocket still
	// answers true, and a connect answers ECONNREFUSED
	t.Setenv("SSH_CONNECTION", "10.0.0.4 4242 10.0.0.9 22")
	t.Setenv("WEZTERM_UNIX_SOCKET", path)
	home := t.TempDir()
	t.Setenv("PROJECT_GUI_SOCKET", filepath.Join(home, ".local", "share", "wezterm", "gui-sock-9"))
}

// fakeWezterm adds a fake wezterm beside the fake tmux, so guiTabReachable
// finds one on PATH. It never runs: every wezterm call of the window layer
// goes through env, which the private PATH of fakeTmux holds no entry for.
func (s *scratch) fakeWezterm(t *testing.T) {
	t.Helper()
	path := filepath.Join(filepath.Dir(os.Getenv("FAKE_TMUX_LOG")), "wezterm")
	_ = os.Remove(path)
	must(t, os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o755))
}

// fakeEnv puts a fake env beside the fake tmux and returns the path of its
// log. The window layer runs every wezterm call through env, so the fake
// records each full call and answers the two calls whose output the layer
// reads: one desktop pane for list, a pane id for spawn. The wezterm of the
// machine never runs — exec resolves env against the PATH of the test, and
// the fake answers every call itself (the env note of fakeTmux) — so a test
// reads the tab commands that the layer built, ssh line included, from the
// log alone.
func (s *scratch) fakeEnv(t *testing.T) string {
	t.Helper()
	bin := filepath.Dir(os.Getenv("FAKE_TMUX_LOG"))
	log := filepath.Join(bin, "env.log")
	t.Setenv("FAKE_ENV_LOG", log)
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_ENV_LOG"
case "$*" in
*" cli list --format json"*)
	printf '[{"pane_id":9,"tab_id":1,"window_id":1,"tab_title":"fresh","window_title":"no window"}]'
	;;
*" spawn "*)
	printf '9\n'
	;;
esac
exit 0
`
	must(t, os.WriteFile(filepath.Join(bin, "env"), []byte(script), 0o755))
	return log
}

// readLog reads what a fake binary logged.
func readLog(t *testing.T, path string) string {
	t.Helper()
	out, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

// A local shell and a plain ssh login bring an ide window of another
// session in front of their client: select-window and switch-client, and no
// WezTerm tab, because the local half of the window layer is gone (issue
// #520). A plain ssh login took this path before the change; the local one
// traded its tab for it.
func TestSwitchToWindowSwitchesTheClient(t *testing.T) {
	s := newScratch(t)
	log := s.fakeTmux(t)
	s.tmuxAnswer(t, "@1", "#{session_attached}", "0")
	for _, tc := range []struct{ name, ssh string }{
		{"a local shell", ""},
		{"a plain ssh login", "10.0.0.4 4242 10.0.0.9 22"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("SSH_CONNECTION", tc.ssh)
			var stderr bytes.Buffer
			if err := switchToWindow(&stderr, "@1"); err != nil {
				t.Fatalf("switchToWindow = %v", err)
			}
			out := readLog(t, log)
			if !strings.Contains(out, "select-window -t @1") || !strings.Contains(out, "switch-client -t @1") {
				t.Errorf("the client did not switch: %q", out)
			}
			if stderr.Len() != 0 {
				t.Errorf("a switch printed a diagnostic: %q", stderr.String())
			}
		})
	}
}

// Behind the socket forward of a remote host window the GUI shows the
// session, and the client of the caller stays on its own session whatever
// the session shows: a terminal that already shows the session keeps the
// window selected with a diagnostic, and one that does not leaves the tab
// to the GUI layer. Neither case switches this client (issue #141).
func TestSwitchToWindowBehindForwardKeepsTheClient(t *testing.T) {
	s := newScratch(t)
	tmuxLog := s.fakeTmux(t)
	for _, tc := range []struct {
		name     string
		attached string
		diag     string
	}{
		{"a terminal shows the session", "1", "already open in tmux session demo"},
		{"no terminal shows the session", "0", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			forwardShell(t)
			s.fakeWezterm(t)
			s.tmuxAnswer(t, "@1", "#{session_attached}", tc.attached)
			s.tmuxAnswer(t, "@1", "#{session_id}", "$0")
			s.tmuxAnswer(t, "@1", "#S", "demo")
			var stderr bytes.Buffer
			if err := switchToWindow(&stderr, "@1"); err != nil {
				t.Fatalf("switchToWindow = %v", err)
			}
			out := readLog(t, tmuxLog)
			if !strings.Contains(out, "select-window -t @1") {
				t.Errorf("the window was not selected: %q", out)
			}
			if strings.Contains(out, "switch-client") {
				t.Errorf("the client switched behind a forward: %q", out)
			}
			if tc.diag != "" && !strings.Contains(stderr.String(), tc.diag) {
				t.Errorf("a shown session named no diagnostic: %q", stderr.String())
			}
		})
	}
}

// A local shell outside tmux attaches the session of `project open` in the
// current terminal: the build ends in a foreground tmux attach, and no
// WezTerm call runs (issue #520).
func TestIdeOpenLocalAttachesInTheTerminal(t *testing.T) {
	s := newScratch(t)
	log := s.fakeTmux(t)
	var stderr bytes.Buffer
	if err := ideOpen(&stderr, "demo", s.dir, "", s.main, nil); err != nil {
		t.Fatalf("ideOpen = %v", err)
	}
	out := readLog(t, log)
	if !strings.Contains(out, "new-session -d -P") {
		t.Errorf("no session was built: %q", out)
	}
	if !strings.Contains(out, "attach -t =demo") {
		t.Errorf("the session did not attach in this terminal: %q", out)
	}
	if stderr.Len() != 0 {
		t.Errorf("the attach printed a diagnostic: %q", stderr.String())
	}
}

// Inside tmux, `project open` on a project whose session sits elsewhere
// builds a detached session and then brings the new window in front of this
// client: select-window and switch-client, with no tab and no attach in
// this terminal (issue #520). A plain ssh login took this path before the
// change. The build prints no attach hint: the switch puts the window in
// front of the caller, so the person needs no command (issue 532).
func TestIdeOpenDetachedBuildSwitchesTheClient(t *testing.T) {
	s := newScratch(t)
	log := s.fakeTmux(t)
	t.Setenv("TMUX", "/tmp/tmux-0/default,4211,0")
	t.Setenv("TMUX_PANE", "%0")
	s.tmuxAnswer(t, "", "#S", "other")
	s.tmuxAnswer(t, "", "#{window_width}", "120")
	s.tmuxAnswer(t, "", "#{window_height}", "40")
	var stderr bytes.Buffer
	if err := ideOpen(&stderr, "demo", s.dir, "", s.main, nil); err != nil {
		t.Fatalf("ideOpen = %v", err)
	}
	out := readLog(t, log)
	if !strings.Contains(out, "new-session -d -P") {
		t.Errorf("no detached session was built: %q", out)
	}
	if !strings.Contains(out, "select-window -t @1") || !strings.Contains(out, "switch-client -t @1") {
		t.Errorf("the client did not switch to the new window: %q", out)
	}
	if strings.Contains(out, "attach -t") {
		t.Errorf("the detached build attached in this terminal: %q", out)
	}
	if strings.Contains(stderr.String(), "attach with") {
		t.Errorf("a switched client got an attach hint: %q", stderr.String())
	}
}

// A detached build on a shell that no GUI reaches prints the attach hint:
// the line names the command and claims nothing about WezTerm — the local
// tab path is gone by decision (issue #520), so the shell says nothing
// about the binary (issue 532). WezTerm sits on PATH, as on a machine with
// it installed; without a socket forward no GUI answers, so the hint fires
// the same way for a plain ssh login and a local shell.
func TestIdeDetachHintNamesTheAttachCommand(t *testing.T) {
	s := newScratch(t)
	s.fakeTmux(t)
	s.fakeWezterm(t)
	for _, tc := range []struct{ name, ssh string }{
		{"a local shell", ""},
		{"a plain ssh login", "10.0.0.4 4242 10.0.0.9 22"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("SSH_CONNECTION", tc.ssh)
			// each shell builds its own session: the refusal of a second
			// build on one window per checkout would answer for the hint
			must(t, os.WriteFile(os.Getenv("FAKE_TMUX_WINDOWS"), nil, 0o644))
			code, _, stderr := s.run("ide", "--detach", "demo", s.dir)
			if spec.ExitCode(code) != spec.Success {
				t.Fatalf("ide --detach exit = %d: %s", code, stderr)
			}
			if want := "ide: attach with `tmux attach -t =demo`"; !strings.Contains(stderr, want) {
				t.Errorf("stderr names no attach command: %q", stderr)
			}
			if strings.Contains(stderr, "WezTerm") {
				t.Errorf("stderr claims something about WezTerm: %q", stderr)
			}
		})
	}
}

// A shell behind the socket forward of a remote host window reaches the
// GUI, not its own terminal: with the open window of the checkout in a
// session that already has a client, the GUI layer alone answers for it,
// this terminal runs no attach and no switch, and the diagnostic names the
// session (issue #141 kept; issue #520 reverted the local half alone).
func TestIdeOpenBehindForwardReachesTheGui(t *testing.T) {
	s := newScratch(t)
	tmuxLog := s.fakeTmux(t)
	forwardShell(t)
	s.fakeWezterm(t)
	// the checkout already holds its ide window, and a client shows the
	// session
	must(t, os.WriteFile(os.Getenv("FAKE_TMUX_WINDOWS"), []byte("@1 "+s.main+"\n"), 0o644))
	s.tmuxAnswer(t, "@1", "#{session_attached}", "1")
	s.tmuxAnswer(t, "@1", "#S", "demo")
	var stderr bytes.Buffer
	if err := ideOpen(&stderr, "demo", s.dir, "", s.main, nil); err != nil {
		t.Fatalf("ideOpen = %v", err)
	}
	tmuxOut := readLog(t, tmuxLog)
	if strings.Contains(tmuxOut, "attach -t") || strings.Contains(tmuxOut, "switch-client") {
		t.Errorf("the forward shell moved its own terminal: %q", tmuxOut)
	}
	if !strings.Contains(stderr.String(), "session demo already has a client") {
		t.Errorf("the GUI layer answered for no session: %q", stderr.String())
	}
}

// The live session names of the attach path pass the denylist of the ruling
// on issue #382 before they reach the executed tab line (issue #568). The
// three consumers of weztermAttach behind a socket forward each hand it a
// name from outside this code — ideOpen and switchToWindow the session name
// that the tmux server reports, wezterm-attach the word that a person typed
// — and remoteSessionCommand puts the name unquoted into its line three
// times: the has-session target, the attach target, and the guard message.
// The fake env records every wezterm call of the layer, so the test reads
// the ssh tab line that the spawn of the session tab carried: every
// position holds the cleaned name, the raw name reaches no call, and the
// pinned tab title carries the same cleaned name, so the tab lookup and the
// guard message agree. The raw name holds three members of the class with
// the semicolon and the dollar as one run, the way the class walk of
// TestSessionNameDeniesTheRulingClass picks them.
func TestAttachPathNamesPassTheDenylistBehindAForward(t *testing.T) {
	s := newScratch(t)
	s.fakeTmux(t)
	const raw, clean = "ev'il;$x", "ev_il_x"
	for _, tc := range []struct{ name string }{
		{"ideOpen"},
		{"switchToWindow"},
		{"wezterm-attach"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			forwardShell(t)
			s.fakeWezterm(t)
			envLog := s.fakeEnv(t)
			// one case reads only its own calls
			must(t, os.WriteFile(envLog, nil, 0o644))
			// the checkout holds its ide window, in a session whose live
			// name holds bytes of the class; no client shows the session
			must(t, os.WriteFile(os.Getenv("FAKE_TMUX_WINDOWS"), []byte("@1 "+s.main+"\n"), 0o644))
			s.tmuxAnswer(t, "@1", "#{session_attached}", "0")
			s.tmuxAnswer(t, "@1", "#{session_id}", "$0")
			s.tmuxAnswer(t, "@1", "#S", raw)
			var stderr bytes.Buffer
			switch tc.name {
			case "ideOpen":
				if err := ideOpen(&stderr, "demo", s.dir, "", s.main, nil); err != nil {
					t.Fatalf("ideOpen = %v", err)
				}
			case "switchToWindow":
				if err := switchToWindow(&stderr, "@1"); err != nil {
					t.Fatalf("switchToWindow = %v", err)
				}
			default:
				code, _, stderrText := s.run("wezterm-attach", raw)
				if spec.ExitCode(code) != spec.Success {
					t.Fatalf("wezterm-attach exit = %d: %s", code, stderrText)
				}
			}
			out := readLog(t, envLog)
			if strings.Contains(out, raw) {
				t.Errorf("the raw name reached a wezterm call:\n%s", out)
			}
			for _, want := range []string{
				"tmux has-session -t =" + clean + " && tmux attach -t =" + clean,
				"tmux session " + clean + " is gone",
				"set-tab-title --tab-id 1 " + clean,
			} {
				if !strings.Contains(out, want) {
					t.Errorf("the tab calls miss %q:\n%s", want, out)
				}
			}
		})
	}
}

// The focus read of the follow names the session of the pane (issue 564): the
// @ide_editor option of the window names the pane, one display answers the
// window, the two flags of the focus, and the attached count of the session,
// and the guard binds only when all four answer for the pane. A display that
// answers both flags still answers no focus while no client sits in the
// session — the client switched to another session, or the session runs
// detached — because the flags are state of the session and stay set.
func TestEditorFocusReadsTheClientOfTheSession(t *testing.T) {
	s := newScratch(t)
	s.fakeTmux(t)
	s.tmuxAnswer(t, "@3", "@ide_editor", "%5")
	display := "#{window_id} #{window_active} #{pane_active} #{session_attached}"
	for _, tc := range []struct {
		name    string
		display string
		want    bool
	}{
		{"a client sits at the editor pane", "@3 1 1 1", true},
		{"a second client sits in the session", "@3 1 1 2", true},
		{"no client sits in the session", "@3 1 1 0", false},
		{"the display failed", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s.tmuxAnswer(t, "%5", display, tc.display)
			if got := editorFocus("@3"); got != tc.want {
				t.Errorf("editorFocus = %v, want %v", got, tc.want)
			}
		})
	}
	// a window without the @ide_editor option names no pane to ask
	if editorFocus("@4") {
		t.Errorf("editorFocus of a window without the editor option = true, want false")
	}
}

// ------------------------------------------------------------------- helpers

// The one constructor of the coded refusals: the exit code and the machine
// error code stay in step with each other as the caller passes them, and
// the message formats. The refusal tests of close pin the four call sites.
func TestErrWithCode(t *testing.T) {
	err := errWithCode(spec.PermissionDenied, "CLOSE_VETOED", "refused to close %s", "/demo/feat-x")
	if err.code != spec.PermissionDenied {
		t.Errorf("exit = %d, want %d", err.code, spec.PermissionDenied)
	}
	if err.err.Code != "CLOSE_VETOED" || err.err.Message != "refused to close /demo/feat-x" {
		t.Errorf("error = %+v", err.err)
	}
	if err.Error() != "refused to close /demo/feat-x" {
		t.Errorf("Error() = %q", err.Error())
	}
}

// The one direnv guard: no direnv on PATH and no .envrc answer absent, and
// an .envrc answers allowed or blocked as the direnv status of its
// directory says. The fake direnv decides through the marker file of the
// directory it runs in, which is what direnvStatusAllowed reads.
func TestEnvrcStateOf(t *testing.T) {
	s := newScratch(t)
	s.fakeBin(t, "direnv", "#!/bin/sh\nif [ -f allowed ]; then echo 'Found RC allowed 0'; else echo 'Found RC blocked'; fi\n")

	none := t.TempDir() // holds no .envrc
	allowed := t.TempDir()
	must(t, os.WriteFile(filepath.Join(allowed, ".envrc"), []byte("use flake\n"), 0o644))
	must(t, os.WriteFile(filepath.Join(allowed, "allowed"), nil, 0o644))
	blocked := t.TempDir()
	must(t, os.WriteFile(filepath.Join(blocked, ".envrc"), []byte("use flake\n"), 0o644))

	if got := envrcStateOf(none); got != envrcAbsent {
		t.Errorf("no .envrc = %v, want absent", got)
	}
	if got := envrcStateOf(allowed); got != envrcAllowed {
		t.Errorf("an allowed .envrc = %v, want allowed", got)
	}
	if got := envrcStateOf(blocked); got != envrcBlocked {
		t.Errorf("a blocked .envrc = %v, want blocked", got)
	}
	// no direnv on PATH: the .envrc plays no part
	s.fakeBin(t, "unused", "#!/bin/sh\n")
	if got := envrcStateOf(allowed); got != envrcAbsent {
		t.Errorf("no direnv on PATH = %v, want absent", got)
	}
}

// The one worktree-of-branch finder: the first worktree that holds the
// branch answers, the skipped path never answers, an empty skip lets every
// worktree answer, and no match is empty.
func TestWorktreeOfBranch(t *testing.T) {
	worktrees := []backend.Worktree{
		{Path: "/demo/main", Branch: "main"},
		{Path: "/demo/feat-x", Branch: "feat/x"},
		{Path: "/demo/feat-x-2", Branch: "feat/x"},
		{Path: "/demo/detached"},
	}
	if got := worktreeOfBranch(worktrees, "feat/x", "/demo/main"); got != "/demo/feat-x" {
		t.Errorf("worktreeOfBranch = %q, want the first match /demo/feat-x", got)
	}
	if got := worktreeOfBranch(worktrees, "main", "/demo/main"); got != "" {
		t.Errorf("the skipped path answered: %q", got)
	}
	if got := worktreeOfBranch(worktrees, "main", ""); got != "/demo/main" {
		t.Errorf("an empty skip must let main answer: %q", got)
	}
	if got := worktreeOfBranch(worktrees, "nope", ""); got != "" {
		t.Errorf("no match = %q, want empty", got)
	}
}

// The one merge-slot builder: the default branch the caller read beside the
// projectBase of the branch, and the refs of the slot follow from coord.
func TestMergeSlotOf(t *testing.T) {
	s := newScratch(t)
	s.run("add", s.dir, "feat/x")
	must(t, gitBackend.ConfigSet(s.main, "branch.feat/x.projectBase", "ui/trunk"))
	slot := mergeSlotOf(gitBackend, s.main, "feat/x", "main")
	if slot.DefaultBranch != "main" || slot.ProjectBase != "ui/trunk" {
		t.Fatalf("slot = %+v, want the base and the projectBase", slot)
	}
	// a branch with no projectBase config reads an empty one
	slot = mergeSlotOf(gitBackend, s.main, "feat/y", "main")
	if slot.ProjectBase != "" {
		t.Errorf("slot of a branch without a projectBase = %+v", slot)
	}
}

// The delegation payload carries the dir after the colon, never the
// user@host:dir argument itself, or the remote would parse it as another
// delegation target. Flags follow the positionals, and an inherited plan
// travels as an explicit --plan.
func TestDelegationPayloadLayout(t *testing.T) {
	newScratch(t)
	args := &sessionArgs{
		from:           "ui/trunk",
		as:             "feat-nav",
		headless:       true,
		permissionMode: "acceptEdits",
		planFlag:       "zai",
		remoteDir:      "genixis",
		target:         "dev@services",
	}
	rest := []string{"dev@services:genixis", "feat/nav", "implement", "the", "nav"}
	got := delegationArgs("spawn", args, rest)
	want := []string{
		"spawn", "genixis", "feat/nav", "implement", "the", "nav",
		"--from", "ui/trunk",
		"--as", "feat-nav",
		"--headless",
		"--permission-mode", "acceptEdits",
		"--plan", "zai",
	}
	if len(got) != len(want) {
		t.Fatalf("payload = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("payload[%d] = %q, want %q", i, got[i], want[i])
		}
	}
	for _, part := range got {
		if strings.Contains(part, "dev@services") {
			t.Errorf("payload leaks the delegation prefix: %v", got)
		}
	}
}

// mustRead reads one file that a stub wrote, and fails the test when the
// read cannot run.
func mustRead(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	must(t, err)
	return raw
}

// chdir changes the working directory for one block and restores it after.
func chdir(t *testing.T, dir string) func() {
	t.Helper()
	old, err := os.Getwd()
	must(t, err)
	must(t, os.Chdir(dir))
	return func() { must(t, os.Chdir(old)) }
}
