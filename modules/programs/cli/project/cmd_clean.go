package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"genixis/project/internal/backend"
	"genixis/project/internal/coord"
	"genixis/project/internal/spec"
)

// This file is part of the security spine (issue #74, standing principle 7):
// clean deletes merged branches and closes merged worktrees. Its merge
// decision goes through the merge slot (the default branch or the
// projectBase), one branch at a time, and a worktree with uncommitted work
// stays open.

// cmdClean fast-forwards the default branch, closes every merged worktree,
// and deletes merged local branches. --gone also cleans branches whose
// remote branch was deleted, which is how a squash merge shows. --dry-run
// lists the steps and changes nothing, except the fetch.
func cmdClean(argv []string, stdout, stderr io.Writer) spec.ExitCode {
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

	// the upstream tips from before the fetch drop the branches the remote
	// deleted: --gone deletes a branch only if it has nothing beyond its
	// old upstream
	type tip struct {
		branch string
		commit string
	}
	var preTips []tip
	if gone {
		for _, branch := range localBranches(mainDir) {
			upstream := gitBackend.UpstreamOf(mainDir, branch)
			if upstream == "" {
				continue
			}
			commit := gitBackend.ResolveRef(mainDir, upstream)
			if commit == "" {
				commit = "none"
			}
			preTips = append(preTips, tip{branch: branch, commit: commit})
		}
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

	// --gone: branches whose remote branch was deleted. A branch goes only
	// when its local tip still equals the upstream tip from before the
	// fetch, which shows that no unpushed work exists.
	var goneBranches []string
	if gone {
		for _, branch := range localBranches(mainDir) {
			if !gitBackend.UpstreamGone(mainDir, branch) {
				continue
			}
			kept := true
			for _, pre := range preTips {
				if pre.branch == branch {
					kept = pre.commit != gitBackend.ResolveRef(mainDir, "refs/heads/"+branch)
					break
				}
			}
			if kept {
				printfDiag(stderr, "kept %s: its remote branch is gone, but it may hold unpushed work", branch)
				continue
			}
			goneBranches = append(goneBranches, branch)
		}
	}

	// the frontier: every branch except the default branch and the one
	// main/ has checked out; a branch with only its creation in the reflog
	// has no work yet, it merely looks merged
	var loose, trees []string
	for _, branch := range localBranches(mainDir) {
		if branch == base || branch == gitBackend.CurrentBranch(mainDir) {
			continue
		}
		subjects := gitBackend.ReflogSubjects(mainDir, branch)
		if len(subjects) == 1 && strings.HasPrefix(subjects[0], "branch: Created") {
			continue
		}
		slot := coord.MergeSlot{
			DefaultBranch: base,
			ProjectBase:   gitBackend.ConfigGet(mainDir, "branch."+branch+".projectBase"),
		}
		if !mergedThrough(gitBackend, mainDir, branch, slot) && !contains(goneBranches, branch) {
			continue
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
		// a gone branch need not be an ancestor of anything, so close keeps
		// it
		if contains(goneBranches, branch) && gitBackend.RefExists(mainDir, "refs/heads/"+branch) {
			if err := gitBackend.DeleteBranch(mainDir, branch, true); err == nil {
				writeLine(stdout, "deleted branch %s", branch)
			}
		}
	}
	return spec.Success
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
