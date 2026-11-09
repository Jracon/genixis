package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"genixis/project/internal/spec"
)

// The pane paths of lmk and btw (tmux, claude panes) stay outside these
// tests; this file pins the pure parts they rest on — the prompt line, the
// memory note, the stdin context — and the paths that need no pane.

func TestAskPrompt(t *testing.T) {
	cases := []struct {
		name    string
		kind    string
		words   []string
		context string
		want    string
	}{
		{
			name:  "a question",
			kind:  "ask",
			words: []string{"why", "does", "the", "layout", "skip", "34%"},
			want:  "ask: why does the layout skip 34%",
		},
		{
			name:    "a question with context",
			kind:    "ask",
			words:   []string{"what", "changed"},
			context: ".scratch/ask-1.md",
			want:    "ask: what changed (context: .scratch/ask-1.md)",
		},
		{
			name:  "a fact carries the memory instruction",
			kind:  "btw",
			words: []string{"the", "mirror", "is", "the", "fallback"},
			want: "btw: the mirror is the fallback; absorb this fact, " +
				"and write it to the shared project memory when it must outlive this session",
		},
	}
	for _, tc := range cases {
		if got := askPrompt(tc.kind, tc.words, tc.context); got != tc.want {
			t.Errorf("%s: askPrompt = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// A newline in pasted text would run a line of it on its own when the pane
// holds a shell, so the prompt line flattens every run of them.
func TestAskLineFlattens(t *testing.T) {
	got := askLine([]string{"one\ntwo\tthree", "", "four\r\nfive"})
	if want := "one two three four five"; got != want {
		t.Errorf("askLine = %q, want %q", got, want)
	}
}

func TestAskNoteShape(t *testing.T) {
	when := time.Date(2026, 11, 8, 23, 15, 7, 0, time.UTC)
	name := askNoteName(when)
	if name != "btw-2026-11-08-231507" {
		t.Errorf("askNoteName = %q", name)
	}
	note := string(askNote(name, "the ci bot commit fits the standard.\nLeave it."))
	want := `---
name: btw-2026-11-08-231507
description: the ci bot commit fits the standard. Leave it.
metadata:
  type: project
---

the ci bot commit fits the standard.
Leave it.
`
	if note != want {
		t.Errorf("askNote =\n%s\nwant\n%s", note, want)
	}
	line := askNoteIndexLine(name, "the ci bot commit fits the standard. Leave it.")
	want = "- [btw 2026-11-08-231507](btw-2026-11-08-231507.md) — the ci bot commit fits the standard. Leave it."
	if line != want {
		t.Errorf("askNoteIndexLine = %q, want %q", line, want)
	}
	// a long fact cuts at a word boundary, in the note and in the index line
	long := strings.Repeat("word ", 40)
	if got := askOneLine(long, 20); len(got) > 24 || !strings.HasSuffix(got, "...") {
		t.Errorf("askOneLine = %q, want a cut of at most 20 characters plus an ellipsis", got)
	}
}

// A btw that finds no pane writes the note into the shared memory of the
// project, where the next session reads it: the dated file, and the pointer
// line in the index.
func TestBtwWithoutPaneWritesMemoryNote(t *testing.T) {
	s := newScratch(t)
	defer chdir(t, s.main)()
	var stdout, stderr strings.Builder
	code := cmdAsk("btw", []string{"the", "windows", "build", "needs", "nix", "fmt"}, strings.NewReader(""), &stdout, &stderr)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d, stderr = %q", code, stderr.String())
	}
	memory := filepath.Join(s.dir, ".claude", "memory")
	entries, err := os.ReadDir(memory)
	if err != nil || len(entries) != 2 { // the note and MEMORY.md
		t.Fatalf("memory directory = %v, %v", entries, err)
	}
	var notes []string
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "btw-") {
			notes = append(notes, entry.Name())
		}
	}
	if len(notes) != 1 {
		t.Fatalf("the dated note is missing: %v", entries)
	}
	note, err := os.ReadFile(filepath.Join(memory, notes[0]))
	if err != nil || !strings.Contains(string(note), "the windows build needs nix fmt") {
		t.Errorf("note = %q, %v", string(note), err)
	}
	index, err := os.ReadFile(filepath.Join(memory, "MEMORY.md"))
	if err != nil || !strings.Contains(string(index), "the windows build needs nix fmt") {
		t.Errorf("MEMORY.md = %q, %v", string(index), err)
	}
	if !strings.Contains(string(index), "("+notes[0]+")") {
		t.Errorf("MEMORY.md names no %s: %q", notes[0], string(index))
	}
}

// A btw with no pane and no project around it has nowhere to land the fact.
func TestBtwOutsideProjectFails(t *testing.T) {
	defer chdir(t, t.TempDir())()
	var stdout, stderr strings.Builder
	code := cmdAsk("btw", []string{"a", "fact"}, strings.NewReader(""), &stdout, &stderr)
	if spec.ExitCode(code) != spec.NotFound {
		t.Fatalf("exit = %d, want %d, stderr = %q", code, spec.NotFound, stderr.String())
	}
}

// lmk is the standalone call: one claude --print in the checkout, whose
// prompt holds the question, the context pointer, and the answer
// instruction.
func TestLmkPrompt(t *testing.T) {
	tail := "\nAnswer this question about this repository. Keep the answer short and cite the files you read."
	if got := lmkPrompt([]string{"what", "changed"}, ".scratch/lmk-1.md"); got != "what changed (context: .scratch/lmk-1.md)"+tail {
		t.Errorf("lmkPrompt = %q", got)
	}
	if got := lmkPrompt([]string{"plain"}, ""); got != "plain"+tail {
		t.Errorf("lmkPrompt without context = %q", got)
	}
}

// Piped stdin is context: it lands under .scratch/ of the checkout, and the
// prompt of the standalone call names the file.
func TestLmkStdinBecomesContext(t *testing.T) {
	s := newScratch(t)
	defer chdir(t, s.main)()
	sawFile := filepath.Join(t.TempDir(), "args")
	s.fakeBin(t, "claude", "#!/bin/sh\nprintf '%s\\n' \"$*\" > "+sawFile+"\n")
	var stdout, stderr strings.Builder
	code := cmdLmk([]string{"what", "changed"},
		strings.NewReader("1838da8 clean the branches\n"), &stdout, &stderr)
	if spec.ExitCode(code) != spec.Success {
		t.Fatalf("exit = %d, stderr = %q", code, stderr.String())
	}
	data, err := os.ReadFile(sawFile)
	if err != nil {
		t.Fatal(err)
	}
	saw := strings.TrimSpace(string(data))
	if !strings.HasPrefix(saw, "--print -- what changed (context: .scratch/lmk-") {
		t.Errorf("claude args = %q", saw)
	}
	if !strings.Contains(saw, ".md)\nAnswer this question") {
		t.Errorf("claude args = %q", saw)
	}
	rel := strings.TrimPrefix(saw, "--print -- what changed (context: ")
	rel = strings.TrimSuffix(rel[:strings.Index(rel, "\n")], ")")
	if _, err := os.Stat(filepath.Join(s.main, rel)); err != nil {
		t.Errorf("the context file the prompt names does not exist: %v", err)
	}
	if body, _ := os.ReadFile(filepath.Join(s.main, rel)); string(body) != "1838da8 clean the branches" {
		t.Errorf("context file = %q", string(body))
	}
}

// A bare -- ends the options: the words after it keep a leading dash, and
// a --context after it is a word, not an option. The ask mapping of the
// editor sends the question behind a --.
func TestAskParserEndOfOptions(t *testing.T) {
	var stderr strings.Builder
	contextFile, words, ok := parseAskArgs("ask", []string{"--", "why", "--deep"}, &stderr)
	if !ok || contextFile != "" || strings.Join(words, " ") != "why --deep" {
		t.Errorf("dash word after --: context = %q, words = %v, ok = %v", contextFile, words, ok)
	}
	_, words, ok = parseAskArgs("ask", []string{"--", "--context", "why"}, &stderr)
	if !ok || strings.Join(words, " ") != "--context why" {
		t.Errorf("--context after --: words = %v, ok = %v", words, ok)
	}
	ctx := filepath.Join(t.TempDir(), "bundle.md")
	if err := os.WriteFile(ctx, []byte("context\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	contextFile, words, ok = parseAskArgs("ask", []string{"--context", ctx, "--", "why"}, &stderr)
	if !ok || contextFile != ctx || strings.Join(words, " ") != "why" {
		t.Errorf("--context before --: context = %q, words = %v, ok = %v", contextFile, words, ok)
	}
}

func TestAskArgumentErrors(t *testing.T) {
	var stdout, stderr strings.Builder
	if code := cmdAsk("ask", nil, strings.NewReader(""), &stdout, &stderr); spec.ExitCode(code) != spec.ArgError {
		t.Errorf("no words: exit = %d, want %d", code, spec.ArgError)
	}
	if code := cmdAsk("btw", []string{"--nope", "x"}, strings.NewReader(""), &stdout, &stderr); spec.ExitCode(code) != spec.ArgError {
		t.Errorf("unknown option: exit = %d, want %d", code, spec.ArgError)
	}
	if code := cmdLmk([]string{"--context"}, strings.NewReader(""), &stdout, &stderr); spec.ExitCode(code) != spec.ArgError {
		t.Errorf("--context without a value: exit = %d, want %d", code, spec.ArgError)
	}
	if code := cmdLmk([]string{"--context", "/no/such/file.md", "q"}, strings.NewReader(""), &stdout, &stderr); spec.ExitCode(code) != spec.ArgError {
		t.Errorf("missing context file: exit = %d, want %d", code, spec.ArgError)
	}
}
