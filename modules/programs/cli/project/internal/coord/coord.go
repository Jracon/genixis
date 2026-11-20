// Package coord is the internal coordination vocabulary of this tool.
//
// The names come from the beads work tracker (github.com/gastownhall/beads,
// investigated on issue #66): the frontier, the atomic claim, and the merge
// slot map one to one onto what this tool coordinates. Issue #74 (phase 3)
// fixes the vocabulary and forbids a runtime dependency on beads,
// so the types here are small and the state they describe lives where it
// already lived: in git worktrees, git branches, and git config. Forgejo
// issues stay the ticket of record.
//
// The frontier is the set of work that is unblocked and visible. The list
// subcommand reads it: every claim in flight and every loose branch, each
// marked with its merge readiness.
//
// The claim is the exclusive right to work a branch. Acquiring a claim
// creates the worktree of the branch; a worktree that already holds the
// branch is a held claim, which is why add and spawn are idempotent and two
// sessions never share a worktree. The in-flight map of the future
// dispatcher is a list of claims in this sense.
//
// The merge slot is the serialized integration point. A branch counts as
// integrated only through the default branch or the projectBase the branch
// started from; MergeSlot holds that decision, and clean integrates one
// branch at a time through it.
package coord

// Claim is the exclusive right to work a branch, held by a worktree.
type Claim struct {
	Branch   string `json:"branch"`
	Worktree string `json:"worktree"`
}

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
