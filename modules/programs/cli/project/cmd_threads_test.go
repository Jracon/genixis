package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"genixis/project/internal/spec"
)

// The tests of this file drive the thread store (docs/threads.md) through
// run() in process, from inside a scratch repository: the write verbs lay
// the files of the format, the read verbs print the reading order, and each
// argument error names its rule. The store rides the plain file system, so
// no git plumbing and no fake binary takes part.

// threadsScratch is a scratch whose repository names an agent login, so the
// author default of the write verbs answers.
func threadsScratch(t *testing.T) *scratch {
	t.Helper()
	s := newScratch(t)
	git(t, s.main, "config", "user.name", "claude-bot")
	restore := chdir(t, s.main)
	t.Cleanup(restore)
	return s
}

// bodyFile writes one scratch body and answers its path.
func bodyFile(t *testing.T, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "body.md")
	must(t, os.WriteFile(path, []byte(text), 0o644))
	return path
}

// threadPath joins the store path of the scratch with the parts of one
// thread file.
func threadPath(s *scratch, parts ...string) string {
	return filepath.Join(append([]string{s.main, "threads"}, parts...)...)
}

// One full round of the store: new writes thread.md of the format, add
// writes the event files in sequence, list prints the thread line, and show
// prints the reading order with the header fields of each file.
func TestThreadsRoundTrip(t *testing.T) {
	s := threadsScratch(t)

	body := bodyFile(t, "The review of pull request 702.\n\nThe branch holds one commit.\n")
	code, _, stderr := s.run("threads", "new", "review-702",
		"--title", "review verdict of pull request 702", "--origin", "https://forgejo.example/jracon/genixis/pulls/702",
		"--body-file", body)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("new exit = %d: %s", code, stderr)
	}
	raw, err := os.ReadFile(threadPath(s, "review-702", "thread.md"))
	must(t, err)
	text := string(raw)
	for _, want := range []string{
		"---\n",
		"title: review verdict of pull request 702\n",
		"author: claude-bot\n",
		"status: open\n",
		"origin: https://forgejo.example/jracon/genixis/pulls/702\n",
		"---\n\nThe review of pull request 702.\n",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("thread.md misses %q:\n%s", want, text)
		}
	}
	if !strings.HasPrefix(text, "---\n") {
		t.Errorf("thread.md opens with no frontmatter block:\n%s", text)
	}

	for _, event := range []struct {
		typ  string
		text string
	}{
		{"comment", "The gate ran green.\n"},
		{"verdict", "APPROVED\n"},
	} {
		code, _, stderr = s.run("threads", "add", "review-702",
			"--type", event.typ, "--body-file", bodyFile(t, event.text))
		if spec.ExitCode(code) != spec.Success {
			t.Fatalf("add %s exit = %d: %s", event.typ, code, stderr)
		}
	}
	for _, name := range []string{
		"0001-comment-claude-bot.md",
		"0002-verdict-claude-bot.md",
	} {
		if info, err := os.Stat(threadPath(s, "review-702", name)); err != nil || info.IsDir() {
			t.Errorf("event file %s is missing: %v", name, err)
		}
	}

	// the reading order: the body first, then each event by sequence
	code, stdout, stderr := s.run("threads", "show", "review-702")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("show exit = %d: %s", code, stderr)
	}
	last := -1
	for _, want := range []string{
		"review-702 — review verdict of pull request 702",
		"status open",
		"origin https://forgejo.example/jracon/genixis/pulls/702",
		"The review of pull request 702.",
		"--- event 0001 comment, author claude-bot",
		"The gate ran green.",
		"--- event 0002 verdict, author claude-bot",
		"APPROVED",
	} {
		at := strings.Index(stdout, want)
		if at < 0 {
			t.Errorf("show output misses %q:\n%s", want, stdout)
			continue
		}
		if at < last {
			t.Errorf("show output holds %q before the part that precedes it:\n%s", want, stdout)
		}
		last = at
	}

	code, stdout, stderr = s.run("threads", "list")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("list exit = %d: %s", code, stderr)
	}
	want := "review-702  open  2 events  review verdict of pull request 702"
	if !strings.Contains(stdout, want) {
		t.Errorf("list line = %q, want %q", stdout, want)
	}
}

// An event that a hand wrote takes the sequence above the highest one that
// the directory holds, so a hand-made file and a tool-made file share one
// order.
func TestThreadsAddNumbersAboveTheLastEvent(t *testing.T) {
	s := threadsScratch(t)
	code, _, stderr := s.run("threads", "new", "t", "--title", "a thread", "--body-file", bodyFile(t, "body\n"))
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("new exit = %d: %s", code, stderr)
	}
	must(t, os.WriteFile(threadPath(s, "t", "0005-comment-claude-bot.md"),
		[]byte("---\ntype: comment\nauthor: claude-bot\ndate: 2026-11-27T20:00:00Z\n---\n\nhand written\n"), 0o644))
	code, _, stderr = s.run("threads", "add", "t", "--type", "comment", "--body-file", bodyFile(t, "next\n"))
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("add exit = %d: %s", code, stderr)
	}
	if info, err := os.Stat(threadPath(s, "t", "0006-comment-claude-bot.md")); err != nil || info.IsDir() {
		t.Errorf("the next event file is missing: %v", err)
	}
	if info, err := os.Stat(threadPath(s, "t", "0001-comment-claude-bot.md")); err == nil {
		t.Errorf("the sequence restarted at 1 below a hand-written 0005: %v", info)
	}
}

// The argument rules of the write verbs: the slug grammar, the title, the
// status, the type, the body, and the author grammar each name their rule,
// and a repeated new refuses the thread that exists.
func TestThreadsWriteValidatesArguments(t *testing.T) {
	s := threadsScratch(t)
	s.run("threads", "new", "exists", "--title", "a thread", "--body-file", bodyFile(t, "body\n"))

	for _, argv := range [][]string{
		{"threads", "new", "Bad_Slug", "--title", "t", "--body-file", bodyFile(t, "b\n")},
		{"threads", "new", "ends-in-", "--title", "t", "--body-file", bodyFile(t, "b\n")},
		{"threads", "new", "t"},
		{"threads", "new", "t", "--title", ""},
		{"threads", "new", "t", "--title", "t", "--status", "wet", "--body-file", bodyFile(t, "b\n")},
		{"threads", "new", "t", "--title", "t", "--body-file", "/no/such/body.md"},
		{"threads", "new", "t", "--title", "t", "--body-file", bodyFile(t, "b\n"), "--author", "Not A Login"},
		{"threads", "add", "exists", "--body-file", bodyFile(t, "b\n")},
		{"threads", "add", "exists", "--type", "note", "--body-file", bodyFile(t, "b\n")},
		{"threads"},
		{"threads", "frobnicate"},
	} {
		code, _, stderr := s.run(argv...)
		if spec.ExitCode(code) != spec.ArgError {
			t.Errorf("%v exit = %d, want %d: %s", argv, code, spec.ArgError, stderr)
		}
		if !strings.Contains(stderr, "project help threads") {
			t.Errorf("%v stderr names no help screen: %q", argv, stderr)
		}
	}

	// the refusal of a repeated new is a general error, not an argument error
	code, _, stderr := s.run("threads", "new", "exists", "--title", "t", "--body-file", bodyFile(t, "b\n"))
	if spec.ExitCode(code) != spec.GeneralError || !strings.Contains(stderr, "the thread exists exists") {
		t.Errorf("repeated new exit = %d, stderr = %q", code, stderr)
	}

	// an unknown slug of show and of add answers not found
	code, _, stderr = s.run("threads", "show", "no-such-thread")
	if spec.ExitCode(code) != spec.NotFound || !strings.Contains(stderr, "no thread no-such-thread") {
		t.Errorf("show unknown exit = %d, stderr = %q", code, stderr)
	}
	code, _, stderr = s.run("threads", "add", "no-such-thread", "--type", "comment", "--body-file", bodyFile(t, "b\n"))
	if spec.ExitCode(code) != spec.NotFound || !strings.Contains(stderr, "no thread no-such-thread") {
		t.Errorf("add unknown exit = %d, stderr = %q", code, stderr)
	}

	// list holds extra words for no caller
	code, _, stderr = s.run("threads", "list", "extra")
	if spec.ExitCode(code) != spec.ArgError {
		t.Errorf("list with a word exit = %d: %s", code, stderr)
	}
}

// Outside a repository no store exists, and an empty store lists nothing:
// both answer exit 0 or the not-found code of the table, never a crash.
func TestThreadsOutsideARepositoryAndEmptyStore(t *testing.T) {
	s := newScratch(t)
	restore := chdir(t, s.home)
	code, _, stderr := s.run("threads", "list")
	restore()
	if spec.ExitCode(code) != spec.NotFound {
		t.Errorf("list outside a repository exit = %d, want %d: %s", code, spec.NotFound, stderr)
	}

	restore = chdir(t, s.main)
	code, stdout, stderr := s.run("threads", "list")
	restore()
	if spec.ExitCode(code) != spec.Success || strings.TrimSpace(stdout) != "" {
		t.Errorf("empty list exit = %d, stdout = %q, stderr = %q", code, stdout, stderr)
	}
}

// The author default lowers the git identity of the checkout into the login
// shape, and a checkout whose git names no user asks for the flag.
func TestThreadsAuthorFromTheGitIdentity(t *testing.T) {
	s := threadsScratch(t)
	git(t, s.main, "config", "user.name", "A Leg Bot")
	code, _, stderr := s.run("threads", "new", "t", "--title", "a thread", "--body-file", bodyFile(t, "b\n"))
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("new exit = %d: %s", code, stderr)
	}
	if info, err := os.Stat(threadPath(s, "t", "thread.md")); err != nil || info.IsDir() {
		t.Fatalf("thread.md is missing: %v", err)
	}
	raw, err := os.ReadFile(threadPath(s, "t", "thread.md"))
	must(t, err)
	if !strings.Contains(string(raw), "author: a-leg-bot\n") {
		t.Errorf("thread.md author is not the lowered identity:\n%s", raw)
	}

	git(t, s.main, "config", "user.name", "")
	code, _, stderr = s.run("threads", "add", "t", "--type", "comment", "--body-file", bodyFile(t, "b\n"))
	if spec.ExitCode(code) != spec.ArgError || !strings.Contains(stderr, "git names no user") {
		t.Errorf("add without an identity exit = %d, stderr = %q", code, stderr)
	}
}

// A hand-made file without a frontmatter block stays readable: show prints
// its whole text as the body, and list names the fields it lacks.
func TestThreadsShowReadsAHandMadeFile(t *testing.T) {
	s := threadsScratch(t)
	must(t, os.MkdirAll(threadPath(s, "plain"), 0o755))
	must(t, os.WriteFile(threadPath(s, "plain", "thread.md"), []byte("A body with no block.\n"), 0o644))
	code, stdout, stderr := s.run("threads", "show", "plain")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("show exit = %d: %s", code, stderr)
	}
	if !strings.Contains(stdout, "A body with no block.") {
		t.Errorf("show output misses the body of a hand-made file:\n%s", stdout)
	}
	code, stdout, _ = s.run("threads", "list")
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("list exit = %d", code)
	}
	if !strings.Contains(stdout, "plain  -  0 events") {
		t.Errorf("list line of a hand-made thread = %q", stdout)
	}
}
