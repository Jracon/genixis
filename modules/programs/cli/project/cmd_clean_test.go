package main

import (
	"testing"
)

// The clean tests on plain data pin the join of the forge state: which
// branches the closed entities claim. The scratch tests of main_test.go pin
// the whole path, the unpushed-work guard included.

func TestJoinForgeListsClaimsClosedWorkOnly(t *testing.T) {
	open := []boardPull{
		{Number: "214", State: "open", Head: "ai/issue-205"},
	}
	closed := []boardPull{
		{Number: "207", State: "closed", Head: "ai/issue-198"},
		// tea prints merged for a pull request that merged: it claims
		// nothing, because the merge slot and --gone keep its branch
		{Number: "206", State: "merged", Head: "ai/issue-204"},
		// a pull request without a head branch claims no head
		{Number: "208", State: "closed"},
	}
	issues := []boardIssue{
		{Number: "209"},
		{Number: "205"},
	}
	f := joinForgeLists(open, closed, issues)
	cases := []struct {
		branch  string
		claimed bool
		why     string
	}{
		{"ai/issue-198", true, "pull request #207 closed without a merge"},
		{"ai/review-207", true, "the review of pull request #207 ended"},
		{"review/pr-207", true, "the review of pull request #207 ended"},
		{"ai/issue-209", true, "issue #209 closed"},
		// the open pull request #214 vetoes the claim of its closed issue
		{"ai/issue-205", false, ""},
		// a merged pull request claims neither its head nor its review
		{"ai/issue-204", false, ""},
		{"ai/review-206", false, ""},
		// a review leg of an open pull request stays
		{"ai/review-214", false, ""},
		{"feat/loose", false, ""},
	}
	for _, c := range cases {
		claimed, why := f.claims(c.branch)
		if claimed != c.claimed || why != c.why {
			t.Errorf("claims(%q) = %v, %q; want %v, %q", c.branch, claimed, why, c.claimed, c.why)
		}
	}
	if !f.ready {
		t.Errorf("joinForgeLists left the read not ready")
	}
	// a read that failed claims nothing
	var failed forgeClosed
	if claimed, why := failed.claims("ai/issue-198"); claimed || why != "" {
		t.Errorf("a read that failed claimed %q", why)
	}
}
