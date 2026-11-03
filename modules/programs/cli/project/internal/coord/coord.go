// Package coord is the internal coordination vocabulary of this tool.
//
// The names come from the beads work tracker (github.com/gastownhall/beads,
// investigated on issue #66): the frontier, the atomic claim, the gate, and
// the merge slot map one to one onto what this tool coordinates. Issue #74
// (phase 3) fixes the vocabulary and forbids a runtime dependency on beads,
// so the types here are small and the state they describe lives where it
// already lived: in git worktrees, git branches, and git config. Forgejo
// issues stay the ticket of record.
//
// The frontier is the set of work that is unblocked and visible. The list
// subcommand reads it: Frontier holds every claim in flight and every loose
// branch, each marked with its merge readiness.
//
// The claim is the exclusive right to work a branch. Acquiring a claim
// creates the worktree of the branch; a worktree that already holds the
// branch is a held claim, which is why add and spawn are idempotent and two
// sessions never share a worktree. The in-flight map of the future
// dispatcher is a list of claims in this sense.
//
// The gate parks work on an external event. A GateError names the gate that
// refused an operation: the closeCheck veto parks a close on the project's
// own check, the confirmation code parks a discard on a human, and the
// terminal check parks discard away from agents entirely.
//
// The merge slot is the serialized integration point. A branch counts as
// integrated only through the default branch or the projectBase the branch
// started from; MergeSlot holds that decision, and clean integrates one
// branch at a time through it.
package coord

import "fmt"

// Claim is the exclusive right to work a branch, held by a worktree.
type Claim struct {
	Branch   string `json:"branch"`
	Worktree string `json:"worktree"`
}

// GateError is the refusal of a gate: an operation parked on an external
// event that has not happened.
type GateError struct {
	Gate   string
	Reason string
}

func (e *GateError) Error() string {
	return fmt.Sprintf("%s: %s", e.Gate, e.Reason)
}

// The gates of this tool.
const (
	// GateCloseCheck is the project.closeCheck veto command of a project.
	GateCloseCheck = "project.closeCheck"
	// GateHumanConfirm is the typed code of a discard.
	GateHumanConfirm = "human-confirm"
	// GateTerminal is the requirement that discard runs at a person's
	// terminal.
	GateTerminal = "terminal"
	// GateCleanWork is the uncommitted work that parks a close.
	GateCleanWork = "clean-worktree"
)

// MergeSlot is the integration decision for one branch: the branch counts
// as integrated when it is an ancestor of its default branch (locally or
// upstream) or of the projectBase it was started from (likewise). This is
// the serialized point where work lands; nothing else declares a branch
// done.
type MergeSlot struct {
	DefaultBranch string
	ProjectBase   string
}

// Refs lists the refs that integrate a branch, in decision order.
func (s MergeSlot) Refs() []string {
	var refs []string
	if s.DefaultBranch != "" {
		refs = append(refs, "refs/heads/"+s.DefaultBranch, "refs/remotes/origin/"+s.DefaultBranch)
	}
	if s.ProjectBase != "" {
		refs = append(refs, "refs/heads/"+s.ProjectBase, "refs/remotes/origin/"+s.ProjectBase)
	}
	return refs
}

// FrontierEntry is one branch of the frontier: a held claim or a loose
// branch, with its integration state.
type FrontierEntry struct {
	Branch   string `json:"branch"`
	Worktree string `json:"worktree"` // empty when no claim is held
	Merged   bool   `json:"merged"`   // the merge slot accepts the branch
}

// Frontier is the unblocked work of one project, as the list subcommand
// reports it: the default branch and every other branch with its state.
type Frontier struct {
	DefaultBranch string
	Entries       []FrontierEntry
}

// Held returns the entries with a worktree.
func (f Frontier) Held() []FrontierEntry {
	var held []FrontierEntry
	for _, entry := range f.Entries {
		if entry.Worktree != "" {
			held = append(held, entry)
		}
	}
	return held
}

// Loose returns the entries without a worktree.
func (f Frontier) Loose() []FrontierEntry {
	var loose []FrontierEntry
	for _, entry := range f.Entries {
		if entry.Worktree == "" {
			loose = append(loose, entry)
		}
	}
	return loose
}
