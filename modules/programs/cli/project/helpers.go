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

	"genixis/project/internal/backend"
	"genixis/project/internal/spec"
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

// popupSize is the 90 by 90 percent geometry of the tmux popups of this
// module. The ide-view fallback (cmd_ide_scripts.go) and the board pager
// (cmd_board.go) draw both dimensions from this one constant. Issue 466
// chose the constant over a second hand-synced mirror pair. The value still
// mirrors the popup binds of tmux.nix and the diff popup of review.lua by
// hand: the Go module keeps its own go.mod and imports nothing of the
// surrounding Nix (lib/project-package.nix), so no constant reaches across
// the trees.
const popupSize = "90%"

// tmuxWindowOptionLines reads one "window_id value" line per window from
// tmux list-windows, with the value of option: every session with -a, the
// current session with none, one target with -t. A failed read answers no
// lines.
func tmuxWindowOptionLines(option string, extra ...string) []string {
	args := append([]string{"list-windows", "-F", "#{window_id} #{" + option + "}"}, extra...)
	out, err := tmux(args...)
	if err != nil {
		return nil
	}
	return strings.Split(out, "\n")
}

// firstWindowWithOption is the window id of the first line that holds
// exactly value. The empty value matches nothing: it is the value of an
// unset option, and a search on it would take a window that lacks the
// option.
func firstWindowWithOption(lines []string, value string) string {
	if value == "" {
		return ""
	}
	for _, line := range lines {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && parts[1] == value {
			return parts[0]
		}
	}
	return ""
}

// ideWindow returns the window id of the ide window on dir, in any session,
// or empty. It reads the @ide_dir window option of every window.
func ideWindow(dir string) string {
	return firstWindowWithOption(tmuxWindowOptionLines("@ide_dir", "-a"), dir)
}

// tmuxWindowsWithOption lists the windows whose window option holds exactly
// value, across every session: @ide_dir names the ide windows of a checkout,
// @leg_dir the view windows of the headless legs of a worktree.
func tmuxWindowsWithOption(option, value string) []string {
	return windowsWithOption(tmuxWindowOptionLines(option, "-a"), value)
}

// windowsWithOption picks the window ids of the "id value" lines that hold
// exactly value. A value with spaces stays one value: the split keeps the
// rest of the line. The empty value matches nothing: it is the value of an
// unset option, and a sweep on it would take every window that lacks the
// option.
func windowsWithOption(lines []string, value string) []string {
	var windows []string
	if value == "" {
		return windows
	}
	for _, line := range lines {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) == 2 && parts[1] == value {
			windows = append(windows, parts[0])
		}
	}
	return windows
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

// worktreeOfBranch is the worktree that holds branch, or empty: the first
// match wins. skip names a path that never answers; a leg branch must not
// land in the main checkout, so the loops of list and review pass mainDir.
// The clean loop passes an empty skip: it skips the base branch and the
// current branch before the call, so the main checkout never answers. The
// open flow passes an empty skip too, because `project open <dir> main`
// opens main itself.
func worktreeOfBranch(worktrees []backend.Worktree, branch, skip string) string {
	for _, worktree := range worktrees {
		if worktree.Branch == branch && worktree.Path != skip {
			return worktree.Path
		}
	}
	return ""
}

// emitEnvelope writes the machine-facing outcome of one command: the error
// of a failed run to code and detail with its diagnostic line, the envelope
// with the ToolVersion and SchemaVersion meta, and the exit code. The
// machine paths of the session commands and of list share it; the plain
// text paths stay with their callers.
func emitEnvelope(command string, stdout, stderr io.Writer, started time.Time, data any, err *toolError, warnings []spec.Warning) spec.ExitCode {
	code := spec.Success
	var detail *spec.Error
	if err != nil {
		code = err.code
		detail = err.err
		printfDiag(stderr, "%s", err.err.Message)
	}
	envelope := spec.Build(command, code, data, detail, warnings, time.Since(started).Milliseconds())
	envelope.Meta.ToolVersion = version
	envelope.Meta.SchemaVersion = "1.0"
	if writeErr := spec.Write(stdout, envelope); writeErr != nil {
		return spec.GeneralError
	}
	return code
}
