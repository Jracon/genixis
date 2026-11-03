package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// delegationForm reports whether an argument carries the scp-style
// user@host:<dir> prefix at all: a colon, and a left part that names a host
// (no path characters in it). The user check is the caller's, so it can say
// what is missing.
func delegationForm(arg string) (hostPart, dir string, ok bool) {
	parts := strings.SplitN(arg, ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	if strings.ContainsAny(parts[0], "/~") {
		return "", "", false
	}
	return parts[0], parts[1], true
}

// delegate runs the command on another machine over ssh and, unless the
// session is headless, opens a local WezTerm window that attaches to the
// remote tmux session.
//
// The arguments travel base64-encoded in one variable, joined with NUL,
// because ssh joins a command line with spaces and the remote shell would
// re-parse it, which breaks a prompt that holds spaces. The remote runs the
// command through a login shell, so a tmux server that a first call starts
// has a full environment for its hooks, and it never attaches: the local
// half opens a window that attaches instead.
func delegate(action string, args *sessionArgs, rest []string) error {
	remote := delegationArgs(action, args, rest)
	payload := base64.StdEncoding.EncodeToString([]byte(strings.Join(remote, "\x00")))
	run := "exec $SHELL -lc 'set -g PROJECT_REMOTE_ARGV " + payload +
		"; project (printf %s $PROJECT_REMOTE_ARGV | base64 -d | string split0)'"
	ssh := exec.Command("ssh", "-o", "ConnectTimeout=10", args.target, "--", run)
	ssh.Stdin = os.Stdin
	ssh.Stdout = os.Stdout
	ssh.Stderr = os.Stderr
	if err := ssh.Run(); err != nil {
		return errUnavailable("ssh to %s failed: %v", args.target, err)
	}
	if args.headless {
		return nil
	}
	return attachRemote(args.target, args.remoteDir)
}

// delegationArgs builds the argument list the remote runs: the action, the
// dir after the colon of the user@host:dir prefix (never the prefix itself,
// or the remote would parse it as another delegation target), the remaining
// positionals, then the flags. A spawn without --plan inherits the plan of
// this session, which the remote cannot see in its environment, so the
// inherited name travels as an explicit --plan. The form is the payload the
// former fish implementation built, so a remote on either revision accepts
// it.
func delegationArgs(action string, args *sessionArgs, rest []string) []string {
	remote := append([]string{action, args.remoteDir}, rest[1:]...)
	if args.from != "" {
		remote = append(remote, "--from", args.from)
	}
	if args.as != "" {
		remote = append(remote, "--as", args.as)
	}
	if args.headless {
		remote = append(remote, "--headless")
	}
	if args.permissionMode != "" {
		remote = append(remote, "--permission-mode", args.permissionMode)
	}
	if args.identity != "" {
		remote = append(remote, "--identity", args.identity)
	}
	if args.planFlag != "" {
		remote = append(remote, "--plan", args.planFlag)
	}
	return remote
}

// attachRemote opens the local WezTerm window that attaches to the remote
// tmux session, titled host:session so it never collides with the window of
// a local project of the same name. A window that is already open is
// selected, because two clients on one tmux session mirror each other's
// current window.
func attachRemote(target, dir string) error {
	host := target
	if at := strings.Index(host, "@"); at >= 0 {
		host = host[at+1:]
	}
	resolved, err := resolvePath(dir)
	if err != nil {
		return wrapGeneral(err)
	}
	session := sessionName(filepath.Base(resolved))
	title := host + ":" + session
	if !commandExists("wezterm") {
		return errGeneral("no WezTerm here; attach with ssh -t %s tmux attach -t =%s", target, session)
	}
	base := []string{"-u", "TMUX", "-u", "TMUX_PANE", "wezterm"}
	cli := append(append([]string{}, base...), "cli")
	if tabID, ok := weztermTabID(cli, title); ok {
		return runEnv(append(append([]string{}, cli...), "activate-tab", "--tab-id", tabID)...)
	}
	attach := "exec '$SHELL' -lc 'tmux attach -t =" + session + "'"
	sshAttach := []string{"ssh", "-o", "ConnectTimeout=10", "-t", target, "--", attach}
	pane, err := runEnvOutput(append(append(append([]string{}, cli...), "--no-auto-start",
		"spawn", "--new-window", "--"), sshAttach...)...)
	if err != nil || pane == "" {
		// no running WezTerm answers, so start one; its window cannot be
		// titled from here
		cmd := exec.Command("env", append(append(append([]string{}, base...), "start", "--"), sshAttach...)...)
		if cmd.Start() == nil {
			_ = cmd.Process.Release()
		}
		return nil
	}
	// the tab and window titles stick: the pane title keeps following what
	// the remote tmux pushes, but the override names the host, so the window
	// stays distinct from a local project of the same name. The titles are
	// cosmetic: a wezterm list right after the spawn can miss the new tab,
	// so a failed title-set never fails the attach.
	tabID, windowID := weztermIDsForPane(cli, pane)
	if tabID != "" {
		_ = runEnv(append(append(append([]string{}, cli...), "set-tab-title", "--tab-id", tabID), title)...)
	}
	if windowID != "" {
		_ = runEnv(append(append(append([]string{}, cli...), "set-window-title", "--window-id", windowID), title)...)
	}
	return nil
}

type weztermPane struct {
	PaneID   int    `json:"pane_id"`
	TabID    int    `json:"tab_id"`
	WindowID int    `json:"window_id"`
	TabTitle string `json:"tab_title"`
}

func weztermList(cli []string) []weztermPane {
	out, err := runEnvOutput(append(append([]string{}, cli...), "list", "--format", "json")...)
	if err != nil || out == "" {
		return nil
	}
	var panes []weztermPane
	if err := json.Unmarshal([]byte(out), &panes); err != nil {
		return nil
	}
	return panes
}

func weztermTabID(cli []string, title string) (string, bool) {
	for _, pane := range weztermList(cli) {
		if pane.TabTitle == title {
			return fmt.Sprint(pane.TabID), true
		}
	}
	return "", false
}

func weztermIDsForPane(cli []string, pane string) (tabID, windowID string) {
	for _, entry := range weztermList(cli) {
		if fmt.Sprint(entry.PaneID) == pane {
			return fmt.Sprint(entry.TabID), fmt.Sprint(entry.WindowID)
		}
	}
	return "", ""
}

// runEnv runs `env <kv...> <command...>` and waits for it.
func runEnv(args ...string) error {
	cmd := exec.Command("env", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// runEnvOutput runs `env <kv...> <command...>` and captures stdout.
func runEnvOutput(args ...string) (string, error) {
	cmd := exec.Command("env", args...)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}
