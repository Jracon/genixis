package backend

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Git is the Backend implementation over the git command line. Every call
// runs one git invocation; none of them is interactive.
type Git struct{}

// NewGit returns the git backend.
func NewGit() *Git { return &Git{} }

func (g *Git) run(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	out, err := cmd.Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return string(out), fmt.Errorf("git %s: %s", strings.Join(args, " "), strings.TrimSpace(string(exit.Stderr)))
		}
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return string(out), nil
}

// ok runs git and reports only whether it succeeded. It is for probes,
// where the caller does not want the error text.
func (g *Git) ok(dir string, args ...string) bool {
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	return cmd.Run() == nil
}

func (g *Git) lines(dir string, args ...string) ([]string, error) {
	out, err := g.run(dir, args...)
	if err != nil {
		return nil, err
	}
	lines := []string{}
	for _, line := range strings.Split(out, "\n") {
		if line = strings.TrimRight(line, "\r"); line != "" {
			lines = append(lines, line)
		}
	}
	return lines, nil
}

func (g *Git) DefaultBranch(mainDir string) string {
	if name := g.ConfigGet(mainDir, "project.defaultBranch"); name != "" {
		return name
	}
	if out, err := g.run(mainDir, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"); err == nil {
		name := strings.TrimPrefix(strings.TrimSpace(out), "origin/")
		if name != "" && (g.RefExists(mainDir, "refs/heads/"+name) || g.RefExists(mainDir, "refs/remotes/origin/"+name)) {
			return name
		}
	}
	return g.CurrentBranch(mainDir)
}

func (g *Git) CurrentBranch(dir string) string {
	out, err := g.run(dir, "branch", "--show-current")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

func (g *Git) Worktrees(mainDir string) ([]Worktree, error) {
	lines, err := g.lines(mainDir, "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	var worktrees []Worktree
	var current Worktree
	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "worktree "):
			if current.Path != "" {
				worktrees = append(worktrees, current)
			}
			current = Worktree{Path: strings.TrimPrefix(line, "worktree ")}
		case strings.HasPrefix(line, "branch "):
			current.Branch = strings.TrimPrefix(line, "branch refs/heads/")
		}
	}
	if current.Path != "" {
		worktrees = append(worktrees, current)
	}
	return worktrees, nil
}

func (g *Git) LocalBranches(mainDir string) ([]string, error) {
	return g.lines(mainDir, "for-each-ref", "--format=%(refname:short)", "refs/heads")
}

func (g *Git) RemoteBranches(mainDir string) ([]string, error) {
	lines, err := g.lines(mainDir, "for-each-ref", "--format=%(refname:lstrip=3)", "refs/remotes/origin")
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(lines))
	for _, line := range lines {
		if line != "HEAD" {
			names = append(names, line)
		}
	}
	return names, nil
}

func (g *Git) RefExists(mainDir, ref string) bool {
	return g.ok(mainDir, "show-ref", "--verify", "--quiet", ref)
}

func (g *Git) ResolveRef(mainDir, ref string) string {
	out, err := g.run(mainDir, "rev-parse", "--quiet", "--verify", ref)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

func (g *Git) AncestorOf(mainDir, branch, ref string) bool {
	return g.ok(mainDir, "merge-base", "--is-ancestor", branch, ref)
}

func (g *Git) AddWorktree(mainDir, path, branch string, mode AddMode, base string) error {
	switch mode {
	case AddExisting:
		_, err := g.run(mainDir, "worktree", "add", "--quiet", path, branch)
		return err
	case AddTrack:
		_, err := g.run(mainDir, "worktree", "add", "--quiet", "--track", "-b", branch, path, "origin/"+branch)
		return err
	case AddNew:
		_, err := g.run(mainDir, "worktree", "add", "--quiet", "--no-track", "-b", branch, path, base)
		return err
	}
	return fmt.Errorf("unknown add mode %d", mode)
}

func (g *Git) RemoveWorktree(mainDir, path string, force bool) error {
	args := []string{"worktree", "remove"}
	if force {
		args = append(args, "--force")
	}
	_, err := g.run(mainDir, append(args, path)...)
	return err
}

func (g *Git) DeleteBranch(mainDir, branch string, force bool) error {
	args := []string{"branch", "--quiet", "--delete"}
	if force {
		args = append(args, "--force")
	}
	_, err := g.run(mainDir, append(args, branch)...)
	return err
}

func (g *Git) StatusEmpty(dir string) bool {
	out, err := g.run(dir, "status", "--porcelain")
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == ""
}

func (g *Git) StatusLines(dir string) ([]string, error) {
	return g.lines(dir, "status", "--porcelain")
}

func (g *Git) ReflogSubjects(mainDir, branch string) []string {
	out, err := g.run(mainDir, "reflog", "show", "--format=%gs", branch)
	if err != nil {
		return nil
	}
	subjects := []string{}
	for _, line := range strings.Split(out, "\n") {
		if line = strings.TrimRight(line, "\r"); line != "" {
			subjects = append(subjects, line)
		}
	}
	return subjects
}

func (g *Git) UpstreamOf(mainDir, branch string) string {
	out, err := g.run(mainDir, "for-each-ref", "--format=%(upstream)", "refs/heads/"+branch)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

func (g *Git) UpstreamGone(mainDir, branch string) bool {
	out, err := g.run(mainDir, "for-each-ref", "--format=%(upstream:track)", "refs/heads/"+branch)
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == "[gone]"
}

func (g *Git) Fetch(mainDir string, prune bool, limit time.Duration) FetchResult {
	if !g.ok(mainDir, "remote", "get-url", "origin") {
		return FetchResult{}
	}
	args := []string{"fetch", "--quiet"}
	if prune {
		args = append(args, "--prune")
	}
	args = append(args, "origin")
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = mainDir
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return FetchResult{TimedOut: true}
	}
	if err != nil {
		return FetchResult{Err: err}
	}
	return FetchResult{}
}

func (g *Git) FastForward(mainDir, ref string) error {
	_, err := g.run(mainDir, "merge", "--ff-only", "--quiet", ref)
	return err
}

func (g *Git) ConfigGet(dir, key string) string {
	out, err := g.run(dir, "config", "--get", key)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

func (g *Git) ConfigGetAll(dir, key string) []string {
	lines, err := g.lines(dir, "config", "--get-all", key)
	if err != nil {
		return nil
	}
	return lines
}

func (g *Git) ConfigSet(dir, key, value string) error {
	_, err := g.run(dir, "config", key, value)
	return err
}

func (g *Git) ConfigSetWorktree(dir, key, value string) error {
	_, err := g.run(dir, "config", "--worktree", key, value)
	return err
}

// ConfigUnset removes a config key of the repository at dir. An absent key
// is success, so callers can clear unconditionally.
func (g *Git) ConfigUnset(dir, key string) error {
	return g.configUnset(dir, key, false)
}

// ConfigUnsetWorktree removes a per-worktree config key of the worktree at
// dir, with the same absent-key rule.
func (g *Git) ConfigUnsetWorktree(dir, key string) error {
	return g.configUnset(dir, key, true)
}

func (g *Git) configUnset(dir, key string, worktree bool) error {
	args := []string{"config"}
	if worktree {
		args = append(args, "--worktree")
	}
	args = append(args, "--unset", key)
	cmd := exec.Command("git", args...)
	if dir != "" {
		cmd.Dir = dir
	}
	if err := cmd.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok && exit.ExitCode() == 5 {
			return nil // the key is not set
		}
		return fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return nil
}

func (g *Git) WorktreeConfigEnabled(dir string) bool {
	format := g.ConfigGet(dir, "core.repositoryformatversion") == "1"
	enabled := g.ConfigGet(dir, "extensions.worktreeConfig") == "true"
	return format && enabled
}

// EnableWorktreeConfig is the repair dance of the former fish function
// __project_identity: per-worktree config needs extensions.worktreeConfig,
// and git reads an extensions.* key only when core.repositoryformatversion
// is 1. Turning the extension on ends the exception that confines core.bare
// and core.worktree of the common config to main, so both keys move into
// main's own per-worktree config and main works as before. A clone that an
// older revision left with the extension key at version 0 repairs itself
// here too. This method is part of the spine the owner reviews line by
// line: it rewrites repository config.
func (g *Git) EnableWorktreeConfig(mainDir string) error {
	if g.WorktreeConfigEnabled(mainDir) {
		return nil
	}
	bare := g.ConfigGet(mainDir, "core.bare")
	worktree := g.ConfigGet(mainDir, "core.worktree")
	if err := g.ConfigSet(mainDir, "core.repositoryformatversion", "1"); err != nil {
		return err
	}
	if err := g.ConfigSet(mainDir, "extensions.worktreeConfig", "true"); err != nil {
		return err
	}
	if bare != "" {
		if err := g.ConfigSetWorktree(mainDir, "core.bare", bare); err != nil {
			return err
		}
		if err := g.ConfigUnset(mainDir, "core.bare"); err != nil {
			return err
		}
	}
	if worktree != "" {
		if err := g.ConfigSetWorktree(mainDir, "core.worktree", worktree); err != nil {
			return err
		}
		if err := g.ConfigUnset(mainDir, "core.worktree"); err != nil {
			return err
		}
	}
	return nil
}

func (g *Git) GlobalConfig(key string) string {
	out, err := g.run("", "config", "--global", "--get", key)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}
