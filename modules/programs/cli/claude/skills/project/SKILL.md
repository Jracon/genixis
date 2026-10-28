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

| Command | Action |
| --- | --- |
| `project add <dir> <branch> [--from <base>] [--as <name>]` | Makes the worktree. Prints its path. Opens no window. **Use this in scripts and as an agent.** |
| `project open [dir] [branch] [--from <base>] [--as <name>]` | Does the same, then opens a tmux `ide` window. For the user, not for agents. |
| `project spawn <dir> <branch> [--from <base>] [--as <name>] [--headless] [--permission-mode <mode>] <prompt...>` | Makes the worktree like `add`, then starts a Claude session there with the prompt. The session runs in a new `ide` window in the tmux session of the project, which shows all its worktrees in one WezTerm window, where the user can watch it and answer its permission prompts. The command fails when the worktree already has an `ide` window. With `--headless`, the session runs in the background with no window. Use `claude agents`, `claude attach <name>`, `claude logs <name>` and `claude stop <id>` to manage a background session. A background session waits at any permission prompt. |
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

## Enter a worktree

When you do the task yourself, use `project add` and enter the worktree. When you give the task to a different agent,
use `project spawn` (see "Orchestrator").

After `project add` makes a worktree, move the session into it with the worktree tool of your agent. Do not use `cd`
or `git -C` to reach the worktree.

In Claude Code:

1. If the session is already in a worktree, call `ExitWorktree` with `action: "keep"` first. `EnterWorktree` with
   `path` refuses a project worktree while the session is in a different worktree. It accepts only a worktree under
   `.claude/worktrees/` in that case.
2. Call `EnterWorktree` with `path` set to the path that `project add` prints. All later commands run in the
   worktree.
3. Do not call `EnterWorktree` with `name`. That call makes a worktree under `.claude/worktrees/`, outside the
   project layout.
4. To go back, call `ExitWorktree` with `action: "keep"`. The worktree stays on disk.

## Stacked branches

A long-lived trunk branch (for example a UI redesign) can have feature branches:

```fish
project add . ui/trunk
project add . ui/nav --from ui/trunk --as ui-nav
```

Git cannot keep a branch `a/b` together with `a/b/c`. Give the trunk a last segment that no branch uses as a
prefix, for example `ui/trunk` and `ui/nav`.

Merge a feature branch into its parent with `git merge --no-ff`. Then `project close` deletes the feature branch.

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
- The prompt repeats the rules of "Commands" in `~/.claude/CLAUDE.md`: change files with the supplied file tools,
  not the shell, and run one plain command in each shell call. Each permission prompt stops the agent until the user
  answers it.

## Git metadata

A session that `project open` or `project spawn` starts in a worktree can read these paths without a prompt:

- `<dir>/main/.git/worktrees/<name>/`, the git metadata of its own worktree.
- Each entry of `<dir>/main/.git` that existed when the session started, except `worktrees/`.
- The list of `<dir>/main/.git`, with the exact command `ls <dir>/main/.git`.

The session cannot edit a path in `<dir>/main/.git`. Do not read the metadata of another worktree.

## Environment

A new worktree gets `direnv allow` automatically only when its `.envrc` equals the `.envrc` of `main/`. Otherwise run
`direnv allow` by hand in the worktree. Use `direnv exec <worktree> <command>` until then.
