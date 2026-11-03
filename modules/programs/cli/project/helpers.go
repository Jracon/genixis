package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

// gitTopLevel is the working tree root of dir, or empty outside a repo.
func gitTopLevel(dir string) string {
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// runCmd runs one command, discards nothing, and returns trimmed stdout.
func runCmd(dir string, env []string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Env = append(os.Environ(), env...)
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = io.Discard
	err := cmd.Run()
	return strings.TrimSpace(stdout.String()), err
}

// commandExists reports whether name is on PATH.
func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// fishFunc calls a fish function by name with arguments, the way the former
// writeShellScriptBin wrapper called project: `fish -c '<fn> $argv' -- ...`.
// Arguments pass through as argv, so no shell escaping of values happens.
func fishFunc(fn string, args ...string) error {
	full := append([]string{"-c", fn + " $argv", "--"}, args...)
	cmd := exec.Command("fish", full...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// fishFuncOutput calls a fish function and captures stdout.
func fishFuncOutput(fn string, args ...string) (string, error) {
	full := append([]string{"-c", fn + " $argv", "--"}, args...)
	cmd := exec.Command("fish", full...)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}

// detached starts a command in its own process group and releases it, the
// Go form of fish's `... &; disown`. The child survives this process.
func detached(dir string, name string, args ...string) {
	cmd := exec.Command(name, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if cmd.Start() == nil {
		_ = cmd.Process.Release()
	}
}

// warmDirenv evaluates the .envrc of path once, so the panes that `ide`
// starts next all hit the nix-direnv cache instead of racing to evaluate
// it themselves. An .envrc that is not allowed yet fails silently here and
// is left for the panes to report; a slow evaluation stops after a minute
// so the window is never held up for long.
func warmDirenv(path string) {
	if !commandExists("direnv") {
		return
	}
	if info, err := os.Stat(path + "/.envrc"); err != nil || info.IsDir() {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "direnv", "exec", path, "true")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	_ = cmd.Run()
}

// pullBehind starts a fast-forward pull in the background, so a window
// opens at once and still catches up with upstream. Fast-forward only, so
// local work is safe.
func pullBehind(path string) {
	detached(path, "git", "-C", path, "pull", "--ff-only", "--quiet")
}

// tmux runs one tmux command and returns trimmed stdout. The tmux binary is
// called directly, which is what `command tmux` did in the fish function:
// on Darwin the interactive tmux function would add -N, and that behaviour
// belongs to interactive use only.
func tmux(args ...string) (string, error) {
	cmd := exec.Command("tmux", args...)
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), err
}

// ideWindow returns the window id of the ide window on dir, in any session,
// or empty. It reads the @ide_dir window option of every window.
func ideWindow(dir string) string {
	out, err := tmux("list-windows", "-a", "-F", "#{window_id} #{@ide_dir}")
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

// tmuxWindowsWithDir lists every window whose @ide_dir starts with prefix,
// as (window id, dir) pairs.
func tmuxWindowsWithDir(prefix string) [][2]string {
	out, err := tmux("list-windows", "-a", "-F", "#{window_id} #{@ide_dir}")
	if err != nil {
		return nil
	}
	var found [][2]string
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && strings.HasPrefix(parts[1], prefix) {
			found = append(found, [2]string{parts[0], parts[1]})
		}
	}
	return found
}

// tmuxDisplay formats one tmux format string against a target (empty for
// the current one).
func tmuxDisplay(target, format string) string {
	args := []string{"display-message", "-p"}
	if target != "" {
		args = append(args, "-t", target)
	}
	out, _ := tmux(append(args, format)...)
	return out
}

// writeCDFile tells the calling fish stub to change directory: close and
// convert cannot chdir their parent, so the stub reads the path from the
// file named by PROJECT_CD_FILE after the binary ends. Nothing is written
// when no stub is listening, which is the case for agent sessions.
func writeCDFile(path string) {
	name := os.Getenv("PROJECT_CD_FILE")
	if name == "" || path == "" {
		return
	}
	_ = os.WriteFile(name, []byte(path+"\n"), 0o644)
}

// claudeStopTree stops the background Claude sessions that were started in
// a worktree, because after close they have nothing left to work in.
func claudeStopTree(tree string) {
	if !commandExists("claude") {
		return
	}
	out, err := runCmd("", nil, "claude", "agents", "--json", "--cwd", tree)
	if err != nil {
		return
	}
	var sessions []struct {
		ID   string `json:"id"`
		Kind string `json:"kind"`
	}
	if err := jsonUnmarshal([]byte(out), &sessions); err != nil {
		return
	}
	for _, session := range sessions {
		if session.Kind == "background" {
			_ = exec.Command("claude", "stop", session.ID).Run()
		}
	}
}

func jsonUnmarshal(data []byte, v any) error {
	return json.Unmarshal(data, v)
}
