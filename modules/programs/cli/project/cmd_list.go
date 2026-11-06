package main

import (
	"io"
	"path/filepath"
	"time"

	"genixis/project/internal/backend"
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
	mainDir := filepath.Join(dir, "main")
	base := gitBackend.DefaultBranch(mainDir)
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err != nil {
		return emitList(stdout, stderr, started, nil, wrapGeneral(err))
	}
	branches, err := gitBackend.LocalBranches(mainDir)
	if err != nil {
		return emitList(stdout, stderr, started, nil, wrapGeneral(err))
	}
	claimOf := map[string]string{}
	for _, worktree := range worktrees {
		if worktree.Branch != "" && worktree.Path != mainDir {
			claimOf[worktree.Branch] = worktree.Path
		}
	}
	frontier := coord.Frontier{DefaultBranch: base}
	for _, branch := range branches {
		if branch == base {
			continue
		}
		slot := coord.MergeSlot{
			DefaultBranch: base,
			ProjectBase:   gitBackend.ConfigGet(mainDir, "branch."+branch+".projectBase"),
		}
		frontier.Entries = append(frontier.Entries, coord.FrontierEntry{
			Branch:   branch,
			Worktree: claimOf[branch],
			Merged:   mergedThrough(gitBackend, mainDir, branch, slot),
		})
	}
	data := map[string]any{
		"defaultBranch": base,
		"dir":           dir,
		"branches":      frontier.Entries,
		"worktrees":     worktreeReports(mainDir, worktrees),
	}
	return emitList(stdout, stderr, started, data, nil)
}

// worktreeReports describes each worktree for the frontier read.
func worktreeReports(mainDir string, worktrees []backend.Worktree) []map[string]any {
	var reports []map[string]any
	for _, worktree := range worktrees {
		reports = append(reports, map[string]any{
			"branch": worktree.Branch,
			"dirty":  !gitBackend.StatusEmpty(worktree.Path),
			"main":   worktree.Path == mainDir,
			"path":   worktree.Path,
		})
	}
	return reports
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
