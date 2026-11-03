package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

// ideOpen puts the ide window of one checkout on screen. It is the port of
// the ideIn block of the former fish function; the layout builder itself is
// the fish function `ide`, which this tool invokes.
//
// A project of its own gets its own tmux session and WezTerm window: from a
// tmux session of another project, `ide --detach` makes both, where plain
// `ide` would add a tab to the current session. A session that is named
// after the project, or that already holds an ide window of one of its
// checkouts, counts as the project's session. A window that is already open
// is selected instead, and a session that no terminal shows gets a new
// WezTerm window. Over ssh no WezTerm window can show the other session, so
// this client switches to it. Outside tmux, `ide --session` attaches to the
// project's session, with a window for this checkout. A call that came over
// ssh from `project` on another machine instead makes or finds the window
// without attaching, and prints the session name for the caller.
func ideOpen(stderr io.Writer, project, dir, planName string, path string, ideArgs []string) error {
	window := ideWindow(path)
	// a plan applies only where claude starts: when the open window of this
	// checkout runs another plan (or none), restart its claude pane under
	// the requested settings
	if window != "" {
		if current := tmuxWindowOption(window, "@ide_plan"); current != planName {
			if err := replan(stderr, window, planName, ideArgs); err != nil {
				return err
			}
		}
	}
	if os.Getenv("PROJECT_REMOTE_ARGV") != "" {
		if window == "" {
			if err := fishFunc("ide", prepend("--detach", project, path, ideArgs)...); err != nil {
				return err
			}
		}
		fmt.Println(sessionName(project))
		return nil
	}
	if os.Getenv("TMUX") == "" {
		return fishFunc("ide", prepend("--session", project, path, ideArgs)...)
	}
	if window != "" && tmuxDisplay(window, "#{session_id}") == tmuxDisplay("", "#{session_id}") {
		_, _ = tmux("select-window", "-t", window)
		return nil
	}
	if window == "" {
		current := tmuxDisplay("", "#S")
		if current == sessionName(project) || len(tmuxWindowsUnder(dir)) > 0 {
			return fishFunc("ide", append([]string{path}, ideArgs...)...)
		}
	} else {
		return switchToWindow(stderr, window)
	}
	// no window here, and this session is not the project's: give the
	// project its own detached session and window
	if err := fishFunc("ide", prepend("--detach", project, path, ideArgs)...); err != nil {
		return err
	}
	if os.Getenv("SSH_CONNECTION") == "" {
		return nil
	}
	window = ideWindow(path)
	if window == "" {
		return nil
	}
	return switchToWindow(stderr, window)
}

// switchToWindow brings an ide window that sits in another session in front
// of this client: a terminal that already shows that session only needs the
// window selected; one that does not needs a WezTerm window for the session;
// over ssh the client switches to it.
func switchToWindow(stderr io.Writer, window string) error {
	if os.Getenv("SSH_CONNECTION") == "" {
		if attached := tmuxDisplay(window, "#{session_attached}"); attached != "" && attached != "0" {
			// a terminal already shows that session
			_, _ = tmux("select-window", "-t", window)
			printfDiag(stderr, "already open in tmux session %s", tmuxDisplay(window, "#S"))
			return nil
		}
		if commandExists("wezterm") {
			// no terminal shows that session (its WezTerm window was
			// closed): give it a new WezTerm window, and leave this client
			// on its own session
			_, _ = tmux("select-window", "-t", window)
			return fishFunc("wezterm-attach", tmuxDisplay(window, "#{session_id}"))
		}
	}
	_, _ = tmux("select-window", "-t", window)
	_, _ = tmux("switch-client", "-t", window)
	return nil
}

// tmuxWindowsUnder lists the windows of the current session whose @ide_dir
// is under dir, the check that a tmux session already holds an ide window
// of this project.
func tmuxWindowsUnder(dir string) [][2]string {
	out, err := tmux("list-windows", "-F", "#{window_id} #{@ide_dir}")
	if err != nil {
		return nil
	}
	var found [][2]string
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && strings.HasPrefix(parts[1], dir+"/") {
			found = append(found, [2]string{parts[0], parts[1]})
		}
	}
	return found
}

// tmuxWindowOption reads a window option, empty when unset.
func tmuxWindowOption(window, option string) string {
	out, _ := tmux("show-option", "-wqv", "-t", window, option)
	return out
}

// replan restarts the claude pane of an ide window under other settings,
// with the plan that `project open` asked for: a plan applies only where
// claude starts, so the pane gets a fresh claude, and --continue carries the
// conversation over, because the settings name the endpoint that serves it.
// --continue picks the most recent conversation of the directory, which is
// the one of the pane unless another claude started there after it. What
// waited at a prompt in the old process is lost.
func replan(stderr io.Writer, window, planName string, claudeArgs []string) error {
	agent := tmuxWindowOption(window, "@ide_agent")
	editor := tmuxWindowOption(window, "@ide_editor")
	sock := tmuxWindowOption(window, "@ide_sock")
	if agent == "" || sock == "" {
		return errGeneral("the ide window of this checkout has no claude pane to restart")
	}
	if _, err := tmux("respawn-pane", "-k", "-t", agent,
		"-e", "IDE_EDITOR_PANE="+editor, "-e", "IDE_NVIM_SOCK="+sock); err != nil {
		return wrapGeneral(err)
	}
	args := append([]string{agent, sock, "--continue"}, claudeArgs...)
	if err := fishFunc("__ide_claude", args...); err != nil {
		return wrapGeneral(err)
	}
	_, _ = tmux("set-option", "-w", "-t", window, "@ide_plan", planName)
	under := "no plan"
	if planName != "" {
		under = "plan " + planName
	}
	printfDiag(stderr, "restarted the claude pane under %s; the conversation continues", under)
	return nil
}

// prepend builds an ide argument list with a mode flag and its value before
// the path and the rest.
func prepend(mode, session, path string, rest []string) []string {
	return append([]string{mode, session, path}, rest...)
}
