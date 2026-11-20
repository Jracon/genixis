package main

import (
	"testing"
)

// The windowed spawn names the session that ideBuild creates: the builder
// gives the session sessionName of the same project argument (cmd_ide.go),
// so the diagnostic prints that sanitized name, never the raw project
// name, which can hold a tmux target separator (issue #382).
func TestSpawnWindowDiagNamesTheCreatedSession(t *testing.T) {
	for _, tc := range []struct {
		branch  string
		project string
		want    string
	}{
		{"ai/issue-382", "genixis", `ide window "ai/issue-382" in tmux session "genixis"`},
		{"ai/x", "my.project", `ide window "ai/x" in tmux session "my_project"`},
		{"ai/x", "demo v2.0", `ide window "ai/x" in tmux session "demo_v2_0"`},
		{"ai/x", `it "quotes" $name`, `ide window "ai/x" in tmux session "it_quotes_name"`},
	} {
		if got := spawnWindowDiag(tc.branch, tc.project); got != tc.want {
			t.Errorf("spawnWindowDiag(%q, %q) = %q, want %q", tc.branch, tc.project, got, tc.want)
		}
	}
}
