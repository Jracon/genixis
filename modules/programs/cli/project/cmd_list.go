package main

import (
	"io"
	"path/filepath"
	"time"

	"genixis/project/internal/coord"
	"genixis/project/internal/spec"
)

// cmdList reads the frontier of a project: every claim in flight (a
// worktree and its branch), every loose branch, and the merge readiness of
// each, plus the dirty state of each worktree. It is the machine-facing
// read of the coordination state, one JSON envelope on stdout.
func cmdList(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "list")
		return spec.Success
	}
	started := time.Now()
	target := ""
	for _, arg := range argv {
		target = arg
	}
	dir, err := dirArg(target)
	if err != nil {
		return emitList(stdout, stderr, started, nil, wrapGeneral(err))
	}
	if project, ok := insideProject(dir); ok {
		dir = project
	}
	if !isProjectDir(dir) {
		return emitList(stdout, stderr, started, nil, errNotFound("%s is not a project (no main/ checkout)", dir))
	}
	f, err := frontierOf(dir)
	if err != nil {
		return emitList(stdout, stderr, started, nil, wrapGeneral(err))
	}
	reports := make([]map[string]any, 0, len(f.worktrees))
	for _, report := range f.worktrees {
		reports = append(reports, map[string]any{
			"branch": report.branch,
			"dirty":  report.dirty,
			"main":   report.main,
			"path":   report.path,
		})
	}
	data := map[string]any{
		"defaultBranch": f.base,
		"dir":           dir,
		"branches":      f.entries,
		"worktrees":     reports,
	}
	return emitList(stdout, stderr, started, data, nil)
}

// worktreeReport is one worktree of the frontier read: its branch, its
// path, whether it is main, and whether it holds uncommitted work.
type worktreeReport struct {
	branch string
	dirty  bool
	main   bool
	path   string
}

// frontier is the frontier read that list prints and the board joins: the
// default branch, every other branch with its worktree and merge state,
// and the report of each worktree.
type frontier struct {
	base      string
	entries   []coord.FrontierEntry
	worktrees []worktreeReport
}

// frontierOf reads the frontier of the project at dir.
func frontierOf(dir string) (*frontier, error) {
	mainDir := filepath.Join(dir, "main")
	base := gitBackend.DefaultBranch(mainDir)
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err != nil {
		return nil, err
	}
	branches, err := gitBackend.LocalBranches(mainDir)
	if err != nil {
		return nil, err
	}
	claimOf := map[string]string{}
	for _, worktree := range worktrees {
		if worktree.Branch != "" && worktree.Path != mainDir {
			claimOf[worktree.Branch] = worktree.Path
		}
	}
	f := &frontier{base: base}
	for _, branch := range branches {
		if branch == base {
			continue
		}
		slot := coord.MergeSlot{
			DefaultBranch: base,
			ProjectBase:   gitBackend.ConfigGet(mainDir, "branch."+branch+".projectBase"),
		}
		f.entries = append(f.entries, coord.FrontierEntry{
			Branch:   branch,
			Worktree: claimOf[branch],
			Merged:   mergedThrough(gitBackend, mainDir, branch, slot),
		})
	}
	for _, worktree := range worktrees {
		f.worktrees = append(f.worktrees, worktreeReport{
			branch: worktree.Branch,
			dirty:  !gitBackend.StatusEmpty(worktree.Path),
			main:   worktree.Path == mainDir,
			path:   worktree.Path,
		})
	}
	return f, nil
}

func emitList(stdout, stderr io.Writer, started time.Time, data any, err *toolError) spec.ExitCode {
	code := spec.Success
	var detail *spec.Error
	if err != nil {
		code = err.code
		detail = err.err
		printfDiag(stderr, "%s", err.err.Message)
	}
	envelope := spec.Build("list", code, data, detail, nil, time.Since(started).Milliseconds())
	envelope.Meta.ToolVersion = version
	envelope.Meta.SchemaVersion = "1.0"
	if writeErr := spec.Write(stdout, envelope); writeErr != nil {
		return spec.GeneralError
	}
	return code
}
