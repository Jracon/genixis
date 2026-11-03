package main

import (
	"crypto/rand"
	"fmt"
	"io"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"genixis/project/internal/backend"
	"genixis/project/internal/coord"
	"genixis/project/internal/spec"
)

// This file is part of the security spine (issue #74, standing principle 7):
// close and discard remove work. The steps run in one fixed order, each
// small enough to read line by line, and nothing is removed before every
// refusal check has passed. discard is close that throws work away, so only
// a person at a terminal may run it.

// cmdClose removes a worktree. close refuses while work is uncommitted and
// keeps a branch that is not merged. discard removes the work too, behind
// the terminal gate and a typed confirmation code.
func cmdClose(action string, argv []string, stdout, stderr io.Writer) spec.ExitCode {
	code, err := runClose(action, argv, stdout, stderr)
	if err != nil {
		printfDiag(stderr, "%s", err.err.Message)
	}
	return code
}

func runClose(action string, argv []string, stdout, stderr io.Writer) (spec.ExitCode, *toolError) {
	// discard runs only from a person's interactive terminal, never from an
	// agent: it refuses inside Claude Code and when stdin or stderr is not a
	// terminal
	if action == "discard" {
		if os.Getenv("CLAUDECODE") != "" {
			return spec.PermissionDenied, errPermission("discard runs only from a person's interactive terminal, never from an agent")
		}
		if !isTerminal(os.Stdin) || !isTerminal(os.Stderr) {
			return spec.PermissionDenied, errPermission("discard runs only from a person's interactive terminal, never from an agent")
		}
	}

	// a bare name is a worktree of the project this runs in, from any of
	// its checkouts or its directory; ./name is relative to here
	target := ""
	if len(argv) > 0 {
		target = argv[0]
	}
	if target == "" {
		target = "."
	}
	resolved, err := resolveCloseTarget(target)
	if err != nil {
		return spec.NotFound, err
	}
	tree := resolved
	dir := filepath.Dir(tree)
	mainDir := filepath.Join(dir, "main")
	if tree == mainDir || !isProjectDir(dir) {
		return spec.NotFound, errNotFound("%s is not a project worktree", tree)
	}
	branch := gitBackend.CurrentBranch(tree)

	// ---- the refusal checks. Nothing below the checks changes anything,
	// and every check that can refuse runs before the first removal.

	// included files are untracked, so git won't guard them: drop the links,
	// the discards, and the copies that still match main, and refuse while
	// any copy differs
	lists := includeLists{}
	if hasIncludeFiles(mainDir, dir) {
		lists = readIncludeLists(mainDir, dir)
	}
	// change nothing while there's uncommitted work: git worktree remove
	// would refuse, but only after the links and copies below were gone.
	// The links show up as untracked when the ignore pattern only matches
	// directories, so they don't count.
	dirty, statusErr := gitBackend.StatusLines(tree)
	if statusErr != nil {
		return spec.GeneralError, wrapGeneral(statusErr)
	}
	dirty = dropLinkedFromStatus(dirty, lists.links)
	// git ignores the discards, so it can't tell they hold work: a project
	// can veto with project.closeCheck, run in the worktree, and non-zero
	// refuses
	vetoed := false
	check := gitBackend.ConfigGet(mainDir, "project.closeCheck")
	if check != "" {
		cmd := exec.Command("sh", "-c", check)
		cmd.Dir = tree
		cmd.Env = append(os.Environ(), "PROJECT_MAIN="+mainDir, "PROJECT_TREE="+tree)
		if cmd.Run() != nil {
			vetoed = true
		}
	}
	if action == "close" {
		if len(dirty) > 0 {
			return spec.GeneralError, &toolError{
				code: spec.GeneralError,
				err: &spec.Error{
					Code:    "UNCOMMITTED_WORK",
					Message: fmt.Sprintf("%s has uncommitted work; commit or discard it first", tree),
				},
			}
		}
		changed := differingCopies(mainDir, tree, lists.copies)
		if len(changed) > 0 {
			return spec.GeneralError, &toolError{
				code: spec.GeneralError,
				err: &spec.Error{
					Code:    "INCLUDED_FILES_CHANGED",
					Message: fmt.Sprintf("these included files differ from main; copy or delete them first: %s", strings.Join(changed, ", ")),
				},
			}
		}
		if vetoed {
			return spec.PermissionDenied, &toolError{
				code: spec.PermissionDenied,
				err: &spec.Error{
					Code:    "CLOSE_VETOED",
					Message: fmt.Sprintf("project.closeCheck refused to close %s", tree),
				},
			}
		}
	}
	// show what is lost, then ask for a code that no script can know in
	// advance: the human gate of the coordination vocabulary
	if action == "discard" {
		changed := differingCopies(mainDir, tree, lists.copies)
		if len(dirty) > 0 || len(changed) > 0 || vetoed {
			if !confirmDiscard(stderr, tree, dirty, changed, vetoed) {
				return spec.GeneralError, &toolError{
					code: spec.GeneralError,
					err:  &spec.Error{Code: "DISCARD_CANCELLED", Message: "wrong code; nothing discarded"},
				}
			}
		}
	}

	// ---- the removals. Each step is one plain action.

	// the copies and the discards go; the links only when they are links
	for _, file := range append(append([]string{}, lists.copies...), lists.discards...) {
		_ = os.RemoveAll(filepath.Join(tree, file))
	}
	for _, file := range lists.links {
		path := filepath.Join(tree, file)
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
			_ = os.Remove(path)
		}
	}
	// a build can leave read-only files (ignored ones), which git can't
	// delete
	_ = exec.Command("chmod", "-R", "u+w", tree).Run()
	// git worktree remove; --force only after discard confirmed above
	if err := gitBackend.RemoveWorktree(mainDir, tree, action == "discard"); err != nil {
		return spec.GeneralError, wrapGeneral(err)
	}
	// background agents that were started in the worktree have nothing left
	// to work in
	claudeStopTree(tree)
	// the caller's shell cannot stay inside a removed directory: the fish
	// stub changes to main through the cd file
	if inDir(tree, cwd()) {
		writeCDFile(mainDir)
	}
	// keep the branch unless the merge slot accepts it: merged into the
	// default branch, locally or upstream, or into the projectBase it
	// started from
	if branch != "" {
		slot := coord.MergeSlot{
			DefaultBranch: gitBackend.DefaultBranch(mainDir),
			ProjectBase:   gitBackend.ConfigGet(mainDir, "branch."+branch+".projectBase"),
		}
		if mergedThrough(gitBackend, mainDir, branch, slot) {
			if err := gitBackend.DeleteBranch(mainDir, branch, true); err != nil {
				return spec.GeneralError, wrapGeneral(err)
			}
			_ = gitBackend.ConfigUnset(mainDir, "branch."+branch+".projectBase")
		} else {
			parent := ""
			if slot.ProjectBase != "" {
				parent = " or " + slot.ProjectBase
			}
			printfDiag(stderr, "kept branch %s, which isn't merged into %s%s", branch, slot.DefaultBranch, parent)
		}
	}
	// last: run from inside the worktree's own window, this ends the shell
	// running it
	for _, window := range tmuxWindowsWithExactDir(tree) {
		_, _ = tmux("kill-window", "-t", window)
	}
	return spec.Success, nil
}

// resolveCloseTarget finds the worktree that a close argument names.
func resolveCloseTarget(target string) (string, *toolError) {
	if nameLike.MatchString(target) {
		// a bare name: the project of the current directory
		if dir := currentProjectDir(); dir != "" {
			return filepath.Join(dir, target), nil
		}
	}
	resolved, err := resolvePath(target)
	if err != nil {
		return "", wrapGeneral(err)
	}
	top := gitTopLevel(resolved)
	if top == "" {
		return "", errNotFound("%s is not a worktree", resolved)
	}
	return top, nil
}

// hasIncludeFiles reports whether either include list exists.
func hasIncludeFiles(mainDir, dir string) bool {
	for _, path := range []string{
		filepath.Join(mainDir, ".worktreeinclude"),
		filepath.Join(dir, ".projectinclude"),
	} {
		if _, err := os.Stat(path); err == nil {
			return true
		}
	}
	return false
}

// dropLinkedFromStatus removes the untracked lines of the symlinked files:
// they show up as untracked when the ignore pattern only matches
// directories.
func dropLinkedFromStatus(lines, links []string) []string {
	patterns := make([]*regexp.Regexp, 0, len(links))
	for _, link := range links {
		quoted := regexp.QuoteMeta(link)
		patterns = append(patterns, regexp.MustCompile(`^\?\? `+quoted+`/?$`))
	}
	kept := make([]string, 0, len(lines))
	for _, line := range lines {
		drop := false
		for _, pattern := range patterns {
			if pattern.MatchString(line) {
				drop = true
				break
			}
		}
		if !drop {
			kept = append(kept, line)
		}
	}
	return kept
}

// differingCopies lists the included copies of the worktree that no longer
// match main.
func differingCopies(mainDir, tree string, copies []string) []string {
	var changed []string
	for _, file := range copies {
		workPath := filepath.Join(tree, file)
		if _, err := os.Stat(workPath); err == nil && !filesEqual(workPath, filepath.Join(mainDir, file)) {
			changed = append(changed, file)
		}
	}
	return changed
}

// confirmDiscard lists the work that would go and asks for a one-time code
// typed at that terminal. A wrong code discards nothing.
func confirmDiscard(stderr io.Writer, tree string, dirty, changed []string, vetoed bool) bool {
	fmt.Fprintf(stderr, "project: discard deletes this work in %s for good:\n", tree)
	for _, line := range dirty {
		fmt.Fprintf(stderr, "  %s\n", line)
	}
	for _, file := range changed {
		fmt.Fprintf(stderr, "  %s (differs from main)\n", file)
	}
	if vetoed {
		fmt.Fprintln(stderr, "  ignored files that project.closeCheck protects")
	}
	code := randomCode()
	fmt.Fprintf(stderr, "project: type %s to discard it: ", code)
	tty, err := os.Open("/dev/tty")
	if err != nil {
		return false
	}
	defer tty.Close()
	answer := readLine(tty)
	return answer == code
}

// randomCode is a six-digit code that no script can know in advance.
func randomCode() string {
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "100000"
	}
	return fmt.Sprintf("%06d", n.Int64()+100000)
}

// readLine reads one line from a reader, without the newline.
func readLine(r io.Reader) string {
	buf := make([]byte, 0, 64)
	one := make([]byte, 1)
	for {
		n, err := r.Read(one)
		if n > 0 {
			if one[0] == '\n' {
				return strings.TrimRight(string(buf), "\r")
			}
			buf = append(buf, one[0])
		}
		if err != nil {
			return strings.TrimRight(string(buf), "\r")
		}
	}
}

// tmuxWindowsWithExactDir lists the windows whose @ide_dir is exactly dir.
func tmuxWindowsWithExactDir(dir string) []string {
	out, err := tmux("list-windows", "-a", "-F", "#{window_id} #{@ide_dir}")
	if err != nil {
		return nil
	}
	var windows []string
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && parts[1] == dir {
			windows = append(windows, parts[0])
		}
	}
	return windows
}

// mergedThrough is the merge slot decision: the branch counts as integrated
// when it is an ancestor of any ref the slot names.
func mergedThrough(git backend.Backend, mainDir, branch string, slot coord.MergeSlot) bool {
	for _, ref := range slot.Refs() {
		if git.RefExists(mainDir, ref) && git.AncestorOf(mainDir, branch, ref) {
			return true
		}
	}
	return false
}
