package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// includeLists holds the untracked files of main/ that a new worktree needs.
//
// Two files list them, in gitignore syntax; both are optional:
//
//	main/.worktreeinclude  committed, shared by every clone; always read
//	                      from main/, never from the branch of a worktree
//	<dir>/.projectinclude  outside every repo, the entries of one machine
//
// A leading @ makes a symlink instead of a copy, and a leading ~ makes a
// copy that close discards without a comparison (files a build regenerates
// for each branch).
type includeLists struct {
	// copies are plain copies (no prefix).
	copies []string
	// discards are ~ copies, removed on close without comparison.
	discards []string
	// links are @ entries, symlinked into main/.
	links []string
}

// any reports whether the lists name anything.
func (l includeLists) any() bool {
	return len(l.copies) > 0 || len(l.discards) > 0 || len(l.links) > 0
}

// readIncludeLists merges the two list files of a project and lists the
// files of each class. The listing runs through git's exclude machinery
// (`git ls-files --others --ignored --directory --exclude-from=<class
// lines>`), once per class with the prefix stripped, so the patterns keep
// the exact gitignore meaning they had in the fish implementation; the tool
// never reimplements gitignore.
func readIncludeLists(mainDir, projectDir string) includeLists {
	var lists includeLists
	var copies, discards, links []string
	for _, path := range []string{
		filepath.Join(mainDir, ".worktreeinclude"),
		filepath.Join(projectDir, ".projectinclude"),
	} {
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(raw), "\n") {
			line = strings.TrimRight(line, "\r")
			if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimLeft(line, " \t"), "#") {
				continue
			}
			switch {
			case strings.HasPrefix(line, "@"):
				links = append(links, strings.TrimPrefix(line, "@"))
			case strings.HasPrefix(line, "~"):
				discards = append(discards, strings.TrimPrefix(line, "~"))
			default:
				copies = append(copies, line)
			}
		}
	}
	lists.copies = lsIncluded(mainDir, copies)
	lists.discards = lsIncluded(mainDir, discards)
	lists.links = lsIncluded(mainDir, links)
	return lists
}

// lsIncluded lists the untracked files of main/ that the patterns match.
// --directory lists a matched directory and its contents once; the trailing
// slash of such an entry is dropped.
func lsIncluded(mainDir string, patterns []string) []string {
	if len(patterns) == 0 {
		return nil
	}
	excludeFile, err := os.CreateTemp("", "project-includes-")
	if err != nil {
		return nil
	}
	defer os.Remove(excludeFile.Name())
	for _, pattern := range patterns {
		if _, err := excludeFile.WriteString(pattern + "\n"); err != nil {
			return nil
		}
	}
	if err := excludeFile.Close(); err != nil {
		return nil
	}
	cmd := exec.Command("git", "-C", mainDir, "ls-files", "--others", "--ignored", "--directory", "--exclude-from="+excludeFile.Name())
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	var files []string
	for _, entry := range strings.Split(string(out), "\n") {
		entry = strings.TrimRight(entry, "\r")
		if entry == "" {
			continue
		}
		files = append(files, strings.TrimSuffix(entry, "/"))
	}
	return files
}

// materialize copies and links the included files into a new worktree.
// Copy is copy-on-write where the file system supports it. Files that exist
// already are left alone, and ls-files can list a directory and then its
// contents, so an earlier entry wins.
func materialize(mainDir, tree string, lists includeLists) {
	for _, lists := range [][]string{lists.copies, lists.discards} {
		for _, file := range lists {
			copyIncluded(mainDir, tree, file)
		}
	}
	for _, file := range lists.links {
		if _, err := os.Lstat(filepath.Join(tree, file)); err == nil {
			continue
		}
		mkdirTree(tree, file)
		_ = os.Symlink(filepath.Join(mainDir, file), filepath.Join(tree, file))
	}
}

func copyIncluded(mainDir, tree, file string) {
	if _, err := os.Lstat(filepath.Join(tree, file)); err == nil {
		return
	}
	mkdirTree(tree, file)
	source := filepath.Join(mainDir, file)
	target := filepath.Join(tree, file)
	if runtime.GOOS == "darwin" {
		// -c asks APFS for a clone; the fallback is a plain copy
		if err := exec.Command("cp", "-Rc", source, target).Run(); err != nil {
			_ = exec.Command("cp", "-R", source, target).Run()
		}
		return
	}
	_ = exec.Command("cp", "-R", "--reflink=auto", source, target).Run()
}

func mkdirTree(tree, file string) {
	_ = os.MkdirAll(filepath.Dir(filepath.Join(tree, file)), 0o755)
}
