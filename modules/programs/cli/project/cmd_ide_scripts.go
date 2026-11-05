package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"genixis/project/internal/spec"
)

// This file is the port of the ide store scripts of tmux.nix and yazi.nix
// (issue #74, phase 3, the ide leg): ide-layout, ide-open, ide-edit,
// ide-tab, and ide-view, each behind the same PATH name, a symlink to this
// binary. The tmux hooks and the yazi openers call them exactly as before;
// the nvim lua side (genixis.ide) stays lua.

// cmdIdeLayout re-proportions the panes of an ide window. The tmux hooks
// client-attached and client-resized run it on every attach and resize.
func cmdIdeLayout(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 1 || argv[0] == "" {
		fmt.Fprintln(stderr, "usage: ide-layout <target>")
		return spec.ArgError
	}
	ideLayout(argv[0])
	return spec.Success
}

// cmdIdeOpen is the yazi edit opener: inside an ide session it opens each
// file in the nvim pane over the socket, one tab each, and focuses it;
// inside tmux elsewhere it falls back to a new window. It must not block: a
// blocking opener makes yazi suspend and re-detect the terminal, a stall of
// seconds on every open.
func cmdIdeOpen(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	sock := os.Getenv("IDE_NVIM_SOCK")
	editor := os.Getenv("IDE_EDITOR_PANE")
	if sock != "" {
		restoreEditor(editor)
		// after a :q the editor pane is back at its shell: start a fresh
		// nvim there instead of falling through to a new window, and give
		// its socket up to 2 seconds to appear
		if !isSocket(sock) && tmuxDisplay(editor, "#{pane_current_command}") == "fish" {
			_, _ = tmux("send-keys", "-t", editor, "nvim --listen "+sock, "Enter")
			for i := 0; i < 40; i++ {
				if isSocket(sock) {
					break
				}
				time.Sleep(50 * time.Millisecond)
			}
		}
	}
	if sock != "" && isSocket(sock) {
		_, _ = tmux("select-pane", "-t", editor)
		quoted := make([]string, 0, len(argv))
		for _, path := range argv {
			quoted = append(quoted, vimString(path))
		}
		expr := fmt.Sprintf("luaeval('require(\"genixis.ide\").open(_A)', [%s])", strings.Join(quoted, ","))
		_ = nvimExpr(sock, expr)
		return spec.Success
	}
	if os.Getenv("TMUX") != "" {
		if _, err := tmux(append([]string{"new-window", "nvim"}, argv...)...); err != nil {
			return spec.GeneralError
		}
		return spec.Success
	}
	fmt.Fprintln(stderr, "ide-open: not in an ide or tmux session; use yazi's Open with (O) for a blocking nvim")
	return spec.GeneralError
}

// cmdIdeEdit is the blocking $EDITOR for tools such as `agenix -e`: it
// opens each file in the nvim pane of the ide window, one tab each, and
// waits until the buffer closes. Outside an ide window it runs plain nvim
// in the foreground of this terminal.
func cmdIdeEdit(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	sock := os.Getenv("IDE_NVIM_SOCK")
	if sock == "" || !isSocket(sock) {
		if err := runForeground("nvim", argv...); err != nil {
			return spec.GeneralError
		}
		return spec.Success
	}
	editor := os.Getenv("IDE_EDITOR_PANE")
	restoreEditor(editor)
	_, _ = tmux("select-pane", "-t", editor)
	// the nvim of the pane writes this file when the buffer closes
	done := filepath.Join(os.TempDir(), fmt.Sprintf("ide-edit-%d", os.Getpid()))
	defer os.Remove(done)
	for _, path := range argv {
		_ = os.Remove(done)
		expr := fmt.Sprintf("luaeval('require(\"genixis.ide\").edit(_A[1], _A[2])', [%s, %s])",
			vimString(path), vimString(done))
		_ = nvimExpr(sock, expr)
		for !fileExists(done) && isSocket(sock) {
			time.Sleep(200 * time.Millisecond)
		}
	}
	return spec.Success
}

// cmdIdeTab is what the tmux Ctrl+digit and Ctrl+Tab bindings run in an ide
// window: it shows tab n (0 is the 10th), or the next or previous tab, of
// the window's nvim, and focuses the editor, whatever pane has focus.
func cmdIdeTab(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 2 || argv[1] == "" || (!isDigits(argv[1]) && argv[1] != "next" && argv[1] != "prev") {
		fmt.Fprintln(stderr, "usage: ide-tab <window> <n|next|prev>")
		return spec.ArgError
	}
	window := argv[0]
	editor := tmuxWindowOption(window, "@ide_editor")
	sock := tmuxWindowOption(window, "@ide_sock")
	restoreEditor(editor)
	_, _ = tmux("select-pane", "-t", editor)
	if !isSocket(sock) {
		return spec.Success
	}
	call := "tab(" + argv[1] + ")"
	switch argv[1] {
	case "next":
		call = "step(1)"
	case "prev":
		call = "step(-1)"
	}
	_ = nvimExpr(sock, "luaeval('require(\"genixis.ide\")."+call+"')")
	return spec.Success
}

// cmdIdeView shows a file read-only in the editor pane's place: the viewer
// runs in a throwaway tmux session and is swapped with the nvim pane, so it
// is a real pane (Option+arrows still move between panes) and nvim keeps
// running untouched out of sight. `q` swaps nvim back. Outside an ide
// session it falls back to a popup. The --run and --popup modes are what
// the viewer pane and the popup run.
func cmdIdeView(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) > 0 && argv[0] == "--run" {
		if len(argv) != 3 {
			fmt.Fprintln(stderr, "usage: ide-view --run <editor pane> <file>")
			return spec.ArgError
		}
		// this runs inside the viewer pane
		_ = viewFile(argv[2])
		_, _ = tmux("swap-pane", "-s", os.Getenv("TMUX_PANE"), "-t", argv[1])
		_, _ = tmux("set-option", "-pu", "-t", argv[1], "@ide_viewer")
		_, _ = tmux("select-pane", "-t", argv[1])
		return spec.Success
	}
	if len(argv) > 0 && argv[0] == "--popup" {
		if len(argv) != 2 {
			fmt.Fprintln(stderr, "usage: ide-view --popup <file>")
			return spec.ArgError
		}
		if err := viewFile(argv[1]); err != nil {
			return spec.GeneralError
		}
		return spec.Success
	}
	if len(argv) != 1 || argv[0] == "" {
		fmt.Fprintln(stderr, "usage: ide-view <file>")
		return spec.ArgError
	}
	file := argv[0]
	exe := selfPath()
	if editor := os.Getenv("IDE_EDITOR_PANE"); editor != "" {
		restoreEditor(editor)
		fields := strings.Fields(tmuxDisplay(editor, "#{pane_width} #{pane_height}"))
		if len(fields) != 2 {
			return spec.GeneralError
		}
		run := viewerCommand(exe, "--run", editor, file)
		viewer, err := tmux("new-session", "-d", "-P", "-F", "#{pane_id}",
			"-s", fmt.Sprintf("ide-view-%d", os.Getpid()), "-x", fields[0], "-y", fields[1], run)
		if err != nil {
			return spec.GeneralError
		}
		_, _ = tmux("set-option", "-p", "-t", editor, "@ide_viewer", viewer)
		_, _ = tmux("swap-pane", "-s", viewer, "-t", editor)
		_, _ = tmux("select-pane", "-t", viewer)
		return spec.Success
	}
	popup := viewerCommand(exe, "--popup", file)
	if _, err := tmux("display-popup", "-w", "90%", "-h", "90%", "-E", popup); err != nil {
		return spec.GeneralError
	}
	return spec.Success
}

// viewFile renders one file read-only: markdown through glow, everything
// else through bat, both with a pager.
func viewFile(path string) error {
	var cmd *exec.Cmd
	if strings.HasSuffix(path, ".md") || strings.HasSuffix(path, ".markdown") {
		cmd = exec.Command("glow", "--pager", path)
	} else {
		cmd = exec.Command("bat", "--paging=always", path)
	}
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// restoreEditor swaps nvim back into the editor pane when a read-only
// viewer (ide-view) stands in its place, and closes the viewer pane. A
// viewer option without a live viewer pane clears itself.
func restoreEditor(editor string) {
	if editor == "" {
		return
	}
	viewer := tmuxPaneOption(editor, "@ide_viewer")
	if viewer == "" {
		return
	}
	if _, err := tmux("display-message", "-p", "-t", viewer, "#{pane_id}"); err != nil {
		return
	}
	_, _ = tmux("swap-pane", "-s", viewer, "-t", editor)
	_, _ = tmux("set-option", "-pu", "-t", editor, "@ide_viewer")
	_, _ = tmux("kill-pane", "-t", viewer)
}

// vimString writes s as a Vim single-quoted string: an embedded quote
// doubles.
func vimString(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// shQuote writes s for a POSIX shell command line: always single-quoted,
// with an embedded quote closed and reopened the POSIX way.
func shQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// viewerCommand is the command line of the viewer pane (--run) and of the
// popup (--popup): the binary that selfPath resolved, one subcommand word,
// and the mode with its arguments. The line must carry exactly one
// ide-view word: dispatchArgs puts the word in front when the path itself
// is called as ide-view, and cmdIdeView rejects the doubled word.
func viewerCommand(exe, mode string, args ...string) string {
	words := append([]string{exe, "ide-view", mode}, args...)
	quoted := make([]string, len(words))
	for i, word := range words {
		quoted[i] = shQuote(word)
	}
	return strings.Join(quoted, " ")
}

// selfPath is the path of this binary, for the viewer pane and the popup
// that re-invoke it. The path resolves through the symlinks of the ide
// family, so it names the binary itself and the subcommand word of the
// command line routes the call. On a symlink call (the yazi opener runs
// ide-view from PATH), os.Executable can name the symlink: the subcommand
// word would then appear twice after dispatchArgs, and the pane would die
// on a usage error.
func selfPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "project"
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		return resolved
	}
	return exe
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
