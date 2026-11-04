---
name: project
description: Use when you create, open, or remove a git worktree or feature branch in a project directory (a directory with a `main/` clone and sibling worktrees), when a branch must start from a trunk or integration branch, or when you act as an orchestrator that runs one agent for each feature branch. Covers the `project` command.
---

# The `project` command

A project directory `<dir>` holds `main/` (an ordinary clone) and one git worktree for each branch, beside `main/`.
The include lists name untracked files that every new worktree needs. Only `project` copies or links them. A worktree
that you make with `git worktree add` lacks them, and the build fails.

## Include lists

Two files list untracked files in `main/` for new worktrees. `project` uses the entries of both files. Each file is
optional.

- `main/.worktreeinclude` is in the repo and can be committed. `project` always reads it from `main/`, not from the
  branch of the worktree. A change to it in a branch takes effect after the branch merges and `main/` pulls it.
- `<dir>/.projectinclude` is outside every repo and is never committed. It holds the entries of one machine only.

Each line is a gitignore pattern (`#` starts a comment). A leading `/` anchors the pattern to the root of the repo. A
prefix before the pattern sets what happens:

| Prefix | New worktree | `project close` |
| --- | --- | --- |
| none | Copy of the file | Refuses while the copy differs from `main/`. Removes it otherwise. |
| `@` | Symlink to the file in `main/` | Removes the link. Use it for read-only inputs that builds never write. |
| `~` | Copy of the file | Discards it with no comparison. Use it for files that a build regenerates. |

Git ignores these files, so it cannot see work in them. A project can set `git config project.closeCheck <command>` in
`main/`. `close` runs it in the worktree before it discards anything. A non-zero exit status refuses the close.

## Commands

Run these from any checkout of the project, or pass `<dir>`. A `<dir>` that is a bare name (no `/` or `~`) means
`~/projects/<dir>`. Use `./<dir>` for a path relative to the current directory.

The machine-facing commands `add`, `spawn --headless`, and `list` print one JSON envelope on stdout and exit with
codes from the exit-code table of the tool: 0 success, 1 general error, 2 argument error, 5 not found, 7 permission
denied, 12 unavailable. The interactive commands stay plain text and use the same codes. Parse the envelope, not
the text: `ok`, `data`, `error.code`, `warnings`, and `meta.exit_code` are always present.

| Command | Action |
| --- | --- |
| `project add <dir> <branch> [--from <base>] [--as <name>] [--identity <name>]` | Makes the worktree. Prints one JSON envelope whose `data` holds the `branch` and the `worktree` path. Opens no window. **Use this in scripts and as an agent.** |
| `project list [dir]` | Prints the frontier of the project as one JSON envelope: each branch, its worktree (its claim), its merge state, and the dirty state of each worktree. |
| `project open [dir] [branch] [--from <base>] [--as <name>] [--plan <name>] [--identity <name>]` | Does the same, then opens a tmux `ide` window. For the user, not for agents. |
| `project spawn <dir> <branch> [--from <base>] [--as <name>] [--plan <name>] [--identity <name>] [--headless] [--permission-mode <mode>] <prompt...>` | Makes the worktree like `add`, then starts a Claude session there with the prompt. The session runs in a new `ide` window in the tmux session of the project, which is one tab of the host WezTerm window (one window per host, one tab per session), where the user can watch it and answer its permission prompts. The command fails when the worktree already has an `ide` window. With `--headless`, the session runs in the background with no window, and the command prints one JSON envelope with the `session` name and the `worktree` path. Use `claude agents`, `claude attach <name>`, `claude logs <name>` and `claude stop <id>` to manage a background session. A background session waits at any other permission prompt. The forge hook denies a forge command that it would ask about, so a headless session reports on its entity and stops. See the `forgejo` skill. |
| `project close [worktree]` | Removes the worktree. Deletes the branch if it is merged. A `[worktree]` that is a bare name (no `/` or `~`) is the worktree `<project>/<worktree>`. This is true in `main/`, in any worktree, and in the project directory. Use `./<worktree>` for a path relative to the current directory. |
| `project clean [dir] [--dry-run] [--gone]` | Fetches, fast-forwards the branch of `main/`, closes every merged worktree, and deletes merged local branches. Run it after pull requests merge. `--gone` also cleans squash-merged branches whose remote branch is deleted. |

- `--from <base>` starts a new branch from `<base>`. Without it, the branch starts from the branch of the worktree
  that you run the command in. Outside a worktree, it starts from main.
- `<base>` is recorded as `branch.<branch>.projectBase`. `project close` counts a merge into `<base>` as merged.
- `--as <name>` sets the directory name. The default is the branch name with `/` changed to `-`. The name cannot
  contain `/`.
- A branch that already has a worktree opens that worktree. It does not make a second one.
- `project close` changes nothing and refuses while the worktree has uncommitted work. It keeps a branch that is not merged into main or
  `<base>`, and then exits with status 0. A squash-merged branch always stays. Delete it with `git branch -D` when the pull request is merged, or use `project clean --gone`.
- `project discard [worktree]` is for the user only. It closes a worktree and throws away its uncommitted work. It
  refuses inside Claude Code and without a terminal. Never run it, and never try to get around its checks. When a
  worktree has work that blocks `project close`, stop and tell the user.
- `project add` and `project close` ask no question. `project open` can ask to create a missing project.

## Branch namespaces

The first path segment of a branch names who works it. Pick the namespace before you name a branch:

| Prefix | Who | Use |
| --- | --- | --- |
| `ai/` | a dispatcher worker | the dispatcher makes these legs for issues |
| `review/` | an interactive agent session | an agent that reviews or pairs in a window |
| `research/` | an investigation | a research leg with notes in `.scratch/` |
| none | the owner | never take a plain name for agent work |

An agent session that starts a branch uses `ai/<issue>`, `review/<pr>`, or `research/<topic>`. The `AGENTS.md` of the
project can give its own table; it takes priority.

## Over ssh

The `dir` argument of `project open` and `project spawn` can carry an scp-style prefix:
`project open dev@services:genixis` runs on `services` as `dev`, and a local tab attaches to the tmux
session there, in the WezTerm window titled `services`. The user part is required. The remote form needs an existing project, and it never creates or
converts one. `add`, `close`, `clean`, and `discard` do not delegate. A delegated `spawn` carries the plan of the
session that runs it as an explicit `--plan`, which must exist on the remote host. A delegated `open` also
restarts the claude pane of an open window under the requested plan (see "Plans"). Claude memory and plans stay
per host.

## Work in a worktree

To start work in a new worktree, run `project spawn` (see "Orchestrator"). The command starts a new session in the
worktree, and that session does the work.

A session that `project spawn` started must run one plain command in each shell call, like any other session. In that
session, the forge hook denies a compound command. See the `forgejo` skill.

Never enter a worktree with the worktree tool of your agent. Never use `cd` or `git -C` to reach a worktree. In Claude
Code, never call `EnterWorktree` or `ExitWorktree`.

Use `project add` only to make a worktree without a session, for example in a script, or as the step before a
`project spawn`.

## Scratch directory

Every worktree has a directory `.scratch/` at its root. The global git ignore file of this machine lists the name, so
no commit sees the directory. Use it for files that no commit must see: a body file for `tea` with
`--description-file <path>`, the output of a test, or a throwaway script.

Two limits apply:

1. The directory goes away with the worktree. `project close` removes it. Copy a file out of `.scratch/` when you must
   keep it.
2. A test that runs git in a nested repository must not use `.scratch/`. When `git init` fails partway, the commands
   that follow act on the worktree itself. Make the directory outside the worktree instead, for example with
   `mktemp -d`.

## Stacked branches

A long-lived trunk branch (for example a UI redesign) can have feature branches:

```fish
project add . ui/trunk
project add . ui/nav --from ui/trunk --as ui-nav
```

Git cannot keep a branch `a/b` together with `a/b/c`. Give the trunk a last segment that no branch uses as a
prefix, for example `ui/trunk` and `ui/nav`.

Merge a feature branch into its parent with `git merge --no-ff`. Then `project close` deletes the feature branch.

The forge hook denies a push to a trunk branch, for example `ui/trunk`. A parent branch that is not a trunk branch,
for example a composition branch, is only a `projectBase`. A push to it stops at a permission prompt.

## Orchestrator

An orchestrator is the agent that works in a parent branch, for example a composition branch. It makes one worktree
for each child branch with `project add . <child> --from <parent> --as <name>`. It starts one agent in each worktree, with `project spawn <dir> <child> --from <parent> --as <name> "<task>"`.
Two agents never share a worktree. After it merges a child, it runs `project close <name>` in the worktree of the parent branch. At the end of a batch, `project clean --dry-run` shows what is left to remove.

If the project has its own rules for branch and directory names, follow them. Read the `AGENTS.md` of the project.

Rules for `project spawn`:

- Always pass `--from`. Without it, the branch starts from the branch of the current worktree or of `main/`. Both can
  be the wrong parent.
- Do not pass `--headless`, unless the user says so for that run. The user watches each agent in its window.
- Pass `--permission-mode acceptEdits`. Pass `bypassPermissions` only when the user says so for that run.
- The prompt must make sense without the conversation of the orchestrator. It names the task, the branch, and the
  point at which the agent stops. For example: "Implement #58 on this branch. Stop after you push the branch and
  comment on the issue."
- The prompt names every path that the agent needs, for example `.scratch/` for a body file. An agent without a path
  searches for it, and a search outside the working directory stops at a permission prompt.
- The prompt repeats the rules of "Commands" in `~/.claude/CLAUDE.md`: change files with the supplied file tools,
  not the shell, and run one plain command in each shell call. Each permission prompt stops the agent until the user
  answers it.

## Plans

`--plan <name>` starts the session of `project open` or `project spawn` against another Anthropic-compatible
endpoint, for example `--plan zai`. A session without a plan uses the login of Claude Code. A `project spawn`
without `--plan` uses the plan of the session that runs the spawn.

- The plans are the files `~/.config/project/plans/<name>.json`. If the plan does not exist, the command stops and
  lists the plans that exist.
- If the plan cannot read its token file, the command stops. The token file is an agenix secret.
- With a plan, the prompts and the code go to the third party that runs the endpoint. The children of a session
  under a plan go to that third party too, because they inherit the plan.
- `--plan none` starts the session without a plan. Pass it when the children of a session under a plan must not
  go to the endpoint of that plan.
- `project add` starts no session, so it takes no `--plan`.
- If the `ide` window of the checkout is already open, `project open` selects it. When the plan of the window is not
  the requested plan, `project open` restarts the claude pane under the requested settings. The restarted claude
  continues the conversation with `--continue`. The old claude process ends. Work that waits at a prompt is lost.
- When no settings name a plan, `claude --resume` and `claude --continue` send the session to the login of Claude
  Code. The settings on the command line do apply. `claude --continue --settings <settings of a plan>` continues the
  session under that plan. To resume a session of a plan, start a new session with the same `--plan`. Then resume
  the old session inside it with `/resume`.
- All plans share the memory of the project (`<dir>/.claude/memory`). A model reads the notes that a model of another
  plan wrote.

## Git metadata

A session that `project open` or `project spawn` starts in a worktree can read these paths without a prompt:

- `<dir>/main/.git/worktrees/<name>/`, the git metadata of its own worktree.
- Each entry of `<dir>/main/.git` that existed when the session started, except `worktrees/`.
- The list of `<dir>/main/.git`, with the exact command `ls <dir>/main/.git`.

The session cannot edit a path in `<dir>/main/.git`. Do not read the metadata of another worktree.

## Identity

A worktree that `project add`, `open`, or `spawn` makes or opens carries the identity of the leg as
per-worktree git config: `user.name`, `user.email`, and `core.sshCommand`. Git applies it to every
process in the worktree. Commit and push from the worktree as usual. Do not check that a settings
file exists first. Do not set `GIT_SSH_COMMAND`, `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`,
`GIT_COMMITTER_NAME`, or `GIT_COMMITTER_EMAIL` yourself.

The `--identity` flag of the command names the identity of the leg. The default is `agent`: the
values come from the `env` block of `main/.claude/settings.local.json` (`GIT_SSH_COMMAND` and the
author and committer name and email). `owner` uses the global git config of the user and clears the
ssh override, so an owner leg commits and pushes as the person. A profile that the same file lists
under `project.identity.<name>` is also valid. An unknown name stops the command.

When the file or these keys are missing, the worktree has no identity of its own, and git uses the
config of the repository and of the user.

Git applies the identity to every process in the worktree. This includes a person at a terminal. A
worktree that already exists gets the identity of the leg the next time `project add`, `open`, or
`spawn` names its branch. `main/` always keeps the identity of the person.

## Environment

A new worktree gets `direnv allow` automatically only when its `.envrc` equals the `.envrc` of `main/`. Otherwise run
`direnv allow` by hand in the worktree. Until then, the tools of the environment can be missing. Report that
`direnv allow` is needed. Do not use `direnv exec`, because a deny rule blocks it.
