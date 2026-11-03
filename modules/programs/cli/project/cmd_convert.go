package main

import (
	"io"
	"os"
	"path/filepath"
	"regexp"

	"genixis/project/internal/spec"
)

// This file is part of the security spine (issue #74, standing principle 7):
// convert moves a whole repository one directory down, repairs its linked
// worktrees, and moves the Claude state of the old path. Every step is one
// plain action, in one fixed order.

// cmdConvert moves a plain repo into <repo>/main.
func cmdConvert(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) == 0 || argv[0] == "" {
		return fail(stderr, spec.ArgError, "%s", usage)
	}
	repo, err := resolvePath(argv[0])
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	if info, statErr := os.Stat(filepath.Join(repo, ".git")); statErr != nil || !info.IsDir() {
		return fail(stderr, spec.NotFound, "%s is not a plain git repo", repo)
	}
	mainDir := filepath.Join(repo, "main")
	// the working directory is read before the move, because os.Getwd
	// resolves the path and would answer the new location of the same
	// directory
	before := cwd()

	// linked worktrees, which keep pointing at the old path until repaired
	worktrees, err := gitBackend.Worktrees(repo)
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	var linked []string
	for i, worktree := range worktrees {
		if i > 0 {
			linked = append(linked, worktree.Path)
		}
	}

	// the move: repo becomes <tmp>/main, then tmp takes the name of repo,
	// so main sits one level below where the repo was. A failure between
	// the two renames leaves the repository in tmp, never deleted, so the
	// owner can move it back by hand.
	tmp, err := os.MkdirTemp(filepath.Dir(repo), ".project-convert.")
	if err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	if err := os.Rename(repo, filepath.Join(tmp, "main")); err != nil {
		return fail(stderr, spec.GeneralError, "%v", err)
	}
	if err := os.Rename(tmp, repo); err != nil {
		return fail(stderr, spec.GeneralError, "the repository now sits in %s; move it back by hand: %v", tmp, err)
	}
	if len(linked) > 0 {
		if out, err := runCmd(mainDir, nil, "git", append([]string{"worktree", "repair"}, linked...)...); err != nil {
			return fail(stderr, spec.GeneralError, "git worktree repair: %v: %s", err, out)
		}
	}
	_ = gitBackend.ConfigUnset(mainDir, "project.convert")

	// the caller's shell stays where it was, now inside main: the fish stub
	// changes directory through the cd file
	if inDir(repo, before) {
		rel, _ := filepath.Rel(repo, before)
		writeCDFile(filepath.Join(mainDir, rel))
	}
	// ide windows record their directory in @ide_dir; they follow the repo
	for _, entry := range tmuxWindowsWithExactDir(repo) {
		_, _ = tmux("set-option", "-w", "-t", entry, "@ide_dir", mainDir)
	}

	// Claude Code keeps transcripts per path, every non-alphanumeric
	// character as -; memory moves into the project, where `project open`
	// points Claude at it
	claudeConfig := os.Getenv("CLAUDE_CONFIG_DIR")
	if claudeConfig == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return spec.Success
		}
		claudeConfig = filepath.Join(home, ".claude")
	}
	projects := filepath.Join(claudeConfig, "projects")
	old := filepath.Join(projects, manglePath(repo))
	new := filepath.Join(projects, manglePath(mainDir))
	if info, err := os.Stat(filepath.Join(old, "memory")); err == nil && info.IsDir() {
		if _, err := os.Stat(filepath.Join(repo, ".claude", "memory")); os.IsNotExist(err) {
			if err := os.MkdirAll(filepath.Join(repo, ".claude"), 0o755); err == nil {
				_ = os.Rename(filepath.Join(old, "memory"), filepath.Join(repo, ".claude", "memory"))
			}
		}
	}
	if _, err := os.Stat(old); err == nil {
		if _, err := os.Stat(new); os.IsNotExist(err) {
			_ = os.Rename(old, new)
		}
	}
	return spec.Success
}

var manglePattern = regexp.MustCompile(`[^A-Za-z0-9]`)

func manglePath(path string) string {
	return manglePattern.ReplaceAllString(path, "-")
}
