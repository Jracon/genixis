package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"genixis/project/internal/ide"
	"genixis/project/internal/spec"
)

// This file is the port of the fish function `ide` of fish.nix (issue #74,
// phase 3, the ide leg): the window builder of a checkout and its pop,
// close, and reload verbs, plus the claude pane start (the former
// __ide_claude) and wezterm-attach. The command line and the @ide_* options
// are unchanged; the pure parts they rest on are frozen in internal/ide.

// goosDarwin gates the launchd-owned tmux server of Darwin.
var goosDarwin = runtime.GOOS == "darwin"

// tmuxLaunchdLabel is the label of the launchd agent that runs the tmux
// server on Darwin; tmux.nix sets it and must stay in step.
const tmuxLaunchdLabel = "org.nix-community.home.tmux"

// cmdIde is the `project ide` subcommand. The fish function of the same name
// is a stub that only adds the cd of the caller's shell (the PROJECT_CD_FILE
// protocol); every other consumer, `project` included, lands here.
func cmdIde(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	verb := ""
	if len(argv) > 0 {
		verb = argv[0]
	}
	var err *toolError
	switch verb {
	case "pop":
		err = idePop()
	case "close", "reload":
		err = ideCloseReload(verb, stderr)
	default:
		err = ideBuild(argv)
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return err.code
	}
	return spec.Success
}

// ideBuild is the window builder. argv is the ide command line:
// [--detach|--session <session>] [dir] [title] [claude args...].
//
// A window is yazi on the left, nvim over a shell in the middle, and claude
// on the right. --detach puts the window in a named session without
// attaching and without switching a window: scripts and agents use it, and
// one project gets one session, which is one tab of the host window when a
// terminal shows it (see wezterm.go). Outside tmux the command attaches to
// the session it names (or the one named after the directory); inside tmux
// the window is a tab of the current session, built in place when that
// window is one lone pane.
func ideBuild(argv []string) *toolError {
	if err := tmuxServerCheck(); err != nil {
		return err
	}
	detach := false
	session := ""
	if len(argv) > 0 && (argv[0] == "--detach" || argv[0] == "--session") {
		if argv[0] == "--detach" {
			detach = true
		}
		if len(argv) > 1 {
			session = argv[1]
			argv = argv[2:]
		} else {
			argv = nil
		}
	}
	dirValue := "."
	if len(argv) > 0 {
		dirValue = argv[0]
	}
	dir, err := resolvePath(dirValue)
	if err != nil {
		return wrapGeneral(err)
	}
	name := ""
	if len(argv) > 1 {
		name = argv[1]
	}
	if name == "" {
		name = filepath.Base(dir)
	}
	if session == "" {
		session = name
	}
	session = sessionName(session)
	var claudeArgs []string
	if len(argv) > 2 {
		claudeArgs = argv[2:]
	}

	inTmux := os.Getenv("TMUX") != ""
	var editor string
	switch {
	case detach:
		// one window per checkout, whatever the session
		if w := ideWindowWithDir(dir, "-a"); w != "" {
			return errGeneral("ide: %s already has an ide window", dir)
		}
		if sessionExists(session) {
			editor, err = idePane("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "="+session+":", "-n", name, "-c", dir)
		} else {
			// size it like the window it will show in, if any; the
			// client-attached hook re-proportions the panes anyway
			var size []string
			if inTmux {
				size = []string{"-x", tmuxDisplay("", "#{window_width}"), "-y", tmuxDisplay("", "#{window_height}")}
			} else {
				// the session opens as a tab of the host window, and this
				// terminal is a fair guess for its size; at the 80x24
				// default every pane would scale up on attach
				size = []string{"-x", terminalSize("cols"), "-y", terminalSize("lines")}
			}
			args := append([]string{"new-session", "-d", "-P", "-F", "#{pane_id}", "-s", session, "-c", dir, "-n", name}, size...)
			editor, err = idePane(args...)
		}
		if err != nil {
			return wrapGeneral(err)
		}
	case inTmux:
		if w := ideWindowWithDir(dir); w != "" {
			_, _ = tmux("select-window", "-t", w)
			return nil
		}
		if tmuxDisplay(os.Getenv("TMUX_PANE"), "#{window_panes}") == "1" {
			// this lone pane becomes the editor pane; the shell of the
			// caller follows into the directory through the cd protocol
			editor = os.Getenv("TMUX_PANE")
			writeCDFile(dir)
			_, _ = tmux("rename-window", "-t", editor, name)
		} else {
			editor, err = idePane("new-window", "-P", "-F", "#{pane_id}", "-n", name, "-c", dir)
			if err != nil {
				return wrapGeneral(err)
			}
		}
	case sessionExists(session):
		// the session may hold other checkouts of a project: attach on this
		// directory's window, or add one
		if w := ideWindowWithDir(dir, "-t", "="+session); w != "" {
			_, _ = tmux("select-window", "-t", w)
			return tmuxAttachError("=" + session)
		}
		editor, err = idePane("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "="+session+":", "-n", name, "-c", dir)
		if err != nil {
			return wrapGeneral(err)
		}
		_, _ = tmux("select-window", "-t", editor)
	default:
		// size the detached session like this terminal; at the 80x24
		// default, attaching would scale 30 columns up proportionally
		editor, err = idePane("new-session", "-d", "-P", "-F", "#{pane_id}", "-s", session, "-c", dir, "-n", name,
			"-x", terminalSize("cols"), "-y", terminalSize("lines"))
		if err != nil {
			return wrapGeneral(err)
		}
	}

	// per pane, not per session, so several ide windows can share a session
	sock := ide.SocketPath(tmuxDisplay(editor, "#{pid}-#{pane_id}"))
	_ = os.Remove(sock)
	env := []string{"-e", "IDE_EDITOR_PANE=" + editor, "-e", "IDE_NVIM_SOCK=" + sock}
	files, err := idePane(append(append([]string{"split-window"}, env...), "-P", "-F", "#{pane_id}", "-h", "-b", "-l", "30", "-t", editor, "-c", dir)...)
	if err != nil {
		return wrapGeneral(err)
	}
	agent, err := idePane(append(append([]string{"split-window"}, env...), "-P", "-F", "#{pane_id}", "-h", "-l", "30%", "-t", editor, "-c", dir)...)
	if err != nil {
		return wrapGeneral(err)
	}
	shell, err := idePane(append(append([]string{"split-window"}, env...), "-P", "-F", "#{pane_id}", "-v", "-l", "20%", "-t", editor, "-c", dir)...)
	if err != nil {
		return wrapGeneral(err)
	}
	// the plan of the agent session, which the settings of `project` name in
	// PROJECT_PLAN: recorded so that a later `project open` can tell whether
	// the pane already runs the requested plan (empty: none)
	plan := idePlanFromArgs(claudeArgs)
	for _, args := range ide.OptionWrites(editor, agent, dir, files, plan, shell, sock) {
		if _, err := tmux(args...); err != nil {
			return wrapGeneral(err)
		}
	}
	_, _ = tmux("send-keys", "-t", files, "y", "Enter")
	if err := claudePaneStart(agent, sock, claudeArgs); err != nil {
		return err
	}
	_, _ = tmux("select-pane", "-t", editor)

	if detach {
		_, _ = tmux("send-keys", "-t", editor, "nvim --listen "+sock, "Enter")
		ideLayout(editor)
		// a session that a terminal already shows lists the new window in
		// its status bar; otherwise it gets a tab in the host window (no GUI
		// over ssh: the session waits for `tmux attach`)
		if attached := tmuxDisplay("="+session+":", "#{session_attached}"); attached != "" && attached != "0" {
			return nil
		}
		if commandExists("wezterm") && os.Getenv("SSH_CONNECTION") == "" {
			return weztermAttachError("="+session, session)
		}
		fmt.Fprintf(os.Stderr, "ide: no WezTerm here; attach with `tmux attach -t =%s`\n", session)
		return nil
	}
	if !inTmux {
		_, _ = tmux("send-keys", "-t", editor, "nvim --listen "+sock, "Enter")
		return tmuxAttachError("=" + session)
	}
	ideLayout(editor)
	if editor == os.Getenv("TMUX_PANE") {
		// this pane is the editor: nvim takes it over until it quits
		if err := runForeground("nvim", "--listen", sock); err != nil {
			return wrapGeneral(err)
		}
		return nil
	}
	_, _ = tmux("send-keys", "-t", editor, "nvim --listen "+sock, "Enter")
	return nil
}

// ideCloseReload implements `ide close` and `ide reload`, which run from a
// pane of the ide window they act on. close refuses while nvim holds unsaved
// buffers; reload picks up a rebuild: the tmux config, nvim with its tabs
// and windows, and yazi. The claude pane and the shells keep running.
func ideCloseReload(action string, stderr io.Writer) *toolError {
	editor := tmuxWindowOption(os.Getenv("TMUX_PANE"), "@ide_editor")
	if editor == "" {
		return errGeneral("ide: %s runs inside an ide window", action)
	}
	sock := tmuxWindowOption(editor, "@ide_sock")
	if isSocket(sock) {
		if count, err := strconv.Atoi(nvimExpr(sock, "luaeval('#vim.fn.getbufinfo({bufmodified = 1})')")); err == nil && count > 0 {
			_, _ = tmux("select-pane", "-t", editor)
			return errGeneral("ide: nvim has %d unsaved buffer(s); write or discard them first", count)
		}
	}
	// a viewer standing in for nvim (ide-view) has nvim's pane in a
	// throwaway session: swap it back
	if viewer := tmuxPaneOption(editor, "@ide_viewer"); viewer != "" {
		if _, err := tmux("swap-pane", "-s", viewer, "-t", editor); err == nil {
			_, _ = tmux("kill-pane", "-t", viewer)
		}
	}
	if action == "close" {
		// last: this ends the shell running it, and the session if it was
		// the only window
		if _, err := tmux("kill-window", "-t", editor); err != nil {
			return wrapGeneral(err)
		}
		return nil
	}

	// tmux: new options and bindings apply at once; removed ones linger
	// until the server restarts
	if configFiles := tmuxDisplay("", "#{config_files}"); configFiles != "" {
		_, _ = tmux(append([]string{"source-file", "-q"}, strings.Split(configFiles, ",")...)...)
	}
	// nvim: save its tabs and windows, quit, and start the new one on the
	// same socket. The session leaves out options, which would bring back
	// the old runtimepath (and so the old config).
	sessionFile := ide.SessionFile(sock)
	_ = os.Remove(sessionFile)
	if isSocket(sock) {
		_ = nvimExpr(sock, fmt.Sprintf("execute('set sessionoptions-=blank sessionoptions-=options | mksession! %s')", sessionFile))
		_ = nvimSend(sock, `<C-\><C-N>:qa<CR>`)
		for i := 0; i < 50; i++ {
			if !isSocket(sock) {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
		if isSocket(sock) {
			_, _ = tmux("select-pane", "-t", editor)
			return errGeneral("ide: nvim didn't quit; reload it by hand")
		}
	}
	nvimCmd := []string{"nvim", "--listen", sock}
	if _, statErr := os.Stat(sessionFile); statErr == nil {
		nvimCmd = append(nvimCmd, "-S", sessionFile, "-c", "call delete(v:this_session)")
	}
	escaped := make([]string, len(nvimCmd))
	for i, part := range nvimCmd {
		escaped[i] = ide.FishEscape(part)
	}
	if _, err := tmux("send-keys", "-t", editor, strings.Join(escaped, " "), "Enter"); err != nil {
		return wrapGeneral(err)
	}
	// yazi: a fresh shell in its pane, in the directory it was showing
	files := tmuxWindowOption(editor, "@ide_files")
	if _, err := tmux("respawn-pane", "-k", "-t", files,
		"-c", tmuxDisplay(files, "#{pane_current_path}"),
		"-e", "IDE_EDITOR_PANE="+editor, "-e", "IDE_NVIM_SOCK="+sock); err != nil {
		return wrapGeneral(err)
	}
	_, _ = tmux("send-keys", "-t", files, "y", "Enter")
	ideLayout(editor)
	fmt.Fprintln(stderr, "ide: reloaded tmux, nvim and yazi; restart claude with /exit and `claude --continue`, and shells with `exec fish`")
	return nil
}

// idePop implements `ide pop`: the current tmux window moves into a WezTerm
// window of its own.
func idePop() *toolError {
	pane := os.Getenv("TMUX_PANE")
	if pane == "" {
		return errGeneral("ide: pop runs inside tmux")
	}
	if !commandExists("wezterm") {
		return errGeneral("ide: wezterm isn't installed")
	}
	// moving a session's only window would destroy the session, and this
	// client with it
	if tmuxDisplay(pane, "#{session_windows}") == "1" {
		return errGeneral("ide: this is the only window of its session; open a second WezTerm window with `tmux new -s <name>`")
	}
	window := tmuxDisplay(pane, "#{window_id}")
	name := strings.NewReplacer(".", "-", ":", "-").Replace(tmuxDisplay(pane, "#{window_name}"))
	session := "pop-" + name + "-" + strings.TrimPrefix(window, "@")
	// the placeholder keeps the new session's first window away from fish,
	// which would attach tmux inside it
	placeholder, err := tmux("new-session", "-dP", "-F", "#{window_id}", "-s", session, "sleep 60")
	if err != nil {
		return wrapGeneral(err)
	}
	_, _ = tmux("move-window", "-s", window, "-t", session+":")
	_, _ = tmux("kill-window", "-t", placeholder)
	if err := weztermOwnWindow(session); err != nil {
		return wrapGeneral(err)
	}
	return nil
}

// claudePaneStart starts claude in the agent pane of an ide window: the
// builder starts a fresh pane with it, and the replan of `project open`
// restarts the pane under other settings with it. Typed-ahead input waits in
// the tty's line buffer until fish starts, and macOS drops what passes about
// 1 KiB (the Enter with it), so a long claude command goes through a script
// that removes itself; the leading space of the source line keeps it out of
// the fish history. The script bytes are frozen in internal/ide.
func claudePaneStart(pane, sock string, args []string) *toolError {
	start := ide.ClaudeScript(sock)
	if err := os.WriteFile(start, ide.ClaudeStartScript(start, args), 0o644); err != nil {
		return wrapGeneral(err)
	}
	if _, err := tmux("send-keys", "-t", pane, ide.ClaudePaneSource(start), "Enter"); err != nil {
		return wrapGeneral(err)
	}
	return nil
}

// weztermAttachError opens the tab of a local session in the host window
// (see wezterm.go) and adapts its failure to the builder's error type. The
// caller has already checked that no other client shows the session.
func weztermAttachError(target, name string) *toolError {
	if _, err := weztermAttach(target, name, false); err != nil {
		return wrapGeneral(err)
	}
	return nil
}

// cmdWeztermAttach is the PATH form of wezterm-attach, a symlink beside the
// project binary: it opens the tab of one session in the window of this
// user on this host.
func cmdWeztermAttach(argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if len(argv) != 1 || argv[0] == "" {
		fmt.Fprintln(stderr, "usage: wezterm-attach <session>")
		return spec.ArgError
	}
	name := strings.TrimPrefix(argv[0], "=")
	if _, err := weztermAttach(argv[0], name, false); err != nil {
		fmt.Fprintf(stderr, "wezterm-attach: %v\n", err)
		return spec.GeneralError
	}
	return spec.Success
}

// ideLayout re-proportions the panes of an ide window to its window size,
// from the @ide_* options: yazi 15% of the width (clamped to 24-40 columns),
// claude 30% (at least 40), the shell 20% of the height (at least 6). The
// client-attached and client-resized hooks run it too, through the PATH
// command of the same name.
func ideLayout(editor string) {
	files := tmuxWindowOption(editor, "@ide_files")
	if files == "" {
		return
	}
	agent := tmuxWindowOption(editor, "@ide_agent")
	shell := tmuxWindowOption(editor, "@ide_shell")
	fields := strings.Fields(tmuxDisplay(editor, "#{window_width} #{window_height}"))
	if len(fields) != 2 {
		return
	}
	width, errWidth := strconv.Atoi(fields[0])
	height, errHeight := strconv.Atoi(fields[1])
	if errWidth != nil || errHeight != nil {
		return
	}
	filesWidth, agentWidth, shellHeight := ide.LayoutSizes(width, height)
	_, _ = tmux("resize-pane", "-t", files, "-x", strconv.Itoa(filesWidth))
	_, _ = tmux("resize-pane", "-t", agent, "-x", strconv.Itoa(agentWidth))
	_, _ = tmux("resize-pane", "-t", shell, "-y", strconv.Itoa(shellHeight))
}

// idePlanFromArgs reads the plan name out of the --settings value of the
// claude arguments, up to the -- that ends the options.
func idePlanFromArgs(args []string) string {
	take := false
	for _, arg := range args {
		if arg == "--" {
			break
		}
		if take {
			return ide.ExtractPlan(arg)
		}
		if arg == "--settings" {
			take = true
		}
	}
	return ""
}

// tmuxServerCheck is the Darwin gate of the builder: launchd owns the tmux
// server there (see "tmux server on Darwin" in AGENTS.md), so a client must
// not start one. -N makes a client fail instead of starting a server.
func tmuxServerCheck() *toolError {
	if !goosDarwin {
		return nil
	}
	cmd := exec.Command("tmux", "-N", "start-server")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		return errGeneral("tmux: no server; launchd starts it. Run `launchctl kickstart gui/%d/%s`, or read ~/Library/Logs/tmux-server.log",
			os.Getuid(), tmuxLaunchdLabel)
	}
	return nil
}

// idePane runs a tmux command that prints a pane id (-P -F '#{pane_id}') and
// returns it. On Darwin a new-session goes through -N so that it cannot
// start a server of its own.
func idePane(args ...string) (string, error) {
	if args[0] == "new-session" && goosDarwin {
		full := append([]string{"-N"}, args...)
		cmd := exec.Command("tmux", full...)
		var out bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = io.Discard
		err := cmd.Run()
		return strings.TrimSpace(out.String()), err
	}
	return tmux(args...)
}

// ideWindowWithDir lists the window whose @ide_dir is exactly dir, from the
// windows that extra names: all sessions (-a), the current session (none),
// or one target.
func ideWindowWithDir(dir string, extra ...string) string {
	args := append([]string{"list-windows", "-F", "#{window_id} #{@ide_dir}"}, extra...)
	out, err := tmux(args...)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && parts[1] == dir {
			return parts[0]
		}
	}
	return ""
}

// sessionExists reports whether a session of exactly this name exists.
func sessionExists(session string) bool {
	_, err := tmux("has-session", "-t", "="+session)
	return err == nil
}

// tmuxAttachError runs tmux attach in the foreground of this terminal.
func tmuxAttachError(target string) *toolError {
	if err := runForeground("tmux", "attach", "-t", target); err != nil {
		return wrapGeneral(err)
	}
	return nil
}

// runForeground runs a command in the foreground of the caller's terminal,
// until it quits.
func runForeground(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// terminalSize is `tput cols` or `tput lines`, 80 by 24 when it cannot read
// a terminal.
func terminalSize(what string) string {
	out, err := runCmd("", nil, "tput", what)
	if err != nil || out == "" {
		if what == "lines" {
			return "24"
		}
		return "80"
	}
	return out
}

// nvimExpr asks the nvim of a socket for one expression and returns its
// stdout, empty on failure.
func nvimExpr(sock, expr string) string {
	out, _ := runCmd("", nil, "nvim", "--headless", "--server", sock, "--remote-expr", expr)
	return out
}

// nvimSend types keys into the nvim of a socket.
func nvimSend(sock, keys string) error {
	cmd := exec.Command("nvim", "--headless", "--server", sock, "--remote-send", keys)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run()
}

// tmuxPaneOption reads a pane option, empty when unset.
func tmuxPaneOption(target, option string) string {
	out, _ := tmux("show-option", "-pqv", "-t", target, option)
	return out
}

// isSocket reports whether a path is a unix socket, the fish `test -S`.
func isSocket(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.Mode()&os.ModeSocket != 0
}
