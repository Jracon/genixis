package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"genixis/project/internal/backend"
	"genixis/project/internal/spec"
)

// This file is the review subcommand of the reviewer rig (issue #181): the
// head of a pull request as one worktree of its own, opened in an ide
// window. The branch review/pr-<n> lives in the review namespace, and this
// subcommand owns it alone: it makes the branch from the fetched head, and
// on every run it moves the branch to the current head, so a review never
// reads a stale revision. A dirty worktree is the one exception: its state
// stays, and the run says so.

// cmdReview is `project review [<dir>] <n>`: fetch the head of pull request
// <n> into the branch review/pr-<n>, make or reuse its worktree, and open it
// the way `project open` does, under the identity of the owner.
func cmdReview(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "review")
		return spec.Success
	}
	var positionals []string
	for _, arg := range argv {
		if strings.HasPrefix(arg, "-") {
			return fail(stderr, spec.ArgError, "review takes no option; it needs one pull-request number")
		}
		positionals = append(positionals, arg)
	}
	if len(positionals) < 1 || len(positionals) > 2 {
		return fail(stderr, spec.ArgError, "usage: project review [<dir>] <n>")
	}
	target := ""
	if len(positionals) == 2 {
		target = positionals[0]
	}
	number := positionals[len(positionals)-1]
	n, convErr := strconv.Atoi(number)
	if convErr != nil || n < 1 || strconv.Itoa(n) != number {
		return fail(stderr, spec.ArgError, "%q is not a pull-request number; for example: project review 173", number)
	}
	dir, err := dirArg(target)
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	if project, ok := insideProject(dir); ok {
		dir = project
	}
	if !isProjectDir(dir) {
		return fail(stderr, spec.NotFound, "%s is not a project (no main/ checkout)", dir)
	}
	branch := fmt.Sprintf("review/pr-%d", n)
	if toolErr := reviewSync(stderr, dir, branch, n); toolErr != nil {
		fmt.Fprintln(stderr, toolErr)
		return toolErr.code
	}
	// open under the identity of the owner: the review worktree is the
	// reading room of the owner, so a commit made there carries the owner,
	// not the agent
	return cmdSession("open", []string{dir, branch, "--identity", "owner"}, stdout, stderr)
}

// reviewSync fetches the head of pull request n and puts the review branch
// at it. A missing branch and worktree are made; an existing worktree is
// reused, and the branch moves to the fetched head while the worktree is
// clean. The fetch must succeed: a review that cannot see the current head
// reads the wrong revision, so the command fails with the unavailable code
// and the run is retried.
func reviewSync(stderr io.Writer, dir, branch string, n int) *toolError {
	mainDir := filepath.Join(dir, "main")
	ref := fmt.Sprintf("refs/pull/%d/head", n)
	fetched := gitBackend.FetchRef(mainDir, ref, 10*time.Second)
	if fetched.TimedOut || fetched.Err != nil {
		return errUnavailable("couldn't fetch %s from origin; a review reads the current head, so retry when origin answers", ref)
	}
	head := gitBackend.ResolveRef(mainDir, "FETCH_HEAD")
	if head == "" {
		return errNotFound("origin holds no %s; is %d a pull request of this repository?", ref, n)
	}
	tree := reviewTree(dir, branch, mainDir)
	if _, statErr := os.Stat(tree); os.IsNotExist(statErr) {
		mode := backend.AddNew
		if gitBackend.RefExists(mainDir, "refs/heads/"+branch) {
			// the branch of a closed review sits at its last head; put it at
			// the current one before the worktree checks it out
			if err := gitBackend.MoveBranch(mainDir, branch, head); err != nil {
				return wrapGeneral(err)
			}
			mode = backend.AddExisting
		}
		if err := gitBackend.AddWorktree(mainDir, tree, branch, mode, head); err != nil {
			return wrapGeneral(err)
		}
		setupWorktree(mainDir, dir, tree)
		printfDiag(stderr, "review: %s at %s", branch, shortHead(head))
		return nil
	}
	if !gitBackend.StatusEmpty(tree) {
		printfDiag(stderr, "review: %s holds uncommitted work, so the branch stays at its head; close or clean it to follow pull request %d", tree, n)
		return nil
	}
	if current := gitBackend.ResolveRef(mainDir, "refs/heads/"+branch); current != head {
		if err := gitBackend.MoveBranch(mainDir, branch, head); err != nil {
			return wrapGeneral(err)
		}
		printfDiag(stderr, "review: moved %s to %s", branch, shortHead(head))
	}
	return nil
}

// reviewTree is the worktree of the review branch: the one that already
// holds the branch, whatever its directory name, else <dir>/<branch with /
// as ->.
func reviewTree(dir, branch, mainDir string) string {
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err == nil {
		for _, worktree := range worktrees {
			if worktree.Branch == branch && worktree.Path != mainDir {
				return worktree.Path
			}
		}
	}
	return filepath.Join(dir, strings.ReplaceAll(branch, "/", "-"))
}

// shortHead is the first nine letters of a commit id, the length git prints.
func shortHead(head string) string {
	if len(head) > 9 {
		return head[:9]
	}
	return head
}
