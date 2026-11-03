// Package backend is the worktree and branch layer of a project directory.
//
// Every subcommand of this tool goes through this interface, and the git
// implementation is the only one today. The interface exists so that a jj
// backend can sit behind it later (issue #74, phase 3): the subcommands
// speak in worktrees, branches, merge decisions, and config keys, never in
// git command lines. A second backend implements this interface and nothing
// else changes.
package backend

import "time"

// Worktree is one linked worktree of a project: its path and its branch,
// which is empty for a detached worktree.
type Worktree struct {
	Path   string
	Branch string
}

// AddMode tells AddWorktree how the branch of a new worktree comes to be.
type AddMode int

const (
	// AddExisting checks out a local branch that already exists.
	AddExisting AddMode = iota
	// AddTrack creates the branch from a remote branch and tracks it.
	AddTrack
	// AddNew creates the branch with no upstream, starting at base.
	AddNew
)

// FetchResult reports what a fetch did, for the warnings of a command.
type FetchResult struct {
	// TimedOut is true when the fetch gave up within its limit. The caller
	// continues with what is local.
	TimedOut bool
	// Err is the failure when the fetch ran and failed.
	Err error
}

// Backend reads and changes the worktree and branch layer of one project.
// Every method takes the directory it works on, so one Backend serves a
// whole project directory. Methods that change state return an error when
// the underlying command fails; the subcommands decide the exit code.
type Backend interface {
	// DefaultBranch names the project's default branch: the git config key
	// project.defaultBranch, else what origin/HEAD names when that branch
	// exists, else the branch checked out in main. Empty when none applies.
	DefaultBranch(mainDir string) string
	// CurrentBranch is the branch checked out in dir, or empty.
	CurrentBranch(dir string) string
	// Worktrees lists the linked worktrees of the repository at mainDir.
	Worktrees(mainDir string) ([]Worktree, error)
	// LocalBranches lists the branch names under refs/heads, in ref order.
	LocalBranches(mainDir string) ([]string, error)
	// RemoteBranches lists the branch names under refs/remotes/origin,
	// without the prefix and without HEAD.
	RemoteBranches(mainDir string) ([]string, error)
	// RefExists reports whether a ref (short form allowed) resolves.
	RefExists(mainDir, ref string) bool
	// ResolveRef returns the commit id a ref points at, or empty.
	ResolveRef(mainDir, ref string) string
	// AncestorOf reports whether branch is an ancestor of ref, the merge
	// decision of the tool.
	AncestorOf(mainDir, branch, ref string) bool
	// AddWorktree creates a worktree at path for branch. base is the start
	// point for AddNew and the source for AddTrack; AddExisting ignores it.
	AddWorktree(mainDir, path, branch string, mode AddMode, base string) error
	// RemoveWorktree removes the worktree at path; force discards work in
	// it, and the caller must guard force behind its own gates.
	RemoveWorktree(mainDir, path string, force bool) error
	// DeleteBranch removes a local branch; force deletes a branch that is
	// not merged, and the caller must guard force behind its own gates.
	DeleteBranch(mainDir, branch string, force bool) error
	// StatusEmpty reports whether the worktree at dir has no uncommitted
	// and no untracked work that git sees.
	StatusEmpty(dir string) bool
	// StatusLines is the porcelain status of dir, one entry per line.
	StatusLines(dir string) ([]string, error)
	// ReflogSubjects are the one-line subjects of the reflog of branch,
	// oldest first; an empty slice when the branch has no reflog.
	ReflogSubjects(mainDir, branch string) []string
	// UpstreamOf names the upstream of branch, or empty.
	UpstreamOf(mainDir, branch string) string
	// UpstreamGone reports whether the upstream of branch was deleted on
	// the remote, which is how a squash merge shows.
	UpstreamGone(mainDir, branch string) bool
	// Fetch updates the remote-tracking branches of origin, with a limit.
	// It never fails the caller for a network problem: the result says what
	// happened and the caller warns.
	Fetch(mainDir string, prune bool, limit time.Duration) FetchResult
	// FastForward moves the branch of mainDir forward to ref, only when
	// that is a fast-forward.
	FastForward(mainDir, ref string) error
	// ConfigGet reads a config key of the repository at dir, or empty.
	ConfigGet(dir, key string) string
	// ConfigGetAll reads every value of a multi-valued key.
	ConfigGetAll(dir, key string) []string
	// ConfigSet writes a config key of the repository at dir.
	ConfigSet(dir, key, value string) error
	// ConfigSetWorktree writes a per-worktree config key of the worktree
	// at dir.
	ConfigSetWorktree(dir, key, value string) error
	// ConfigUnset removes a config key of the repository at dir.
	ConfigUnset(dir, key string) error
	// ConfigUnsetWorktree removes a per-worktree config key of the worktree
	// at dir.
	ConfigUnsetWorktree(dir, key string) error
	// WorktreeConfigEnabled reports whether the repository at dir reads
	// per-worktree config.
	WorktreeConfigEnabled(dir string) bool
	// EnableWorktreeConfig turns per-worktree config on for the repository,
	// moving core.bare and core.worktree into the per-worktree config of
	// main, so main keeps working as before. It is idempotent.
	EnableWorktreeConfig(mainDir string) error
	// GlobalConfig reads a key from the global config of the user, or empty.
	GlobalConfig(key string) string
}
