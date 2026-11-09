package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"genixis/project/internal/backend"
	"genixis/project/internal/coord"
	"genixis/project/internal/spec"
)

// This file is part of the security spine (issue #74, standing principle 7):
// clean deletes branches and closes worktrees. A branch goes through the
// merge slot (the default branch or the projectBase), one branch at a time,
// through the gone upstream under --gone, or through the closed state of the
// forge. Every path keeps the same rails: a worktree with uncommitted work
// stays open, and a branch with unpushed work stays.

// cmdClean fast-forwards the default branch, closes every merged worktree,
// and deletes merged local branches. --gone also cleans branches whose
// remote branch was deleted, which is how a squash merge shows. A branch
// with only its creation in the reflog is a finished review leg when it is
// merged and its upstream is gone: clean removes that too. Work that the
// forge shows closed goes as well: the head branch and the review branch of
// a pull request that closed without a merge, and the branch of an issue
// that closed, each under the unpushed-work guard. --dry-run lists the steps
// and changes nothing, except the fetch.
func cmdClean(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "clean")
		return spec.Success
	}
	dryRun := false
	gone := false
	var target string
	for _, arg := range argv {
		switch arg {
		case "-n", "--dry-run":
			dryRun = true
		case "--gone":
			gone = true
		default:
			if strings.HasPrefix(arg, "-") {
				return fail(stderr, spec.ArgError, "unknown option %s", arg)
			}
			target = arg
		}
	}
	if target == "" {
		target = "."
	}
	resolved, err := resolvePath(target)
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	dir := ""
	if isProjectDir(resolved) {
		dir = resolved
	} else if project, ok := insideProject(resolved); ok {
		dir = project
	}
	if dir == "" {
		return fail(stderr, spec.NotFound, "%s is not in a project", resolved)
	}
	mainDir := filepath.Join(dir, "main")
	base := gitBackend.DefaultBranch(mainDir)

	// the upstream tips from before the fetch guard two paths: --gone and
	// the closed state of the forge. The fetch prunes the branches the
	// remote deleted, so a branch whose upstream is gone goes only when it
	// has nothing beyond its old upstream tip
	preTips := map[string]string{}
	for _, branch := range localBranches(mainDir) {
		upstream := gitBackend.UpstreamOf(mainDir, branch)
		if upstream == "" {
			continue
		}
		preTips[branch] = gitBackend.ResolveRef(mainDir, upstream)
	}

	// catch up: fetch (dropping branches the remote deleted), then
	// fast-forward the default branch
	fetched := gitBackend.Fetch(mainDir, true, 10*time.Second)
	if fetched.TimedOut || fetched.Err != nil {
		printfDiag(stderr, "couldn't fetch origin; cleaning with what is local")
	}
	if base != "" {
		current := gitBackend.CurrentBranch(mainDir)
		if current != base {
			printfDiag(stderr, "main/ is on %s, not the default branch %s; not fast-forwarding", current, base)
		} else if gitBackend.RefExists(mainDir, "refs/remotes/origin/"+base) {
			if dryRun {
				writeLine(stdout, "would fast-forward %s", base)
			} else if err := gitBackend.FastForward(mainDir, "origin/"+base); err != nil {
				printfDiag(stderr, "couldn't fast-forward %s to origin/%s", base, base)
			}
		}
	}

	// which branch each worktree has
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	worktreeBranch := map[string]string{}
	for _, worktree := range worktrees {
		worktreeBranch[worktree.Path] = worktree.Branch
	}

	// the closed state of the forge: the third way to finish, beside the
	// merge slot and the gone upstream (issue #210)
	forge := readForgeClosed(mainDir, stderr)

	// --gone: branches whose remote branch was deleted. A branch goes only
	// when its local tip still equals the upstream tip from before the
	// fetch, which shows that no unpushed work exists.
	var goneBranches []string
	if gone {
		for _, branch := range localBranches(mainDir) {
			if !gitBackend.UpstreamGone(mainDir, branch) {
				continue
			}
			if preTips[branch] != gitBackend.ResolveRef(mainDir, "refs/heads/"+branch) {
				printfDiag(stderr, "kept %s: its remote branch is gone, but it may hold unpushed work", branch)
				continue
			}
			goneBranches = append(goneBranches, branch)
		}
	}

	// the frontier: every branch except the default branch and the one
	// main/ has checked out. A branch with only its creation in the reflog
	// has no work yet, it merely looks merged: it stays, unless the gone
	// upstream names a finished review leg (issue #130). A reviewer makes
	// no commits, and the forge deletes the remote branch of the pull
	// request it merged, so creation + merged + upstream gone can hold no
	// work to lose. The closed state of the forge names finished work the
	// same way (issue #210), under the unpushed-work guard.
	var loose, trees, finishedBranches []string
	for _, branch := range localBranches(mainDir) {
		if branch == base || branch == gitBackend.CurrentBranch(mainDir) {
			continue
		}
		slot := coord.MergeSlot{
			DefaultBranch: base,
			ProjectBase:   gitBackend.ConfigGet(mainDir, "branch."+branch+".projectBase"),
		}
		merged := mergedThrough(gitBackend, mainDir, branch, slot)
		subjects := gitBackend.ReflogSubjects(mainDir, branch)
		creationOnly := len(subjects) == 1 && strings.HasPrefix(subjects[0], "branch: Created")
		finished := false
		if claimed, claim := forge.claims(branch); claimed {
			if reason := unpushedWork(gitBackend, mainDir, branch, preTips, creationOnly); reason != "" {
				printfDiag(stderr, "kept %s: %s, but %s", branch, claim, reason)
			} else {
				finished = true
			}
		}
		if creationOnly && !finished {
			// a leg that a claim made but no session started has no
			// upstream, and the branch of a pull request in review still
			// has one: only the gone upstream proves the leg finished
			if !merged || !gitBackend.UpstreamGone(mainDir, branch) {
				continue
			}
		}
		if !merged && !finished && !contains(goneBranches, branch) {
			continue
		}
		if finished {
			finishedBranches = append(finishedBranches, branch)
		}
		if tree := worktreeOf(worktrees, branch); tree != "" {
			trees = append(trees, tree)
		} else {
			loose = append(loose, branch)
		}
	}

	for _, branch := range loose {
		if dryRun {
			writeLine(stdout, "would delete branch %s", branch)
			continue
		}
		if err := gitBackend.DeleteBranch(mainDir, branch, true); err != nil {
			printfDiag(stderr, "%v", err)
			continue
		}
		writeLine(stdout, "deleted branch %s", branch)
	}

	// the worktree this runs in goes last: closing it ends the shell
	here := gitTopLevel(cwd())
	for i, tree := range trees {
		if tree == here {
			trees = append(append(trees[:i:i], trees[i+1:]...), here)
			break
		}
	}
	for _, tree := range trees {
		branch := worktreeBranch[tree]
		if dryRun {
			writeLine(stdout, "would close %s and delete branch %s", tree, branch)
			continue
		}
		code, err := runClose("close", []string{tree}, stdout, stderr)
		if err != nil {
			printfDiag(stderr, "%s", err.err.Message)
			continue
		}
		if code != spec.Success {
			continue
		}
		if _, statErr := os.Stat(tree); statErr == nil {
			printfDiag(stderr, "kept %s", tree)
			continue
		}
		writeLine(stdout, "closed %s", tree)
		// a gone branch and a branch of closed forge work need not be an
		// ancestor of anything, so close keeps them: clean deletes them
		// itself, the way project close deletes a merged branch
		if (contains(goneBranches, branch) || contains(finishedBranches, branch)) && gitBackend.RefExists(mainDir, "refs/heads/"+branch) {
			if err := gitBackend.DeleteBranch(mainDir, branch, true); err == nil {
				writeLine(stdout, "deleted branch %s", branch)
			}
		}
	}
	return spec.Success
}

// forgeClosed is the forge half of the finished decision of clean: the pull
// requests that closed without a merge, the head branches of the pull
// requests still open, and the issues that closed. A pull request that
// merged claims no branch: the merge slot and --gone already reach its
// branch.
type forgeClosed struct {
	// ready is false when a list failed, so no branch is claimed
	ready bool
	// closedHeads maps the head branch of each pull request that closed
	// without a merge to its number
	closedHeads map[string]int
	// closedReviews holds the number of each pull request that closed
	// without a merge, for the branches of the review namespace
	closedReviews map[int]bool
	// openHeads holds the head branch of each open pull request
	openHeads map[string]bool
	// closedIssues holds the number of each closed issue
	closedIssues map[int]bool
}

// readForgeClosed reads the closed pull requests, the open pull requests,
// and the closed issues through tea, the same lists that project board
// reads. Each list holds the 50 most recent entries of its kind. Every
// failure becomes a warning and leaves the read not ready, so clean goes on
// with what git alone proves, the way it already does when the fetch fails.
func readForgeClosed(mainDir string, stderr io.Writer) forgeClosed {
	var open, closed []boardPull
	var issues []boardIssue
	if !commandExists("tea") {
		printfDiag(stderr, "tea is not on PATH, so clean cannot see the work that the forge closed; cleaning with what is local")
		return forgeClosed{}
	}
	for _, list := range []struct {
		state string
		into  *[]boardPull
	}{
		{"open", &open},
		{"closed", &closed},
	} {
		raw, err := runCmd(mainDir, nil, "tea", "pulls", "list", "--state", list.state, "--fields", "index,state,head", "--limit", "50", "--output", "json")
		if err != nil {
			printfDiag(stderr, "tea listed no %s pull requests, so clean cannot see the work that the forge closed: %s", list.state, err)
			return forgeClosed{}
		}
		if err := jsonUnmarshal([]byte(raw), list.into); err != nil {
			printfDiag(stderr, "the %s pull request list of tea did not parse, so clean cannot see the work that the forge closed: %s", list.state, err)
			return forgeClosed{}
		}
	}
	raw, err := runCmd(mainDir, nil, "tea", "issues", "list", "--state", "closed", "--limit", "50", "--output", "json")
	if err != nil {
		printfDiag(stderr, "tea listed no closed issues, so clean cannot see the work that the forge closed: %s", err)
		return forgeClosed{}
	}
	if err := jsonUnmarshal([]byte(raw), &issues); err != nil {
		printfDiag(stderr, "the closed issue list of tea did not parse, so clean cannot see the work that the forge closed: %s", err)
		return forgeClosed{}
	}
	return joinForgeLists(open, closed, issues)
}

// joinForgeLists folds the three tea lists into the claim tables of the
// forge state. tea prints the state merged for a pull request that merged
// and closed for one that closed without a merge: only the second claims a
// branch, because the branch of a merged pull request stays with the merge
// rules and --gone.
func joinForgeLists(open, closed []boardPull, issues []boardIssue) forgeClosed {
	f := forgeClosed{
		closedHeads:   map[string]int{},
		closedReviews: map[int]bool{},
		openHeads:     map[string]bool{},
		closedIssues:  map[int]bool{},
	}
	for _, pull := range open {
		if pull.Head != "" {
			f.openHeads[pull.Head] = true
		}
	}
	for _, pull := range closed {
		n, err := strconv.Atoi(pull.Number)
		if err != nil || pull.State != "closed" {
			continue
		}
		if pull.Head != "" {
			f.closedHeads[pull.Head] = n
		}
		f.closedReviews[n] = true
	}
	for _, issue := range issues {
		if n, err := strconv.Atoi(issue.Number); err == nil {
			f.closedIssues[n] = true
		}
	}
	f.ready = true
	return f
}

// cleanReviewBranch matches the branch of a reviewer leg in both of its
// forms: the review/pr-<n> branch that `project review` makes, and the
// ai/review-<n> branch of the dispatcher. Each names its pull request.
var cleanReviewBranch = regexp.MustCompile(`^(?:review/pr-|ai/review-)(\d+)$`)

// cleanIssueBranch matches the worker branch of the dispatcher, which names
// its issue. The name is a convention of the dispatcher alone, so it is the
// only way an issue can reach a branch that no pull request carries.
var cleanIssueBranch = regexp.MustCompile(`^ai/issue-(\d+)$`)

// claims reports whether the forge names the work of branch as finished,
// and says why. The head branch of an open pull request is never claimed,
// because a nudge leg can still continue its work.
func (f forgeClosed) claims(branch string) (bool, string) {
	if !f.ready || f.openHeads[branch] {
		return false, ""
	}
	if n, ok := f.closedHeads[branch]; ok {
		return true, fmt.Sprintf("pull request #%d closed without a merge", n)
	}
	if match := cleanReviewBranch.FindStringSubmatch(branch); match != nil {
		if n, err := strconv.Atoi(match[1]); err == nil && f.closedReviews[n] {
			return true, fmt.Sprintf("the review of pull request #%d ended", n)
		}
	}
	if match := cleanIssueBranch.FindStringSubmatch(branch); match != nil {
		if n, err := strconv.Atoi(match[1]); err == nil && f.closedIssues[n] {
			return true, fmt.Sprintf("issue #%d closed", n)
		}
	}
	return false, ""
}

// unpushedWork says why branch may hold work that no remote holds, or
// returns empty when every commit of the branch is on a remote. It is the
// guard of the closed-entity path and holds the same rail as --gone: an
// upstream that still exists must carry everything the branch holds, an
// upstream the remote deleted must name the local tip in the saved tips
// from before the fetch, and a branch without an upstream must hold no
// commit of its own, which only its sole creation in the reflog shows.
func unpushedWork(git backend.Backend, mainDir, branch string, preTips map[string]string, creationOnly bool) string {
	upstream := git.UpstreamOf(mainDir, branch)
	if upstream == "" {
		if creationOnly {
			return ""
		}
		return "its work was never pushed"
	}
	if git.RefExists(mainDir, upstream) {
		if git.AncestorOf(mainDir, branch, upstream) {
			return ""
		}
		return "its tip is ahead of " + upstream
	}
	if preTips[branch] == git.ResolveRef(mainDir, "refs/heads/"+branch) {
		return ""
	}
	return "its remote branch is gone and it may hold unpushed work"
}

func localBranches(mainDir string) []string {
	branches, err := gitBackend.LocalBranches(mainDir)
	if err != nil {
		return nil
	}
	return branches
}

func worktreeOf(worktrees []backend.Worktree, branch string) string {
	for _, worktree := range worktrees {
		if worktree.Branch == branch {
			return worktree.Path
		}
	}
	return ""
}

func contains(list []string, name string) bool {
	for _, entry := range list {
		if entry == name {
			return true
		}
	}
	return false
}

func writeLine(w io.Writer, format string, args ...any) {
	fmt.Fprintf(w, format+"\n", args...)
}
