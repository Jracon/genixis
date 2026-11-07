package main

import (
	"strings"
	"testing"

	"genixis/project/internal/coord"
)

// The board tests cover the join on plain data: the closing-keyword reader,
// the two join keys, the row kinds, and the tea list shapes that tea 0.16
// prints.

func TestClosingNumbers(t *testing.T) {
	body := "Closes #181, closes #102. It also fixes #7. No keyword names #99 alone, and closure #5 is no keyword."
	got := closingNumbers(body)
	want := []int{181, 102, 7}
	if len(got) != len(want) {
		t.Fatalf("closingNumbers(%q) = %v, want %v", body, got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("closingNumbers(%q) = %v, want %v", body, got, want)
		}
	}
}

func TestBoardJoin(t *testing.T) {
	issues := []boardIssue{
		{Number: "181", Title: "the rig"},
		{Number: "102", Title: "the board"},
	}
	pulls := []boardPull{
		{Number: "190", Title: "the rig lands", Body: "Closes #181", Head: "ai/issue-181"},
		// a pull request that closes an issue that is not open: no issue row
		// carries it, so it gets its own row
		{Number: "191", Title: "the close fix", Body: "Closes #182", Head: "ai/issue-182"},
	}
	f := &frontier{
		base: "main",
		entries: []coord.FrontierEntry{
			{Branch: "ai/issue-181", Worktree: "/demo/ai-issue-181"},
			{Branch: "review/pr-190", Worktree: "/demo/review-pr-190"},
			{Branch: "ai/issue-182", Worktree: "/demo/ai-issue-182"},
			{Branch: "feat/loose"},
		},
		worktrees: []worktreeReport{
			{branch: "main", main: true, path: "/demo/main"},
			{branch: "ai/issue-181", dirty: true, path: "/demo/ai-issue-181"},
			{branch: "review/pr-190", path: "/demo/review-pr-190"},
			{branch: "ai/issue-182", path: "/demo/ai-issue-182"},
		},
	}
	rows := boardJoin(issues, pulls, f)
	if len(rows) != 4 {
		t.Fatalf("rows = %d, want 4 (two issues, one unclosed pull, one loose branch): %+v", len(rows), rows)
	}
	rig, board, unclosed, loose := rows[0], rows[1], rows[2], rows[3]
	if rig.issue != 181 || rig.pull != 190 || rig.branch != "ai/issue-181" {
		t.Errorf("the issue row joins the wrong work: %+v", rig)
	}
	if rig.worktree != "ai-issue-181" || !rig.dirty {
		t.Errorf("the issue row misses the dirty worktree: %+v", rig)
	}
	if rig.review != "review-pr-190" || rig.reviewDirty {
		t.Errorf("the issue row misses the review worktree: %+v", rig)
	}
	if board.issue != 102 || board.pull != 0 || board.stateLine() != "no pull request" {
		t.Errorf("an issue without a pull request must say so: %+v", board)
	}
	if unclosed.pull != 191 || unclosed.branch != "ai/issue-182" || unclosed.worktree != "ai-issue-182" {
		t.Errorf("a pull request that no issue row carries needs its own row: %+v", unclosed)
	}
	if loose.branch != "feat/loose" || loose.worktree != "" {
		t.Errorf("the loose branch row is wrong: %+v", loose)
	}
}

func TestTeaListShapesParse(t *testing.T) {
	issuesRaw := `[{"index":"182","title":"project close refuses","state":"open","author":"claude-bot","milestone":"","labels":"","owner":"jracon","repo":"genixis"}]`
	var issues []boardIssue
	if err := jsonUnmarshal([]byte(issuesRaw), &issues); err != nil {
		t.Fatalf("the issue list of tea did not parse: %v", err)
	}
	if len(issues) != 1 || issues[0].Number != "182" || issues[0].Title != "project close refuses" {
		t.Fatalf("issues = %+v", issues)
	}
	pullsRaw := `[{"index":"180","title":"sweep","body":"References #74 without a closing word.","head":"review/agent-text-rules","base":"main"}]`
	var pulls []boardPull
	if err := jsonUnmarshal([]byte(pullsRaw), &pulls); err != nil {
		t.Fatalf("the pull request list of tea did not parse: %v", err)
	}
	if len(pulls) != 1 || pulls[0].Head != "review/agent-text-rules" || len(closingNumbers(pulls[0].Body)) != 0 {
		t.Fatalf("pulls = %+v", pulls)
	}
}

func TestRenderBoard(t *testing.T) {
	rows := []boardRow{
		{issue: 102, title: "the board"},
		{issue: 181, title: "the rig", pull: 190, branch: "ai/issue-181", worktree: "ai-issue-181", dirty: true, review: "review-pr-190"},
	}
	text := renderBoard("/demo", rows, boardStats{issues: 2, pulls: 1, branches: 3})
	for _, want := range []string{
		"2 open issues", "#102", "no pull request", "#181", "pull #190 head ai/issue-181",
		"worktree ai-issue-181 (dirty)", "review review-pr-190",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("the board misses %q:\n%s", want, text)
		}
	}
}
