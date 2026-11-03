// Command project manages a project directory: <dir>/main is the repo's
// default branch, and <dir>/<branch> is one git worktree of it per branch.
//
// It is the Go rewrite of the fish function of the same name (issue #74,
// phase 3). The fish function shrank to a cd stub and a completion file that
// call this binary; the ide window builder stays a fish function that this
// binary invokes. The machine-facing subcommands (add, spawn --headless,
// list) print one JSON envelope on stdout and exit with codes from the
// vendored exit-code table; the interactive subcommands stay plain text.
package main

import (
	"fmt"
	"io"
	"os"

	"genixis/project/internal/spec"
)

// version is the tool version of the envelope meta.
const version = "0.1.0"

const usage = "usage: project open|add|spawn|list [dir] [branch] [--from base] [--as name] [--plan name] [--identity name] [--headless] | project close|discard [worktree] | project clean [dir] [--dry-run] [--gone] | project convert <repo>"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run executes one invocation and returns the process exit code. The tests
// call it in process.
func run(argv []string, stdout, stderr io.Writer) int {
	if len(argv) == 0 {
		fmt.Fprintln(stderr, usage)
		return int(spec.ArgError)
	}
	var code spec.ExitCode
	switch argv[0] {
	case "open", "add", "spawn":
		code = cmdSession(argv[0], argv[1:], stdout, stderr)
	case "list":
		code = cmdList(argv[1:], stdout, stderr)
	case "__complete":
		code = cmdComplete(argv[1:], stdout, stderr)
	case "--version":
		fmt.Fprintln(stdout, version)
		return int(spec.Success)
	default:
		fmt.Fprintln(stderr, usage)
		return int(spec.ArgError)
	}
	return int(code)
}

// fail prints the diagnostic of a failed interactive path and names its
// exit code.
func fail(stderr io.Writer, code spec.ExitCode, format string, args ...any) spec.ExitCode {
	fmt.Fprintf(stderr, "project: %s\n", fmt.Sprintf(format, args...))
	return code
}
