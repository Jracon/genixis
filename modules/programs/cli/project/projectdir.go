package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"genixis/project/internal/spec"
)

// toolError is a failure with its exit code already decided, so a command
// body returns one value and the envelope and the plain-text paths agree.
type toolError struct {
	code spec.ExitCode
	err  *spec.Error
}

func (e *toolError) Error() string { return e.err.Message }

func errArg(format string, args ...any) *toolError {
	return &toolError{code: spec.ArgError, err: &spec.Error{Code: "ARG_ERROR", Message: fmt.Sprintf(format, args...)}}
}

func errNotFound(format string, args ...any) *toolError {
	return &toolError{code: spec.NotFound, err: &spec.Error{Code: "NOT_FOUND", Message: fmt.Sprintf(format, args...)}}
}

func errPermission(format string, args ...any) *toolError {
	return &toolError{code: spec.PermissionDenied, err: &spec.Error{Code: "PERMISSION_DENIED", Message: fmt.Sprintf(format, args...)}}
}

func errGeneral(format string, args ...any) *toolError {
	return &toolError{code: spec.GeneralError, err: &spec.Error{Code: "GENERAL_ERROR", Message: fmt.Sprintf(format, args...)}}
}

func errUnavailable(format string, args ...any) *toolError {
	return &toolError{code: spec.Unavailable, err: &spec.Error{Code: "UNAVAILABLE", Message: fmt.Sprintf(format, args...)}}
}

func wrapGeneral(err error) *toolError {
	return &toolError{code: spec.GeneralError, err: &spec.Error{Code: "GENERAL_ERROR", Message: err.Error()}}
}

// nameLike reports whether an argument is a bare name: no /, no ~, and not
// . or ... A bare name is a project under ~/projects.
var nameLike = regexp.MustCompile(`^[^/~]+$`)

// dirArg resolves the dir argument of a subcommand the way the fish
// implementation did: empty means the current directory, a bare name means
// ~/projects/<name>, anything else is a path. The result is absolute.
func dirArg(arg string) (string, error) {
	if arg == "" {
		arg = "."
	} else if nameLike.MatchString(arg) {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		arg = filepath.Join(home, "projects", arg)
	}
	return resolvePath(arg)
}

// resolvePath is fish `path resolve`: absolute, symlinks followed where
// they exist, and clean. A path that does not exist resolves through its
// deepest existing ancestor.
func resolvePath(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved, nil
	}
	parent, err := resolvePath(filepath.Dir(abs))
	if err != nil {
		return "", err
	}
	return filepath.Join(parent, filepath.Base(abs)), nil
}

// isProjectDir reports whether dir holds a main/ checkout.
func isProjectDir(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "main", ".git"))
	return err == nil && info.IsDir()
}

// insideProject reports whether dir is a checkout (main or a worktree) of a
// project, and returns the project directory.
func insideProject(dir string) (string, bool) {
	if isProjectDir(dir) {
		return dir, true
	}
	top := gitTopLevel(dir)
	if top == "" {
		return "", false
	}
	parent := filepath.Dir(top)
	if isProjectDir(parent) {
		return parent, true
	}
	return "", false
}

// currentProjectDir is the project of the current directory, or empty.
func currentProjectDir() string {
	dir, _ := insideProject(cwd())
	return dir
}

func cwd() string {
	dir, err := os.Getwd()
	if err != nil {
		return "."
	}
	return dir
}

// sessionName sanitizes a project name into a tmux session name the same
// way `ide` does, so the local half of a delegated call can compute the
// name of the session on the remote host.
var sessionNameRe = regexp.MustCompile(`[.:\s]+`)

func sessionName(name string) string {
	return sessionNameRe.ReplaceAllString(name, "_")
}

// printfDiag prints a diagnostic line the way the fish implementation did.
func printfDiag(stderr io.Writer, format string, args ...any) {
	fmt.Fprintf(stderr, "project: %s\n", fmt.Sprintf(format, args...))
}

// inDir reports whether path is dir or below it.
func inDir(dir, path string) bool {
	if dir == "" || path == "" {
		return false
	}
	rel, err := filepath.Rel(dir, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}
