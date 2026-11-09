package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"genixis/project/internal/spec"
)

// This file is the ask and tell side of the session plumbing (issue #189):
// `project ask` carries a question to the claude pane of the current
// checkout, `project btw` carries a fact, and `project lmk` answers one
// quick documentation question with a standalone claude call that involves
// no pane. The pane flows find their pane through the @ide_dir and @ide_agent
// window options of the ide window, and they paste their text through the
// tmux buffer, which is the workaround for the typed pane input of macOS
// that the claude start script uses.

// parseAskArgs reads the shared argument form of the three commands:
// [--context <file>] then the words of the question or fact.
func parseAskArgs(kind string, argv []string, stderr io.Writer) (string, []string, bool) {
	contextFile := ""
	var words []string
	for i := 0; i < len(argv); i++ {
		arg := argv[i]
		switch {
		case arg == "--context":
			if i+1 >= len(argv) {
				fail(stderr, spec.ArgError, "--context needs a file path (see project help %s)", kind)
				return "", nil, false
			}
			i++
			contextFile = argv[i]
		case strings.HasPrefix(arg, "-") && arg != "-":
			fail(stderr, spec.ArgError, "unknown option %s (see project help %s)", arg, kind)
			return "", nil, false
		default:
			words = append(words, arg)
		}
	}
	if len(words) == 0 {
		fail(stderr, spec.ArgError, "%s needs a %s as its arguments (see project help %s)", kind, askNoun(kind), kind)
		return "", nil, false
	}
	if contextFile != "" {
		if _, err := os.Stat(contextFile); err != nil {
			fail(stderr, spec.ArgError, "context file %s does not exist", contextFile)
			return "", nil, false
		}
	}
	return contextFile, words, true
}

// askContext reads the context of the question: a --context file passes
// through, piped stdin lands under <root>/.scratch/ and its path replaces
// the option. The return is the path as the prompt names it.
func askContext(kind string, argv []string, stdin io.Reader, stderr io.Writer) (string, []string, bool) {
	contextFile, words, ok := parseAskArgs(kind, argv, stderr)
	if !ok {
		return "", nil, false
	}
	root := gitTopLevel(cwd())
	if rel, piped := askStdinContext(stdin, root, kind); piped {
		if contextFile != "" {
			fail(stderr, spec.ArgError, "give either --context or piped input, not both")
			return "", nil, false
		}
		contextFile = rel
	}
	return contextFile, words, true
}

// cmdLmk implements `project lmk`: one quick documentation question,
// answered by one standalone claude call in the current checkout. No pane is
// searched and no live session is involved; the call reads the repository
// with its own tools and its answer lands on this terminal.
func cmdLmk(argv []string, stdin io.Reader, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, "lmk")
		return spec.Success
	}
	contextFile, words, ok := askContext("lmk", argv, stdin, stderr)
	if !ok {
		return spec.ArgError
	}
	if !commandExists("claude") {
		return fail(stderr, spec.Unavailable, "lmk: claude is not on PATH")
	}
	// the call runs at the checkout root, so a context path of the prompt
	// resolves the same way as it does for a session of the worktree
	cmd := exec.Command("claude", "--print", "--", lmkPrompt(words, contextFile))
	cmd.Dir = gitTopLevel(cwd())
	cmd.Stdin = os.Stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		return fail(stderr, spec.GeneralError, "claude: %v", err)
	}
	return spec.Success
}

// lmkPrompt builds the prompt of the standalone call: the question, the
// pointer to the context, and the instruction that keeps the answer short
// and rooted in the files of the repository.
func lmkPrompt(words []string, contextRel string) string {
	line := askLine(words)
	if contextRel != "" {
		line += " (context: " + contextRel + ")"
	}
	return line + "\nAnswer this question about this repository. Keep the answer short and cite the files you read."
}

// cmdAsk implements `project ask` and `project btw`. kind is "ask" or "btw".
// stdin carries context: text that arrives on a pipe lands in .scratch/ and
// the prompt names the file, so the pane input stays short.
func cmdAsk(kind string, argv []string, stdin io.Reader, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, kind)
		return spec.Success
	}
	contextFile, words, ok := askContext(kind, argv, stdin, stderr)
	if !ok {
		return spec.ArgError
	}
	root := gitTopLevel(cwd())
	prompt := askPrompt(kind, words, contextFile)

	if pane := askAgentPane(root); pane != "" {
		if err := askPaste(pane, prompt); err != nil {
			return fail(stderr, spec.GeneralError, "%v", err)
		}
		printfDiag(stderr, "%s: sent to the claude pane of %s", kind, root)
		return spec.Success
	}

	// no live pane: ask starts claude here, btw lands in the shared memory
	if kind == "btw" {
		project, ok := insideProject(cwd())
		if !ok {
			return fail(stderr, spec.NotFound, "btw: no claude pane here and no project around it, so no shared memory to write to")
		}
		note, err := writeAskNote(project, askLine(words))
		if err != nil {
			return fail(stderr, spec.GeneralError, "%v", err)
		}
		printfDiag(stderr, "btw: no claude pane; wrote %s for the next session", note)
		return spec.Success
	}
	if !commandExists("claude") {
		return fail(stderr, spec.Unavailable, "ask: no claude pane for %s and claude is not on PATH", root)
	}
	printfDiag(stderr, "ask: no claude pane; starting claude here with the prompt entered")
	// claude starts at the checkout root, the working directory of the pane
	// session it stands in for, so the context path of the prompt resolves
	// the same way for both
	cmd := exec.Command("claude", "--", prompt)
	cmd.Dir = root
	cmd.Stdin = os.Stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		return fail(stderr, spec.GeneralError, "claude: %v", err)
	}
	return spec.Success
}

// askNoun is what one command carries: a question or a fact.
func askNoun(kind string) string {
	if kind == "btw" {
		return "fact"
	}
	return "question"
}

// askStdinContext reads piped stdin as the context of the question and
// writes it under <root>/.scratch/. A terminal answers false, and so does
// empty input: nvim calls this command with --context while its own stdin is
// a closed pipe, which reads as empty here. The return is the path as the
// prompt names it, relative to the working directory.
func askStdinContext(stdin io.Reader, root, kind string) (string, bool) {
	if f, ok := stdin.(*os.File); ok && isTerminal(f) {
		return "", false
	}
	data, err := io.ReadAll(stdin)
	if err != nil || len(bytes.TrimSpace(data)) == 0 {
		return "", false
	}
	dir := root
	if dir == "" {
		dir = cwd()
	}
	if err := os.MkdirAll(filepath.Join(dir, ".scratch"), 0o755); err != nil {
		return "", false
	}
	rel := kind + "-" + time.Now().Format("2006-01-02-150405") + ".md"
	if err := os.WriteFile(filepath.Join(dir, ".scratch", rel), bytes.TrimRight(data, "\n"), 0o644); err != nil {
		return "", false
	}
	return filepath.Join(".scratch", rel), true
}

// askLine flattens words into the one line the pane receives: every run of
// whitespace becomes one space, because a bracketed paste of a multi-line
// text into a shell runs a line of it on its own when claude already left
// the pane.
func askLine(words []string) string {
	space := regexp.MustCompile(`\s+`)
	return strings.TrimSpace(space.ReplaceAllString(strings.Join(words, " "), " "))
}

// askPrompt builds the one line that goes to the session: the marker of the
// channel, the question or fact, the pointer to the context bundle, and, for
// a fact, the instruction that keeps durable facts in the shared memory.
func askPrompt(kind string, words []string, contextRel string) string {
	line := kind + ": " + askLine(words)
	if contextRel != "" {
		line += " (context: " + contextRel + ")"
	}
	if kind == "btw" {
		line += "; absorb this fact, and write it to the shared project memory when it must outlive this session"
	}
	return line
}

// askAgentPane finds the claude pane of the ide window of dir: the window
// whose @ide_dir is dir, and its @ide_agent pane. The tmux server and its
// panes live on the host of the session, so the lookup also works behind a
// plain ssh login into that host. A window with no agent pane, or an agent
// pane that no longer answers, counts as no pane.
func askAgentPane(dir string) string {
	if dir == "" {
		return ""
	}
	window := ideWindow(dir)
	if window == "" {
		return ""
	}
	agent := tmuxWindowOption(window, "@ide_agent")
	if agent == "" {
		return ""
	}
	if _, err := tmux("display-message", "-p", "-t", agent, "#{pane_id}"); err != nil {
		return ""
	}
	return agent
}

// askPaste puts one line into the pane through the tmux buffer and submits
// it. load-buffer - reads the bytes from stdin, so the text needs no shell
// quoting on its way in, and paste-buffer -p wraps it as a bracketed paste:
// the pane sees one paste, whatever the text holds. The Enter that follows
// submits the line in the claude input.
func askPaste(pane, line string) error {
	load := exec.Command("tmux", "load-buffer", "-")
	load.Stdin = strings.NewReader(line)
	if out, err := load.CombinedOutput(); err != nil {
		return fmt.Errorf("tmux load-buffer: %v: %s", err, bytes.TrimSpace(out))
	}
	if _, err := tmux("paste-buffer", "-p", "-t", pane); err != nil {
		return fmt.Errorf("tmux paste-buffer: %v", err)
	}
	if _, err := tmux("send-keys", "-t", pane, "Enter"); err != nil {
		return fmt.Errorf("tmux send-keys: %v", err)
	}
	return nil
}

// askNoteName is the file name of one dated note.
func askNoteName(now time.Time) string {
	return "btw-" + now.Format("2006-01-02-150405")
}

// askNote is the note of a fact in the memory format: the frontmatter that
// the memory reader needs, then the fact as it arrived, newlines kept.
func askNote(name, fact string) []byte {
	var b bytes.Buffer
	b.WriteString("---\n")
	fmt.Fprintf(&b, "name: %s\n", name)
	fmt.Fprintf(&b, "description: %s\n", askOneLine(fact, 100))
	b.WriteString("metadata:\n  type: project\n")
	b.WriteString("---\n\n")
	b.WriteString(strings.TrimSpace(fact))
	b.WriteString("\n")
	return b.Bytes()
}

// askNoteIndexLine is the pointer line that MEMORY.md carries, so the next
// session reads the note without a lookup of its own.
func askNoteIndexLine(name, fact string) string {
	title := strings.TrimPrefix(name, "btw-")
	return fmt.Sprintf("- [btw %s](%s.md) — %s", title, name, askOneLine(fact, 60))
}

// askOneLine flattens text to one line and cuts it to width, with an
// ellipsis when something went.
func askOneLine(text string, width int) string {
	line := askLine([]string{text})
	if len(line) <= width {
		return line
	}
	cut := line[:width]
	if i := strings.LastIndexAny(cut, " "); i > width/2 {
		cut = cut[:i]
	}
	return strings.TrimRight(cut, " ") + " ..."
}

// writeAskNote writes the fact of a btw that found no pane into the shared
// memory of the project: one dated note in the memory format, plus the
// pointer line in MEMORY.md. It returns the note path.
func writeAskNote(project, fact string) (string, error) {
	dir := filepath.Join(project, ".claude", "memory")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	name := askNoteName(time.Now())
	note := filepath.Join(dir, name+".md")
	if err := os.WriteFile(note, askNote(name, fact), 0o644); err != nil {
		return "", err
	}
	index := filepath.Join(dir, "MEMORY.md")
	data, err := os.ReadFile(index)
	if err != nil {
		data = []byte("# Memory index\n\n")
	}
	if len(data) > 0 && !bytes.HasSuffix(data, []byte("\n")) {
		data = append(data, '\n')
	}
	data = append(data, []byte(askNoteIndexLine(name, fact)+"\n")...)
	return note, os.WriteFile(index, data, 0o644)
}
