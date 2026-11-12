# project

Project binary and ide window: the git workflow of one project directory.

## What Is the Topic?

One project binary owns the git workflow. A project directory holds `main/`, a clone, and one git worktree per branch beside it. No state lives inside a clone, and no path is hardcoded. No second workflow tool is added while this binary answers.

Commands sit in three groups (modules/programs/cli/project/help.go:44-47):

1. Worktrees and sessions: `open`, `add`, `spawn`, `list`, `close`, `discard`, `clean`, `convert`.
2. Ask and tell: `ask`, `lmk`, `btw`.
3. Ide windows: `ide` with `close` and `reload`, `ide-layout`, `ide-open`, `ide-edit`, `ide-tab`, `ide-view`, `ide-pop`, `ide-follow`, `wezterm-attach`.

## How Is the Topic Realized?

Worktrees and sessions:

1. `open` opens main/ or the worktree of a branch in an ide window. It makes the worktree when needed: an existing branch is checked out, a remote-only branch is tracked, and a new branch starts from the default branch (help.go:57-78).
2. Machine-facing subcommands `add`, `spawn --headless`, and `list` print one JSON envelope on stdout, and they share one exit-code table with the interactive subcommands: 0 success, 1 general error, 2 argument error, 5 not found, 7 permission denied, 12 unavailable, and 11 reserved for a rate limit (the exit-code table of the Go module). Dispatcher reads the envelope and the code (modules/services/dispatcher/README.md:127-130).
3. Two commands, `close` and `convert`, change the directory of the shell of the caller, which a child process cannot do. Each of them writes the target to the file that `PROJECT_CD_FILE` names, and the fish stub of project.nix reads it after the binary ends (modules/programs/cli/project.nix).
4. Settings bytes that start a session are a frozen contract, pinned by the tests and by the environment markers `PROJECT_SPAWN_SESSION` and `PROJECT_HEADLESS_SESSION` that the forge hook reads. They hold one PostToolUse hook that runs the follow of the ide window, so the editor pane follows the files that the session writes (issue 190; lua/genixis/ide.lua:58; cmd_ide.go:413-472).
5. `--from <base>` starts a branch at another base and records it as `branch.<branch>.projectBase`. Commands `close` and `clean` count a merge into that base as merged (help.go:67-68).
6. `--identity <name>` sets the git identity of the leg: agent by default, owner, or a profile of the machine-local `main/.claude/settings.local.json` (help.go:70; internal/identity/identity.go:10-109).
7. `spawn` starts a headless session in the worktree (cmd_session.go: spawnHeadless, L590-634). It runs `claude --bg` with the name `project: branch`, from the worktree, inside its direnv environment when the status allows it.
8. Machine contract of a spawned session: `claude --bg` prints the id of the session on its way out, and that id is the one handle that attaches and stops exactly this session. Both output streams land in one buffer, and the whole output reaches stderr after the run (cmd_session.go:610-622; issue 208).
9. A view window opens in the tmux session of the project after the session starts, and a failure there never costs the leg (cmd_session.go:629-632).
10. Before `spawn` and `ide open`, the tool reads the memory headroom of the host and refuses under two GiB, with exit code 12 (modules/programs/cli/project/memorygate.go:29-40). This gate is the fourth resilience layer of the host services; docs/host-resilience.md holds the layers.
11. `open <user>@<host>:<dir>` runs on a remote host over ssh, and a tab of the local window attaches (help.go:76).

Include lists (modules/programs/cli/project/includes.go):

1. Two optional files list the untracked files of main/ that a new worktree needs: `main/.worktreeinclude`, committed and shared by every clone, and `<project dir>/.projectinclude`, the entries of one machine (includes.go:11-18). Both are always read from main/, never from the branch of a worktree.
2. Lines use gitignore syntax, and the matching runs through the exclude machinery of git itself (includes.go:36-41).
3. A leading `@` makes a symlink instead of a copy, and a leading `~` makes a copy that close discards without a comparison (includes.go:19-21).
4. A copy is copy-on-write where the file system supports it (includes.go:110-144).
5. This repository commits no `.worktreeinclude` today.

Ide window:

1. `open` builds the window: nvim over a shell in one column, with the file tree in a left split of nvim, and claude in the other column (help.go:65). Its builder is ideBuild (cmd_ide.go:78-257).
2. `ask` sends one question to the claude pane of the window whose working tree is the current checkout. Text goes in through the tmux buffer as a bracketed paste, and an Enter submits it (help.go:227).
3. One editor pane follows the session: `ide-follow` reads the tool payload and points the pane at the touched file (cmd_ide.go:413-472), and the nvim side holds the rules (lua/genixis/ide.lua).
4. `wezterm-attach` attaches the window of a remote login through the socket forward. An environment of the forward names HOME and USER only when the socket path sits in the home directory of the user of the GUI (wezterm.go:202-235; issue 160).

Build:

1. lib/project-package.nix builds the binary with buildGoModule and adds the symlinked entry points `ide-edit`, `ide-layout`, `ide-open`, `ide-tab`, `ide-view`, and `wezterm-attach` (lib/project-package.nix:15-32).
2. A check phase fails on an unformatted file and runs the go tests, which drive real git repositories (lib/project-package.nix:21, 36-43).
3. One flake check builds this package on both systems, so every gate run tests the tool (flake.nix:369-380).

## Why Is the Topic That Way?

Workflow Law of this topic, at its application (docs/design.md holds the map):

1. One project binary owns the git workflow. No second workflow tool is added while it answers.
2. No state lives inside a clone, and no path is hardcoded.
3. Branch namespaces name the worker: `ai/` for a dispatcher leg, `review/` for an interactive agent session, `research/` for an investigation, and a plain name for the owner.
4. No force push, and no bypassed hook. A rejection at a gate or at the forge is a stop: the failure is reported, and it is not retried with other flags.
5. An area under review justifies its present lines before it gains new ones.
6. Merging belongs to the owner alone. No agent merges a pull request.
7. Each record carries the executor: the login, the commit trailers, and the branch namespace. A brief discloses which decisions the machine made.

Security Law of this topic, at its application:

8. A command that destroys work beyond recovery answers to a person at a terminal only. It lists the work that it will remove, and it asks for a fresh confirmation code that it reads from the terminal. Plain `git rm` stays allowlisted, because git recovers its removals. Force forms prompt through the deny rules. Known hole, kept as a note: a force flag written mid-command evades a prefix deny. Destructive paths of this binary are security spine: they stay human-authored with agent assist.

Decisions behind the tool:

9. An agent session never enters a worktree. A tool starts the session inside it (docs/decisions.md, record 8).
10. Session ids are the one handle of a session, because a re-looped leg needs a view window that attaches to exactly the right session (issue 208; cmd_session.go:610-614).
11. Include lists keep the exact gitignore meaning of the earlier fish implementation, because the tool must not reimplement gitignore (includes.go:36-41).
12. An environment of a socket forward names directories of the machine that runs the GUI, not of the remote host, and it omits HOME and USER when the socket path names no home (wezterm.go:202-227; issue 160).

Deferred with a trigger: jj as a backend, behind the backend interface, when its churn settles.

## What Does the Topic Enable?

Purpose of the topic: one command starts a checkout, a session, or a leg on any host, with the identity, the plan, and the base branch recorded, so the forge and the owner see the same state. Workflow Law in the Why section of this file states the criteria.

## How Does a Reader Use and Change the Topic?

A person runs `project` at a terminal; fish functions of docs/cli.md wrap the frequent paths. An agent session follows the project skill. In the factory loop, `spawn --headless` runs with a permission mode, and the dispatcher owns that path (docs/services.md).

Change the tool:

1. Write the change under modules/programs/cli/project/, with the help text in help.go.
2. Cover it with the go tests, which the flake check runs (lib/project-package.nix:36-43).
3. Run `nix fmt`, then `nix flake check --impure`.

Add an included file of main/ to the worktrees: list it in `main/.worktreeinclude`, with `@` for a shared symlink or `~` for a regenerated copy.
