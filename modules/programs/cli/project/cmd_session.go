package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"genixis/project/internal/backend"
	"genixis/project/internal/coord"
	"genixis/project/internal/identity"
	"genixis/project/internal/settings"
	"genixis/project/internal/spec"
)

// gitBackend is the worktree and branch layer of every subcommand.
var gitBackend backend.Backend = backend.NewGit()

// sessionArgs are the flags that open, add, and spawn share.
type sessionArgs struct {
	from           string
	as             string
	plan           string // the --plan value, "" when the flag is absent
	planFlag       string // the value that a delegated call forwards: the flag, or the inherited plan
	headless       bool
	permissionMode string
	identity       string
	printSettings  bool
	// target and remoteDir are set when the dir argument delegates over
	// ssh; the rest of the flow runs on the remote host instead.
	target    string
	remoteDir string
}

// sessionResult is what a finished session command produced.
type sessionResult struct {
	// claim is the acquired claim: the branch and its worktree.
	claim coord.Claim
	// session names a headless background session.
	session string
	// sessionID is the id that `claude --bg` printed for a headless
	// session. `claude attach` and `claude stop` take it, and it names one
	// session alone: a stopped session stays listed under its name for
	// about an hour, so the name of a re-looped leg can name two sessions
	// and the id is the only handle that cannot pick the wrong one
	// (issue #208).
	sessionID string
	// warnings are the non-fatal diagnostics, for the envelope or stderr.
	warnings []spec.Warning
}

// parseSessionArgs splits flags from positionals. It mirrors the argparse
// call of the fish implementation: unknown flags and missing values are
// argument errors.
func parseSessionArgs(argv []string) (*sessionArgs, []string, *toolError) {
	args := &sessionArgs{}
	var positionals []string
	for i := 0; i < len(argv); i++ {
		arg := argv[i]
		var value string
		hasValue := false
		switch arg {
		case "--headless":
			args.headless = true
			continue
		case "--print-settings":
			args.printSettings = true
			continue
		case "--from", "--as", "--plan", "--permission-mode", "--identity":
			if i+1 >= len(argv) {
				return nil, nil, errArg("%s needs a value", arg)
			}
			i++
			value = argv[i]
			hasValue = true
		default:
			if strings.HasPrefix(arg, "--") {
				return nil, nil, errArg("unknown option %s", arg)
			}
			positionals = append(positionals, arg)
			continue
		}
		if !hasValue {
			continue
		}
		switch arg {
		case "--from":
			args.from = value
		case "--as":
			args.as = value
		case "--plan":
			args.plan = value
			args.planFlag = value
		case "--permission-mode":
			args.permissionMode = value
		case "--identity":
			args.identity = value
		}
	}
	return args, positionals, nil
}

// cmdSession runs open, add, or spawn. add and spawn --headless are
// machine-facing: their outcome is one JSON envelope on stdout. The others
// are interactive and stay plain text.
func cmdSession(action string, argv []string, stdout, stderr io.Writer) spec.ExitCode {
	if helpFlag(argv) {
		printCommandDoc(stdout, action)
		return spec.Success
	}
	started := time.Now()
	args, positionals, err := parseSessionArgs(argv)
	if err != nil {
		return reportSession(action, false, stdout, stderr, started, nil, err)
	}
	machine := (action == "add" || (action == "spawn" && args.headless)) && !args.printSettings
	if err := validateSessionArgs(action, args, positionals); err != nil {
		return reportSession(action, machine, stdout, stderr, started, nil, err)
	}
	result, err := runSession(action, args, positionals, stdout, stderr)
	return reportSession(action, machine, stdout, stderr, started, result, err)
}

// reportSession turns the outcome of a session command into the plain-text
// or the envelope form.
func reportSession(action string, machine bool, stdout, stderr io.Writer, started time.Time, result *sessionResult, err *toolError) spec.ExitCode {
	var warnings []spec.Warning
	var data any
	if result != nil {
		warnings = result.warnings
		if machine {
			fields := map[string]any{
				"branch":   result.claim.Branch,
				"worktree": result.claim.Worktree,
			}
			if result.session != "" {
				fields["session"] = result.session
			}
			if result.sessionID != "" {
				fields["session_id"] = result.sessionID
			}
			data = fields
		}
	}
	var detail *spec.Error
	code := spec.Success
	if err != nil {
		code = err.code
		detail = err.err
		printfDiag(stderr, "%s", err.err.Message)
	}
	if machine {
		envelope := spec.Build(action, code, data, detail, warnings, time.Since(started).Milliseconds())
		envelope.Meta.ToolVersion = version
		envelope.Meta.SchemaVersion = "1.0"
		if writeErr := spec.Write(stdout, envelope); writeErr != nil {
			return spec.GeneralError
		}
		return code
	}
	for _, warning := range warnings {
		printfDiag(stderr, "%s", warning.Message)
	}
	return code
}

func validateSessionArgs(action string, args *sessionArgs, positionals []string) *toolError {
	if action != "open" && action != "add" && action != "spawn" {
		return errArg("unknown action %s", action)
	}
	if action == "add" && args.planFlag != "" {
		return errArg("add starts no session, so it takes no --plan")
	}
	if action == "add" && args.headless {
		return errArg("add starts no session, so it takes no --headless")
	}
	if args.as != "" && strings.Contains(args.as, "/") {
		return errArg("--as is a directory name, so it can't contain /")
	}
	if len(positionals) > 2 && action != "spawn" {
		return errArg("too many arguments")
	}
	if (args.from != "" || args.as != "") && len(positionals) < 2 {
		return errArg("--from and --as need a branch")
	}
	if action != "open" && len(positionals) < 2 {
		return errArg("%s needs a <dir> and a <branch>; run `project help %s`", action, action)
	}
	if action == "spawn" && len(positionals) < 3 {
		return errArg("spawn needs a prompt after the branch")
	}
	return nil
}

// runSession is the shared flow of open, add, and spawn: resolve the
// project, acquire the claim on the branch (the worktree), set the identity
// of the leg, and hand over to the action-specific ending.
func runSession(action string, args *sessionArgs, positionals []string, stdout, stderr io.Writer) (*sessionResult, *toolError) {
	result := &sessionResult{}
	// a spawn without --plan inherits the plan of the session that runs it,
	// which PROJECT_PLAN in the environment names; --plan none starts no
	// plan, and the empty PROJECT_PLAN it writes stops a child of that
	// session from inheriting one
	if args.plan == "" && action == "spawn" && os.Getenv("PROJECT_PLAN") != "" {
		args.plan = os.Getenv("PROJECT_PLAN")
		args.planFlag = args.plan
	}

	// scp-style delegation: user@host:<dir> runs on that host over ssh.
	// Only open and spawn delegate; the remote form needs an existing
	// project, because the questions below have no terminal to answer them.
	if len(positionals) > 0 {
		if hostPart, dir, ok := delegationForm(positionals[0]); ok {
			if !strings.Contains(hostPart, "@") {
				return nil, errArg("%s names a host but no user; write user@%s", hostPart, positionals[0])
			}
			if action == "add" {
				return nil, errArg("the user@host: form works with open and spawn only")
			}
			if dir == "" || dir == "." {
				return nil, errArg("%s names no project after the host", positionals[0])
			}
			args.target = hostPart
			args.remoteDir = dir
			if err := delegate(action, args, positionals); err != nil {
				return nil, asToolError(err)
			}
			return result, nil
		}
	}

	// plan resolution: the empty value means no plan; none is reserved and
	// starts no plan, so a plan file named none is not reachable
	planName := ""
	var plan *settings.Plan
	if args.plan != "" && args.plan != "none" {
		planName = args.plan
		loaded, err := loadPlan(planName)
		if err != nil {
			return nil, err
		}
		plan = loaded
	}

	dirArgValue := ""
	if len(positionals) > 0 {
		dirArgValue = positionals[0]
	}
	branch := ""
	if len(positionals) > 1 {
		branch = positionals[1]
	}
	prompt := ""
	if len(positionals) > 2 {
		prompt = strings.Join(positionals[2:], " ")
	}

	dir, err := dirArg(dirArgValue)
	if err != nil {
		return nil, wrapGeneral(err)
	}
	here := gitTopLevel(cwd())

	// pointed at one of a project's checkouts (for example `project open`
	// inside one): open that one
	if info, statErr := os.Stat(dir); statErr == nil && info.IsDir() &&
		isProjectDir(filepath.Dir(dir)) && !isProjectDir(dir) {
		if filepath.Base(dir) != "main" && branch == "" {
			branch = gitBackend.CurrentBranch(dir)
		}
		dir = filepath.Dir(dir)
	}
	mainDir := filepath.Join(dir, "main")

	if _, statErr := os.Stat(dir); os.IsNotExist(statErr) {
		// a delegated call cannot answer the question below: its ssh has no
		// terminal to read
		if os.Getenv("PROJECT_REMOTE_ARGV") != "" {
			return nil, errNotFound("%s doesn't exist here; ssh in and create it, then delegate", dir)
		}
		if err := createProject(dir, stderr); err != nil {
			return nil, err
		}
	} else if !isProjectDir(dir) {
		if _, gitErr := os.Stat(filepath.Join(dir, ".git")); gitErr != nil {
			return nil, errNotFound("%s is not a project (no main/ checkout)", dir)
		}
		// a delegated call cannot answer the question below, and a plain
		// repo would end in an ide window that attaches, which has no
		// terminal to attach to
		if os.Getenv("PROJECT_REMOTE_ARGV") != "" {
			return nil, errNotFound("%s is a plain repo here; ssh in and convert it, then delegate", dir)
		}
		// a plain repo: offer to convert it, unless that was declined for
		// good
		if gitBackend.ConfigGet(dir, "project.convert") != "false" {
			answer := ask(stderr, "%s is a plain repo; convert it to a project? [y/N/never] ", dir)
			switch strings.ToLower(answer) {
			case "y", "yes":
				if code := cmdConvert([]string{dir}, stdout, stderr); code != spec.Success {
					return nil, errGeneral("convert failed")
				}
			case "never":
				if err := gitBackend.ConfigSet(dir, "project.convert", "false"); err != nil {
					return nil, wrapGeneral(err)
				}
				printfDiag(stderr, "won't ask again; undo with `git -C %s config --unset project.convert`", dir)
			}
		}
		// still plain: open it as it is, but branches need the project
		// layout
		if !isProjectDir(dir) {
			if branch != "" {
				return nil, errNotFound("%s is a plain repo, so it can't open branches as worktrees", dir)
			}
			if args.plan != "" {
				return nil, errArg("%s is a plain repo, so it can't start a session with --plan", dir)
			}
			if err := ideBuild([]string{dir}); err != nil {
				return nil, err
			}
			return result, nil
		}
	}

	project := filepath.Base(dir)
	// one Claude memory for the whole project, shared by main and its
	// worktrees and kept after close (transcripts stay per path in ~/.claude)
	if err := os.MkdirAll(filepath.Join(dir, ".claude", "memory"), 0o755); err != nil {
		return nil, wrapGeneral(err)
	}
	memoryDir := filepath.Join(dir, ".claude", "memory")

	if branch == "" {
		// catch up with upstream without holding up the window:
		// fast-forward only, so local work is safe
		pullBehind(mainDir)
		warmDirenv(mainDir)
		claudeArgs := []string{"--settings", string(settings.Build(settings.Settings{
			MemoryDir: memoryDir,
			Plan:      plan,
			PlanName:  planName,
		}))}
		if args.printSettings {
			fmt.Fprintln(stdout, claudeArgs[1])
			return result, nil
		}
		if err := ideOpen(stderr, project, dir, planName, mainDir, append([]string{"main"}, claudeArgs...)); err != nil {
			return nil, asToolError(err)
		}
		return result, nil
	}

	// the claim: an existing worktree of the branch wins; else
	// <dir>/<name>, the branch with / as - unless --as names one
	tree := ""
	worktrees, err := gitBackend.Worktrees(mainDir)
	if err != nil {
		return nil, wrapGeneral(err)
	}
	for _, worktree := range worktrees {
		if worktree.Branch == branch {
			tree = worktree.Path
			break
		}
	}
	if tree == "" {
		name := args.as
		if name == "" {
			name = strings.ReplaceAll(branch, "/", "-")
		}
		tree = filepath.Join(dir, name)
	}

	if _, statErr := os.Stat(tree); os.IsNotExist(statErr) {
		claim, acqErr := acquireClaim(action, dir, mainDir, tree, branch, args, here, result)
		if acqErr != nil {
			return nil, acqErr
		}
		result.claim = claim
	} else if action == "open" {
		// catch up with upstream without holding up the window
		pullBehind(tree)
	}
	result.claim = coord.Claim{Branch: branch, Worktree: tree}

	// the identity of the leg, also for a worktree that already exists: git
	// then applies it to every process in the worktree, not only to the
	// shells that the agent session starts
	legIdentity, idErr := identity.Resolve(mainDir, args.identity)
	if idErr != nil {
		return nil, wrapGeneral(idErr)
	}
	if err := identity.Apply(gitBackend, mainDir, tree, legIdentity); err != nil {
		return nil, wrapGeneral(err)
	}

	if action == "add" {
		return result, nil
	}

	// main/.git is outside the worktree, so the agent's reads of its own
	// git metadata would prompt: allow every entry there (as found now) but
	// other worktrees' metadata, and deny edits
	gitDir, err := runCmd(tree, nil, "git", "rev-parse", "--absolute-git-dir")
	if err != nil {
		return nil, wrapGeneral(err)
	}
	mainGit := filepath.Join(mainDir, ".git")
	reads := settings.DiscoverReads(gitDir, mainGit)

	if action == "spawn" {
		spawnSettings := settings.Settings{
			MemoryDir:   memoryDir,
			Permissions: &settings.Permissions{Reads: reads, GitDir: mainGit},
			Plan:        plan,
			Markers:     settings.SpawnMarkers(args.headless),
			PlanName:    planName,
		}
		claudeArgs := []string{"--settings", string(settings.Build(spawnSettings))}
		if args.printSettings {
			fmt.Fprintln(stdout, claudeArgs[1])
			return result, nil
		}
		if args.permissionMode != "" {
			claudeArgs = append(claudeArgs, "--permission-mode", args.permissionMode)
		}
		if !args.headless {
			return spawnWindowed(stderr, result, project, tree, branch, claudeArgs, prompt)
		}
		return spawnHeadless(stderr, result, tree, project, branch, claudeArgs, prompt)
	}

	// open with a branch: the session settings carry the same permission
	// rules as a spawn, but no session markers
	openSettings := settings.Settings{
		MemoryDir:   memoryDir,
		Permissions: &settings.Permissions{Reads: reads, GitDir: mainGit},
		Plan:        plan,
		PlanName:    planName,
	}
	claudeArgs := []string{"--settings", string(settings.Build(openSettings))}
	if args.printSettings {
		fmt.Fprintln(stdout, claudeArgs[1])
		return result, nil
	}
	warmDirenv(tree)
	if err := ideOpen(stderr, project, dir, planName, tree, append([]string{branch}, claudeArgs...)); err != nil {
		return nil, asToolError(err)
	}
	return result, nil
}

// acquireClaim creates the worktree of a new branch: the atomic claim of
// the coordination vocabulary. A new branch starts from --from, else from
// the branch of the worktree the command runs in, else from the default
// branch. A fetch with a limit brings in what was merged upstream since
// main was last pulled. A spawn whose fetch fails refuses a new branch
// from the default branch: a leg must not start on a base that may be
// older than origin main (issue #100).
func acquireClaim(action, dir, mainDir, tree, branch string, args *sessionArgs, here string, result *sessionResult) (coord.Claim, *toolError) {
	base := gitBackend.DefaultBranch(mainDir)
	if base == "" {
		base = "HEAD"
	}
	if current := gitBackend.CurrentBranch(mainDir); current != "" && current != base {
		warn(result, "UNEXPECTED_BRANCH", "main/ is on %s, not the default branch %s; branching from %s", current, base, base)
	}
	from := args.from
	if from == "" && here != "" && here != mainDir && filepath.Dir(here) == dir {
		from = gitBackend.CurrentBranch(here)
		warn(result, "BRANCH_FROM_WORKTREE", "branching from %s, because you are in its worktree (--from overrides)", from)
	}
	if from != "" {
		if gitBackend.RefExists(mainDir, "refs/heads/"+from) {
			base = from
		} else if gitBackend.RefExists(mainDir, "refs/remotes/origin/"+from) {
			base = "origin/" + from
		} else {
			return coord.Claim{}, errNotFound("no branch %s to start from", from)
		}
	}
	// fetch so a new branch starts from what's been merged upstream since
	// main was last pulled; the timeout covers remotes that are only
	// reachable from some networks
	fetched := gitBackend.Fetch(mainDir, false, 10*time.Second)
	if fetched.TimedOut || fetched.Err != nil {
		// a spawn starts a leg that works unattended, and a failed fetch
		// means local main may be older than origin main: a leg on such a
		// base works on problems that main already solved, so the spawn
		// fails loudly instead (exit 12, which the dispatcher retries).
		// A branch that already exists continues its own work, and --from
		// names a base the caller chose, so neither depends on the fetch.
		// open and add keep the fallback: a person reads the warning.
		if action == "spawn" && from == "" &&
			!gitBackend.RefExists(mainDir, "refs/heads/"+branch) &&
			!gitBackend.RefExists(mainDir, "refs/remotes/origin/"+branch) {
			return coord.Claim{}, errUnavailable(
				"couldn't fetch origin, so a spawn would start %s from local %s, which may be older than origin main; retry when origin answers, or pass --from",
				branch, base)
		}
		warn(result, "FETCH_FAILED", "couldn't fetch origin; branching from local %s", base)
	} else if from == "" && gitBackend.RefExists(mainDir, "refs/remotes/origin/"+base) {
		base = "origin/" + base
	}

	var err error
	switch {
	case gitBackend.RefExists(mainDir, "refs/heads/"+branch):
		err = gitBackend.AddWorktree(mainDir, tree, branch, backend.AddExisting, base)
	case gitBackend.RefExists(mainDir, "refs/remotes/origin/"+branch):
		err = gitBackend.AddWorktree(mainDir, tree, branch, backend.AddTrack, base)
	default:
		err = gitBackend.AddWorktree(mainDir, tree, branch, backend.AddNew, base)
	}
	if err != nil {
		return coord.Claim{}, wrapGeneral(err)
	}
	// remember the parent so close counts a merge into it as merged
	if from != "" && gitBackend.RefExists(mainDir, "refs/heads/"+branch) {
		if err := gitBackend.ConfigSet(mainDir, "branch."+branch+".projectBase", from); err != nil {
			return coord.Claim{}, wrapGeneral(err)
		}
	}

	// an .envrc that matches main's is as trusted as main's: allow it, so
	// the environment loads without a manual `direnv allow` (a branch that
	// edits .envrc still needs one)
	setupWorktree(mainDir, dir, tree)
	return coord.Claim{Branch: branch, Worktree: tree}, nil
}

// setupWorktree finishes a new worktree the way every maker of one does: an
// .envrc that matches main's is allowed, so the environment loads without a
// manual `direnv allow`, and the include lists put their untracked files
// into the tree (see includes.go).
func setupWorktree(mainDir, dir, tree string) {
	if commandExists("direnv") {
		envrc := filepath.Join(tree, ".envrc")
		mainEnvrc := filepath.Join(mainDir, ".envrc")
		if _, statErr := os.Stat(envrc); statErr == nil {
			if filesEqual(envrc, mainEnvrc) && direnvStatusAllowed(mainDir) {
				_ = exec.Command("direnv", "allow", tree).Run()
			}
		}
	}
	materialize(mainDir, tree, readIncludeLists(mainDir, dir))
}

// spawnWindowed starts the session in a window of its own, where the user
// can watch the agent and answer its permission prompts.
func spawnWindowed(stderr io.Writer, result *sessionResult, project, tree, branch string, claudeArgs []string, prompt string) (*sessionResult, *toolError) {
	if os.Getenv("PROJECT_REMOTE_ARGV") != "" && ideWindow(tree) != "" {
		// a rerun after the caller's connection dropped: the window and its
		// session are still there, so keep them and let the caller attach
		// again
		printfDiag(stderr, "%s already has an ide window", tree)
		return result, nil
	}
	printfDiag(stderr, "ide window %q in tmux session %q", branch, project)
	warmDirenv(tree)
	ideArgs := append([]string{"--detach", project, tree, branch}, claudeArgs...)
	ideArgs = append(ideArgs, "--", prompt)
	if err := ideBuild(ideArgs); err != nil {
		return nil, err
	}
	return result, nil
}

// spawnHeadless starts the session in the background and opens the view
// window of the leg (see legview.go). A background session cannot ask for
// permission, so it waits at every prompt; the forge hook denies a forge
// command that it would ask about.
func spawnHeadless(stderr io.Writer, result *sessionResult, tree, project, branch string, claudeArgs []string, prompt string) (*sessionResult, *toolError) {
	if !commandExists("claude") {
		return nil, errUnavailable("claude is not on PATH, so the headless session cannot start")
	}
	if !argsHasPermissionMode(claudeArgs) {
		warn(result, "NO_PERMISSION_MODE", "no --permission-mode, so the session waits at every permission prompt")
	}
	// run from the worktree, and in its direnv environment when that's
	// allowed
	runArgs := append([]string{"--bg", "--name", project + ": " + branch}, claudeArgs...)
	runArgs = append(runArgs, "--", prompt)
	cmd := exec.Command("claude", runArgs...)
	if commandExists("direnv") {
		if _, statErr := os.Stat(filepath.Join(tree, ".envrc")); statErr == nil && direnvStatusAllowed(tree) {
			cmd = exec.Command("direnv", append([]string{"exec", ".", "claude"}, runArgs...)...)
		} else if statErr == nil {
			printfDiag(stderr, "%s/.envrc isn't allowed, so the agent starts without its environment", tree)
		}
	}
	cmd.Dir = tree
	// `claude --bg` prints the id of the session on its way out, and that id
	// is the one handle that attaches and stops exactly this session (issue
	// #208). The print names no stream the docs pin, so both streams land in
	// one buffer, and the whole output still reaches stderr after the run,
	// as the machine contract keeps it (see docs/project.md).
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Run(); err != nil {
		_, _ = stderr.Write(output.Bytes())
		return nil, wrapGeneral(err)
	}
	_, _ = stderr.Write(output.Bytes())
	result.session = project + ": " + branch
	result.sessionID = parseSessionID(output.String())
	if result.sessionID == "" {
		warn(result, "NO_SESSION_ID", "claude --bg printed no session id, so the view window attaches by name and the release resolves the name")
	}
	printfDiag(stderr, "session %q (claude attach %q)", result.session, legViewTarget(result.session, result.sessionID))
	// the window needs the running session, so it opens after the start:
	// one view window in the tmux session of the project, which a failure
	// here never costs the leg (see legview.go)
	legViewWindow(stderr, project, tree, branch, result.session, result.sessionID)
	return result, nil
}

// parseSessionID reads the session id out of the output of `claude --bg`.
// The documented print is one block on the way out (code.claude.com/docs,
// agent view, "Dispatch an agent from your shell"):
//
//	backgrounded · 7c5dcf5d · flaky-test-fix
//	  claude agents             list sessions
//	  claude attach 7c5dcf5d    open in this terminal
//	  claude logs 7c5dcf5d      show recent output
//	  claude stop 7c5dcf5d      stop this session
//
// The first line names the id between two " · " separators; the name
// segment at the end is absent without --name, and a "Starting background
// service" line can sit above the block. The attach hint names the id a
// second time, so it serves as the second anchor when the first line
// drifts. A candidate counts only when a pane command can quote it as one
// word. An output that holds no anchor answers "", and the caller falls
// back to the session name (issue #208).
func parseSessionID(output string) string {
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Split(strings.TrimSpace(line), " · ")
		if len(fields) >= 2 && fields[0] == "backgrounded" && paneWord(fields[1]) {
			return fields[1]
		}
	}
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[0] == "claude" && fields[1] == "attach" && paneWord(fields[2]) {
			return fields[2]
		}
	}
	return ""
}

// paneWord reports whether word can stand as the one quoted argument of the
// pane command in every shell that tmux may run it through (see
// legViewCommand): no whitespace, no single quote, no backslash, and a
// length that no wrapped line reaches.
func paneWord(word string) bool {
	return word != "" && !strings.ContainsAny(word, "'\\ \t") && len(word) <= 100
}

func argsHasPermissionMode(claudeArgs []string) bool {
	for _, arg := range claudeArgs {
		if arg == "--permission-mode" {
			return true
		}
	}
	return false
}

// createProject asks at the terminal how a missing project directory comes
// to be: a git URL clones into main/ (the layout `project convert` makes),
// y starts an empty repo, and anything else stops.
func createProject(dir string, stderr io.Writer) *toolError {
	answer := ask(stderr, "create project %s? [git URL to clone/y/N] ", dir)
	switch strings.ToLower(answer) {
	case "y", "yes":
		mainDir := filepath.Join(dir, "main")
		if err := os.MkdirAll(mainDir, 0o755); err != nil {
			return wrapGeneral(err)
		}
		for _, args := range [][]string{
			{"init", "--quiet", "--initial-branch", "main"},
			// worktrees branch from a commit, so start with an empty one
			{"commit", "--quiet", "--allow-empty", "--message", "initial commit"},
		} {
			cmd := exec.Command("git", args...)
			cmd.Dir = mainDir
			if out, err := cmd.CombinedOutput(); err != nil {
				return wrapGeneral(fmt.Errorf("git %v: %v: %s", args, err, out))
			}
		}
		return nil
	case "", "n", "no":
		return errNotFound("no project %s", dir)
	}
	mainDir := filepath.Join(dir, "main")
	cmd := exec.Command("git", "clone", answer, mainDir)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		// a failed clone removes main/, but can leave the empty project
		// directory behind
		_ = os.Remove(dir)
		return wrapGeneral(err)
	}
	return nil
}

// ask reads one answer line from the terminal. A non-interactive caller
// gets an empty answer, which every question treats as no.
func ask(stderr io.Writer, format string, args ...any) string {
	fmt.Fprintf(stderr, "project: "+format, args...)
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return ""
	}
	return strings.TrimSpace(line)
}

// direnvStatusAllowed is the check of the fish implementation: direnv
// status, run in dir, must say that the RC there is allowed.
func direnvStatusAllowed(dir string) bool {
	cmd := exec.Command("direnv", "status")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "Found RC allowed 0")
}

func filesEqual(a, b string) bool {
	rawA, errA := os.ReadFile(a)
	rawB, errB := os.ReadFile(b)
	return errA == nil && errB == nil && string(rawA) == string(rawB)
}

// warn records a non-fatal diagnostic and prints it at once for the
// plain-text paths.
func warn(result *sessionResult, code, format string, args ...any) {
	message := fmt.Sprintf(format, args...)
	if result != nil {
		result.warnings = append(result.warnings, spec.Warning{Code: code, Message: message})
	}
}

// asToolError passes a toolError through and classifies anything else as a
// general failure.
func asToolError(err error) *toolError {
	if toolErr, ok := err.(*toolError); ok {
		return toolErr
	}
	return wrapGeneral(err)
}
