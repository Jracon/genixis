// Command project manages a project directory: <dir>/main is the repo's
// default branch, and <dir>/<branch> is one git worktree of it per branch.
//
// It is the Go rewrite of the fish function of the same name (issue #74,
// phase 3). The fish function shrank to a cd stub and a completion file that
// call this binary, and the ide window builder family moved into this binary
// behind the same command names. The machine-facing subcommands (add, spawn
// --headless, list) print one JSON envelope on stdout and exit with codes
// from the vendored exit-code table; the interactive subcommands stay plain
// text.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"genixis/project/internal/spec"
)

// version is the tool version of the envelope meta.
const version = "0.1.0"

func main() {
	os.Exit(run(dispatchArgs(os.Args[0], os.Args[1:]), os.Stdout, os.Stderr))
}

// dispatchArgs routes a call through the name of the binary: the ide family
// also installs PATH symlinks to this binary (see lib/project-package.nix),
// and the name the binary was called as selects the subcommand. A call of
// the binary itself names its subcommand as its first argument already, so
// its arguments pass through unchanged. A caller that re-invokes the binary
// by path (selfPath) must give the resolved path of the binary: a symlink
// name here would put the subcommand in front of a call that carries it
// already, and cmdIdeView would reject the doubled word.
func dispatchArgs(argv0 string, args []string) []string {
	name := filepath.Base(argv0)
	switch name {
	case "ide-layout", "ide-open", "ide-edit", "ide-tab", "ide-view", "wezterm-attach":
		return append([]string{name}, args...)
	}
	return args
}

// run executes one invocation and returns the process exit code. The tests
// call it in process.
func run(argv []string, stdout, stderr io.Writer) int {
	if len(argv) == 0 {
		printMainHelp(stderr)
		return int(spec.ArgError)
	}
	var code spec.ExitCode
	switch argv[0] {
	case "help", "--help", "-h":
		// `project help <command>` names one screen; the rest print the
		// overview. The overview goes to stderr only on the error paths.
		if argv[0] == "help" && len(argv) > 1 {
			name := strings.Join(argv[1:], " ")
			if findDoc(name) == nil {
				fmt.Fprintf(stderr, "project: no help for %q\n", name)
				printMainHelp(stderr)
				return int(spec.ArgError)
			}
			printCommandDoc(stdout, name)
			return int(spec.Success)
		}
		printMainHelp(stdout)
		return int(spec.Success)
	case "open", "add", "spawn":
		code = cmdSession(argv[0], argv[1:], stdout, stderr)
	case "list":
		code = cmdList(argv[1:], stdout, stderr)
	case "review":
		code = cmdReview(argv[1:], stdout, stderr)
	case "board":
		code = cmdBoard(argv[1:], stdout, stderr)
	case "close", "discard":
		code = cmdClose(argv[0], argv[1:], stdout, stderr)
	case "clean":
		code = cmdClean(argv[1:], stdout, stderr)
	case "convert":
		code = cmdConvert(argv[1:], stdout, stderr)
	case "ide":
		code = cmdIde(argv[1:], stdout, stderr)
	case "ide-layout":
		code = cmdIdeLayout(argv[1:], stdout, stderr)
	case "ide-open":
		code = cmdIdeOpen(argv[1:], stdout, stderr)
	case "ide-edit":
		code = cmdIdeEdit(argv[1:], stdout, stderr)
	case "ide-tab":
		code = cmdIdeTab(argv[1:], stdout, stderr)
	case "ide-view":
		code = cmdIdeView(argv[1:], stdout, stderr)
	case "wezterm-attach":
		code = cmdWeztermAttach(argv[1:], stdout, stderr)
	case "__complete":
		code = cmdComplete(argv[1:], stdout, stderr)
	case "--version":
		fmt.Fprintln(stdout, version)
		return int(spec.Success)
	default:
		fmt.Fprintf(stderr, "project: unknown command %s\n", argv[0])
		printMainHelp(stderr)
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
