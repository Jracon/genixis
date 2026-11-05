package main

import (
	"encoding/base64"
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
// re-parse it, which breaks a prompt that holds spaces. The variable must
// be exported, because the remote project reads it from its environment.
// The remote runs the command through a login shell, so a tmux server that
// a first call starts has a full environment for its hooks, and it never
// attaches: the local half opens a window that attaches instead.
func delegate(action string, args *sessionArgs, rest []string) error {
	remote := delegationArgs(action, args, rest)
	payload := base64.StdEncoding.EncodeToString([]byte(strings.Join(remote, "\x00")))
	run := delegationCommand(payload)
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

// delegationCommand builds the command string that the ssh call runs on
// the remote host: a login shell that exports the payload variable and
// runs the project command on its decoded words.
func delegationCommand(payload string) string {
	return "exec $SHELL -lc 'set -gx PROJECT_REMOTE_ARGV " + payload +
		"; project (printf %s $PROJECT_REMOTE_ARGV | base64 -d | string split0)'"
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

// attachRemote opens the local tab that attaches to the remote tmux session:
// a tab of the WezTerm window of the remote user and host, which carries
// user@host as its computed title (issues #101 and #115). The tab carries
// the session name, so it stays distinct from a local session of the same
// project name. A tab that is already open is selected, because two clients
// on one tmux session mirror each other's current window. The ssh of the
// tab forwards the GUI socket (issue #141), so the shell of the tab can
// open tabs in the same window.
func attachRemote(target, dir string) error {
	// the prefix names the user and the host; a bare host leaves the user to
	// ssh, which picks the local one, so the title does the same
	userName, host := localUserName(), target
	if at := strings.Index(target, "@"); at >= 0 {
		userName, host = target[:at], target[at+1:]
	}
	resolved, err := resolvePath(dir)
	if err != nil {
		return wrapGeneral(err)
	}
	session := sessionName(filepath.Base(resolved))
	if !commandExists("wezterm") {
		return errGeneral("no WezTerm here; attach with ssh -t %s tmux attach -t =%s", target, session)
	}
	_, err = weztermHostTab(hostWindowTitle(userName, host), session,
		remoteAttachCommand(target, session, localGuiForward()), false)
	return err
}

// remoteAttachCommand builds the tab command that puts a tmux session of a
// remote login on screen: the tab runs on the machine that owns the window,
// so it ssh's into the login that runs the tmux server. A forward rides the
// ssh when one exists (issue #141), so the shell of the tab opens tabs in
// the window it lives in. $SHELL stays unquoted in the remote command, or
// the remote login shell reads it as the name of a command.
func remoteAttachCommand(target, session string, forward *guiForward) []string {
	attach := "exec $SHELL -lc 'tmux attach -t =" + session + "'"
	if env := forwardEnvArgs(forward); len(env) > 0 {
		attach = "exec env " + strings.Join(env, " ") + " $SHELL -lc 'tmux attach -t =" + session + "'"
	}
	return sshTabArgs(target, attach, forward)
}
