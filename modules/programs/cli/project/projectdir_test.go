package main

import (
	"testing"
)

// sessionName carries the denylist of the ruling on issue #382. The test
// walks the class member by member, so a byte that the regex misses fails
// by name: beside the tmux target separators that the class always denied,
// every byte that no unquoted shell word of the consumers can carry goes
// to an underscore, because the name lands unquoted in the executed tab
// line of remoteSessionCommand and in pasted attach hints.
func TestSessionNameDeniesTheRulingClass(t *testing.T) {
	denied := "\"'`$;|&<>()*?[]{}.:"
	for _, r := range denied + "\t\n\f\r " {
		name := "a" + string(r) + "b"
		if got := sessionName(name); got != "a_b" {
			t.Errorf("sessionName(%q) = %q, want %q", name, got, "a_b")
		}
	}
	// a run of denied bytes becomes one underscore, whatever mixes in it
	if got := sessionName("a. :'b"); got != "a_b" {
		t.Errorf("sessionName of a run of denied bytes = %q, want %q", got, "a_b")
	}
	// the separators that the class always denied still go, alone and in a
	// name of this fleet
	if got := sessionName("my.project v2.0"); got != "my_project_v2_0" {
		t.Errorf("sessionName of a project name = %q, want %q", got, "my_project_v2_0")
	}
}

// The staying bytes of the ruling keep their place: each is literal in an
// unquoted word at the position where the consumers put the name, in fish
// and in the POSIX shells alike, and tmux carries a non-ASCII byte.
func TestSessionNameKeepsTheStayingBytes(t *testing.T) {
	staying := "-_/=,+%@^~#!azAZ09" + "grün€"
	if got := sessionName(staying); got != staying {
		t.Errorf("sessionName(%q) = %q, want the name unchanged", staying, got)
	}
}
