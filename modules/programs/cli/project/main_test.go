package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

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
			"open", "add", "spawn", "list", "review", "close", "discard", "clean",
			"convert", "ide", "ide-layout", "ide-open", "ide-edit",
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
	head = nextHead()
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

// ------------------------------------------------------------------- helpers

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

// chdir changes the working directory for one block and restores it after.
func chdir(t *testing.T, dir string) func() {
	t.Helper()
	old, err := os.Getwd()
	must(t, err)
	must(t, os.Chdir(dir))
	return func() { must(t, os.Chdir(old)) }
}
