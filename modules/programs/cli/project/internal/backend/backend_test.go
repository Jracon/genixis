package backend

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// newRepo makes a local repository with one commit on main, for the layer
// tests. It runs offline: no remote, no network.
func newRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not available")
	}
	// the build sandbox has no user identity, and git refuses to commit
	// with the auto-detected one on linux, so the tests name one
	t.Setenv("GIT_AUTHOR_NAME", "test")
	t.Setenv("GIT_AUTHOR_EMAIL", "test@example")
	t.Setenv("GIT_COMMITTER_NAME", "test")
	t.Setenv("GIT_COMMITTER_EMAIL", "test@example")
	dir := t.TempDir()
	git := NewGit()
	for _, args := range [][]string{
		{"init", "--quiet", "--initial-branch", "main"},
		{"config", "user.email", "test@example"},
		{"config", "user.name", "test"},
		{"commit", "--quiet", "--allow-empty", "--message", "initial"},
	} {
		cmd := args
		t.Logf("git %v", cmd)
		if out, err := git.run(dir, cmd...); err != nil {
			t.Fatalf("git %v: %v: %s", cmd, err, out)
		}
	}
	return dir
}

func TestWorktreesAndBranches(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	if got := git.CurrentBranch(main); got != "main" {
		t.Fatalf("current branch = %q, want main", got)
	}
	worktrees, err := git.Worktrees(main)
	if err != nil || len(worktrees) != 1 {
		t.Fatalf("worktrees = %v, %v", worktrees, err)
	}
	tree := filepath.Join(filepath.Dir(main), "feat-x")
	if err := git.AddWorktree(main, tree, "feat-x", AddNew, "main"); err != nil {
		t.Fatal(err)
	}
	worktrees, err = git.Worktrees(main)
	if err != nil || len(worktrees) != 2 {
		t.Fatalf("worktrees after add = %v, %v", worktrees, err)
	}
	found := false
	for _, wt := range worktrees {
		if wt.Path == tree && wt.Branch == "feat-x" {
			found = true
		}
	}
	if !found {
		t.Errorf("worktree feat-x missing from %v", worktrees)
	}
	branches, err := git.LocalBranches(main)
	if err != nil || len(branches) != 2 {
		t.Fatalf("branches = %v, %v", branches, err)
	}
	if !git.RefExists(main, "refs/heads/feat-x") || git.RefExists(main, "refs/heads/nope") {
		t.Error("RefExists is wrong")
	}
	if !git.StatusEmpty(tree) {
		t.Error("a fresh worktree must be clean")
	}
	if err := git.RemoveWorktree(main, tree, false); err != nil {
		t.Fatal(err)
	}
	worktrees, _ = git.Worktrees(main)
	if len(worktrees) != 1 {
		t.Errorf("worktree survived removal: %v", worktrees)
	}
	if err := git.DeleteBranch(main, "feat-x", true); err != nil {
		t.Fatal(err)
	}
	branches, _ = git.LocalBranches(main)
	if len(branches) != 1 {
		t.Errorf("branch survived deletion: %v", branches)
	}
}

func TestMergeDecision(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	tree := filepath.Join(filepath.Dir(main), "feat-x")
	if err := git.AddWorktree(main, tree, "feat-x", AddNew, "main"); err != nil {
		t.Fatal(err)
	}
	if !git.AncestorOf(main, "feat-x", "main") {
		t.Error("a branch from main is an ancestor of main")
	}
	// one commit on feat-x breaks the ancestry
	if out, err := git.run(tree, "commit", "--quiet", "--allow-empty", "--message", "work"); err != nil {
		t.Fatalf("commit: %v: %s", err, out)
	}
	if git.AncestorOf(main, "feat-x", "main") {
		t.Error("a branch with its own commit is not merged")
	}
	if !git.AncestorOf(main, "main", "feat-x") {
		t.Error("main is behind feat-x")
	}
}

func TestDefaultBranch(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	if got := git.DefaultBranch(main); got != "main" {
		t.Fatalf("default branch = %q, want main", got)
	}
	if err := git.ConfigSet(main, "project.defaultBranch", "trunk"); err != nil {
		t.Fatal(err)
	}
	if got := git.DefaultBranch(main); got != "trunk" {
		t.Fatalf("default branch = %q, want trunk", got)
	}
}

func TestWorktreeConfigRoundtrip(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	if git.WorktreeConfigEnabled(main) {
		t.Fatal("a fresh repo has no worktree config")
	}
	if err := git.EnableWorktreeConfig(main); err != nil {
		t.Fatal(err)
	}
	if !git.WorktreeConfigEnabled(main) {
		t.Fatal("worktree config is not enabled")
	}
	tree := filepath.Join(filepath.Dir(main), "feat-x")
	if err := git.AddWorktree(main, tree, "feat-x", AddNew, "main"); err != nil {
		t.Fatal(err)
	}
	if err := git.ConfigSetWorktree(tree, "user.name", "agent"); err != nil {
		t.Fatal(err)
	}
	if got := git.ConfigGet(tree, "user.name"); got != "agent" {
		t.Fatalf("worktree config = %q", got)
	}
	if got := git.ConfigGet(main, "user.name"); got == "agent" {
		t.Fatal("the worktree config leaked into main")
	}
	// main keeps working: the config dance moved core.bare into the
	// per-worktree file, so a git command in main still finds its worktree
	if got := git.CurrentBranch(main); got != "main" {
		t.Fatalf("main lost its branch: %q", got)
	}
}

func TestFetchWithoutRemoteIsNoop(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	result := git.Fetch(main, false, time.Second)
	if result.TimedOut || result.Err != nil {
		t.Errorf("fetch without origin must be a no-op: %+v", result)
	}
}

// newRemoteRepo makes a repository with a local bare origin beside it, for
// the tests that need a fetch. It stays offline.
func newRemoteRepo(t *testing.T) string {
	t.Helper()
	main := newRepo(t)
	git := NewGit()
	origin := filepath.Join(t.TempDir(), "origin.git")
	if out, err := git.run(main, "init", "--quiet", "--bare", "--initial-branch", "main", origin); err != nil {
		t.Fatalf("bare origin: %v: %s", err, out)
	}
	if out, err := git.run(main, "remote", "add", "origin", origin); err != nil {
		t.Fatalf("remote add: %v: %s", err, out)
	}
	if out, err := git.run(main, "push", "--quiet", "origin", "main"); err != nil {
		t.Fatalf("push main: %v: %s", err, out)
	}
	return main
}

func TestFetchRefAndMoveBranch(t *testing.T) {
	main := newRemoteRepo(t)
	git := NewGit()
	if out, err := git.run(main, "commit", "--quiet", "--allow-empty", "--message", "head"); err != nil {
		t.Fatalf("commit: %v: %s", err, out)
	}
	if out, err := git.run(main, "push", "--quiet", "origin", "HEAD:refs/pull/7/head"); err != nil {
		t.Fatalf("push the pull-request head: %v: %s", err, out)
	}
	head := git.ResolveRef(main, "HEAD")

	result := git.FetchRef(main, "refs/pull/7/head", time.Second)
	if result.TimedOut || result.Err != nil {
		t.Fatalf("FetchRef: %+v", result)
	}
	if got := git.ResolveRef(main, "FETCH_HEAD"); got != head {
		t.Fatalf("FETCH_HEAD = %q, want %q", got, head)
	}
	if result := git.FetchRef(main, "refs/pull/9/head", time.Second); result.Err == nil && !result.TimedOut {
		t.Error("FetchRef of a ref that origin holds none of must fail")
	}

	// a branch that no worktree holds moves with branch -f
	if out, err := git.run(main, "branch", "review/pr-7", "main~1"); err != nil {
		t.Fatalf("branch: %v: %s", err, out)
	}
	if err := git.MoveBranch(main, "review/pr-7", head); err != nil {
		t.Fatal(err)
	}
	if got := git.ResolveRef(main, "refs/heads/review/pr-7"); got != head {
		t.Fatalf("moved branch = %q, want %q", got, head)
	}

	// the branch of a worktree resets hard, so the files of the worktree follow
	tree := filepath.Join(filepath.Dir(main), "review-pr-7")
	if err := git.AddWorktree(main, tree, "review/pr-7", AddExisting, head); err != nil {
		t.Fatal(err)
	}
	if out, err := git.run(main, "commit", "--quiet", "--allow-empty", "--message", "newer head"); err != nil {
		t.Fatalf("commit: %v: %s", err, out)
	}
	if out, err := git.run(main, "push", "--quiet", "origin", "HEAD:refs/pull/7/head"); err != nil {
		t.Fatalf("push the newer head: %v: %s", err, out)
	}
	newHead := git.ResolveRef(main, "HEAD")
	if result := git.FetchRef(main, "refs/pull/7/head", time.Second); result.TimedOut || result.Err != nil {
		t.Fatalf("FetchRef again: %+v", result)
	}
	if err := git.MoveBranch(main, "review/pr-7", newHead); err != nil {
		t.Fatal(err)
	}
	if got := git.ResolveRef(main, "refs/heads/review/pr-7"); got != newHead {
		t.Fatalf("worktree branch = %q, want %q", got, newHead)
	}
	if !git.StatusEmpty(tree) {
		t.Error("the worktree did not follow the moved branch")
	}
}

func TestReflogAndUpstream(t *testing.T) {
	main := newRepo(t)
	git := NewGit()
	tree := filepath.Join(filepath.Dir(main), "feat-x")
	if err := git.AddWorktree(main, tree, "feat-x", AddNew, "main"); err != nil {
		t.Fatal(err)
	}
	subjects := git.ReflogSubjects(main, "feat-x")
	if len(subjects) == 0 {
		t.Fatal("a created branch has a reflog")
	}
	last := subjects[len(subjects)-1]
	if !strings.HasPrefix(last, "branch: Created") {
		t.Errorf("last reflog subject = %q, want a branch creation", last)
	}
	if got := git.UpstreamOf(main, "feat-x"); got != "" {
		t.Errorf("a --no-track branch has no upstream, got %q", got)
	}
	if git.UpstreamGone(main, "feat-x") {
		t.Error("no upstream cannot be gone")
	}
}
