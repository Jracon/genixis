package main

import (
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"genixis/project/internal/spec"
)

// cmdComplete serves the fish completion protocol: the completion file of
// the fish stub calls
//
//	command project __complete (commandline -cop) -- (commandline -ct)
//
// for positional arguments: the completed tokens of the command line, then
// --, then the token under the cursor (empty when a new word starts; a
// subprocess cannot read the command line itself, so the file passes it).
// The values of --from and --plan come from the context-free forms
// `command project __complete from` and `... plan`. The output is one fish
// completion line per candidate: value, tab, description. The protocol is
// frozen by the tests: a change in these lines is a change of the
// completion file, and both change in one commit.
func cmdComplete(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	// flag-value modes, called without the command line
	if len(argv) == 1 && argv[0] != "" && argv[0][0] != '-' {
		switch argv[0] {
		case "plan":
			// none is reserved: it starts no plan, and it is a value also
			// when no plan file exists
			writeLine(stdout, "none\tstart without a plan")
			for _, name := range planNames() {
				writeLine(stdout, "%s\tplan", name)
			}
			return spec.Success
		case "from":
			return completeBranches(stdout, "", true)
		}
	}
	if len(argv) == 0 {
		return spec.Success
	}
	// the tokens before -- are the command line, the one token after -- is
	// the token under the cursor
	sep := len(argv)
	for i, arg := range argv {
		if arg == "--" {
			sep = i
			break
		}
	}
	tokens := argv[:sep]
	current := ""
	if sep+1 < len(argv) {
		current = argv[sep+1]
	}
	if len(tokens) > 0 && tokens[0] == "project" {
		tokens = tokens[1:]
	}
	if len(tokens) == 0 {
		return spec.Success
	}
	action := tokens[0]
	// the positional arguments before the cursor: options, and the values
	// of those that take one, don't count
	var args []string
	value := false
	for _, token := range tokens[1:] {
		if value {
			value = false
			continue
		}
		switch token {
		case "--from", "--as", "--permission-mode", "--plan", "--identity":
			value = true
		default:
			if !strings.HasPrefix(token, "-") {
				args = append(args, token)
			}
		}
	}
	position := len(args) + 1
	// ./name, ~/name and a/b are paths, not names
	pathlike := regexp.MustCompile(`^[.~]|/`).MatchString(current)

	switch action {
	case "open", "add", "spawn":
		if position == 1 {
			// a user@host: prefix names a project on another machine,
			// which this machine cannot list
			if regexp.MustCompile(`^[^/~@]+@`).MatchString(current) {
				return spec.Success
			}
			if pathlike {
				completeDirectories(stdout, current)
				return spec.Success
			}
			completeProjects(stdout)
			return spec.Success
		}
		if position == 2 {
			return completeBranches(stdout, firstOr(args, ""), false)
		}
	case "close", "discard":
		if position != 1 {
			return spec.Success
		}
		dir := currentProjectDir()
		if pathlike || dir == "" {
			completeDirectories(stdout, current)
			return spec.Success
		}
		completeWorktrees(stdout, dir)
		return spec.Success
	case "clean", "convert":
		if position == 1 {
			completeDirectories(stdout, current)
		}
	}
	return spec.Success
}

func firstOr(list []string, fallback string) string {
	if len(list) > 0 {
		return list[0]
	}
	return fallback
}

// completeProjects lists the projects under ~/projects.
func completeProjects(stdout io.Writer) {
	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	entries, err := os.ReadDir(filepath.Join(home, "projects"))
	if err != nil {
		return
	}
	for _, entry := range entries {
		dir := filepath.Join(home, "projects", entry.Name())
		if isProjectDir(dir) {
			writeLine(stdout, "%s\tproject", entry.Name())
		} else if _, statErr := os.Stat(filepath.Join(dir, ".git")); statErr == nil {
			writeLine(stdout, "%s\tplain repo", entry.Name())
		}
	}
}

// completeBranches lists what the second positional argument of open, add,
// and spawn can be: worktrees first, then local branches, then remote ones.
// The branch of main/ is the bare `project open <dir>`, so only --from
// lists it.
func completeBranches(stdout io.Writer, dirArgValue string, fromMode bool) spec.ExitCode {
	dir, err := dirArg(dirArgValue)
	if err != nil {
		return spec.Success
	}
	if info, statErr := os.Stat(dir); statErr == nil && info.IsDir() &&
		isProjectDir(filepath.Dir(dir)) && !isProjectDir(dir) {
		dir = filepath.Dir(dir)
	}
	mainDir := filepath.Join(dir, "main")
	if !isProjectDir(dir) {
		return spec.Success
	}
	seen := map[string]bool{}
	if !fromMode {
		if current := gitBackend.CurrentBranch(mainDir); current != "" {
			seen[current] = true
		}
	}
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err == nil {
		for _, worktree := range worktrees {
			if worktree.Branch == "" || seen[worktree.Branch] {
				continue
			}
			seen[worktree.Branch] = true
			writeLine(stdout, "%s\tworktree %s", worktree.Branch, filepath.Base(worktree.Path))
		}
	}
	if branches, err := gitBackend.LocalBranches(mainDir); err == nil {
		for _, branch := range branches {
			if seen[branch] {
				continue
			}
			seen[branch] = true
			writeLine(stdout, "%s\tbranch", branch)
		}
	}
	if branches, err := gitBackend.RemoteBranches(mainDir); err == nil {
		for _, branch := range branches {
			if branch == "HEAD" || seen[branch] {
				continue
			}
			seen[branch] = true
			writeLine(stdout, "%s\tremote branch", branch)
		}
	}
	return spec.Success
}

// completeWorktrees lists the worktrees of a project by directory name, for
// close and discard.
func completeWorktrees(stdout io.Writer, dir string) {
	mainDir := filepath.Join(dir, "main")
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err != nil {
		return
	}
	for _, worktree := range worktrees {
		if worktree.Path == mainDir || filepath.Dir(worktree.Path) != dir {
			continue
		}
		writeLine(stdout, "%s\tbranch %s", filepath.Base(worktree.Path), worktree.Branch)
	}
}

// completeDirectories lists directories under a partial path, the part the
// fish helper __fish_complete_directories served.
func completeDirectories(stdout io.Writer, token string) {
	base := filepath.Dir(token)
	prefix := filepath.Base(token)
	if token == "" {
		base = "."
		prefix = ""
	}
	entries, err := os.ReadDir(base)
	if err != nil {
		return
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), prefix) {
			names = append(names, entry.Name())
		}
	}
	sort.Strings(names)
	for _, name := range names {
		writeLine(stdout, "%s/\tDirectory", filepath.Join(base, name))
	}
}
