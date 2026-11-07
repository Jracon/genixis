# The project binary and the ide window

The manual of the `project` command, its worktrees and plans, and the `ide` window layout.

## Projects (`project`)

`project` is one Go binary (issue #74, phase 3), built from `modules/programs/cli/project/` through `lib/project-package.nix`. The ide window builder and its pane scripts (`ide`, `ide-layout`, `ide-open`, `ide-edit`, `ide-tab`, `ide-view`, `wezterm-attach`) are part of the same binary, behind the same command names (see IDE layout).

The fish side of `project.nix` is only a cd stub. `close` and `convert` change the directory of the caller's shell, which a child process cannot do. For this reason, the binary writes the target to the file named by `PROJECT_CD_FILE`. The stub reads it after the binary ends. A completion file forwards the command line to `project __complete`.

The machine-facing subcommands (`add`, `spawn --headless`, `list`) print one JSON envelope on stdout. They exit with codes from the exit-code table vendored in the Go module (0 success, 1 general error, 2 argument error, 5 not found, 7 permission denied, 12 unavailable). The code 11 (rate-limited) is reserved. The interactive subcommands stay plain text and use the same codes.

The `--settings` bytes that start a session are a frozen contract. The tests of the Go module pin them. The markers `PROJECT_SPAWN_SESSION` and `PROJECT_HEADLESS_SESSION`, which the forge hook reads, pin them too.

**Branch namespaces.** The first path segment of a branch names who works it:

| Prefix | Who | Set by |
| --- | --- | --- |
| `ai/` | a dispatcher worker session | phase 4 of #74 |
| `review/` | an interactive agent session | the agent that opens it |
| `research/` | an investigation | the agent that opens it |
| none | the owner | the owner |

**Layout.** A project directory holds `main/` (an ordinary clone on the default branch) and one git worktree for each branch, next to `main/`, at `<dir>/<branch>`. Each `/` in the branch name becomes `-`. Nothing lives inside a repository. No path is hardcoded. A path `<dir>` resolves from the current directory. A bare name resolves under `~/projects`.

**`project open [dir] [branch] [--from <base>] [--as <name>] [--plan <name>] [--identity <name>]`**

- A `<dir>` without `/` or `~` (and not `.` or `..`) is a name. It resolves to `~/projects/<dir>` from any directory. Write `./<dir>` for a directory relative to the current one.
- With no branch, it opens `main/` in an `ide` window named `main`.
- With a branch, it opens that worktree in an `ide` window named `<branch>`, and creates the worktree first when needed.
- Inside tmux, the command builds a detached window (the `ide --detach <dir>` path) when the current tmux session is not the one of the project. The project then gets its own tmux session, which is one tab of the host window (see IDE layout). In the session of the project, the window is a tab of that session.
  - The session of the project is the session with the name of the project. A session that already has an `ide` window of a checkout of the project is also the session of the project.
  - If the `ide` window of that checkout is already open in the current session, the command selects it.
  - If the `ide` window of that checkout is already open in another session, the command selects it. It never switches your tmux client away from the current session, unless `SSH_CONNECTION` is set and no socket forward answers. When a terminal already shows that session, the command only tells you its name. Otherwise, it opens a tab for that session in the host window.
  - When `SSH_CONNECTION` is set and no socket forward answers, no WezTerm window can open. So the command switches your tmux client to the window. Behind the forward of a window of a remote login, the command opens a tab of that window instead, and the tmux client of the caller does not switch (see The host window).
- Outside tmux, the command opens the session of the project as a tab of the host window, one tab per session. It no longer runs `ide --session <dir>` in your terminal. In the shell of a tab that holds a socket forward, the command opens the tab in the window of its login (see The host window). Over a plain ssh login, or on a machine without WezTerm, the session still takes over the current terminal, the way `ide --session` does.
  - If the `ide` window of that checkout is already open in another session, the command selects the tab of that session. A session that another client already shows gets no second tab. The command then only prints the name of the session.
- Opening `main/` or an existing worktree starts a silent background `git pull --ff-only` there.
- To create a worktree:
  - An existing local branch is checked out.
  - A remote-only branch is tracked.
  - The default branch is `project.defaultBranch` in the git config of `main/`. If that is not set, it is the branch that `origin/HEAD` names, when that branch exists. Otherwise it is the branch that `main/` has checked out. The command warns when `main/` is on another branch, and it branches from the default branch.
  - A new branch comes from `origin/<default>` with `--no-track`, after a `git fetch` with a 10-second limit. The fetch makes the new branch include PRs merged since main was last pulled. When the fetch fails, `open` and `add` warn and branch from local main. `spawn` refuses a new branch from the default branch instead, with exit code 12 (unavailable): a leg must not start on a base that may be older than origin main. A branch that already exists and a `--from` base keep the fallback: one continues its own work, and the other is the choice of the caller.
  - `--from <base>` makes a new branch start from `<base>` instead of main. Use it for a feature branch of a long-lived trunk branch. A local `<base>` has priority over `origin/<base>`. The command records `<base>` as `branch.<branch>.projectBase` in the git config. The option has no effect on an existing branch.
  - Without `--from`, the command run inside a worktree starts the new branch from the branch of that worktree. It records that branch as `projectBase`, and it prints one line to say so. Inside `main/` or outside the project, the base is main.
  - `--as <name>` sets the directory name of a new worktree, instead of the branch name with `-` for `/`. The name cannot contain `/`. A branch that already has a worktree always opens that worktree, whatever its directory name.
  - When the `.envrc` of a new worktree is identical to the `.envrc` of `main/`, and `main/` is allowed in direnv, the command runs `direnv allow` in the worktree. A branch that changes `.envrc` still needs a manual `direnv allow`.
  - Name a trunk branch so that no branch name is a prefix of another at a `/`. Git refuses `ui` together with `ui/nav`. Use `ui/trunk` and `ui/nav`.
- If `<dir>` does not exist, the command asks before it creates the project. The answer selects how it creates `main/`:
  - A git URL clones the repo into `main/`. This gives the layout that `project convert` makes. If the clone fails, the command removes the empty `<dir>`.
  - `y` makes `main/` with `git init` and an empty first commit. Worktrees need that commit.
  - An empty answer, `n`, or `no` stops the command, and it changes nothing.
- For a plain repo, the command offers `project convert`. The answer `never` records `project.convert = false` in the local git config of the repo and stops the questions. A repo left plain opens as it is, without branches.

**`project add <dir> <branch> [--from <base>] [--as <name>] [--identity <name>]`**

- It does what `project open` does to make the worktree, with the same include lists and `direnv` check. It does not open an `ide` window and does not pull. It prints one JSON envelope whose `data` holds the `branch` and the `worktree` path, so a script or an orchestrator parses stdout. A repeated `add` for the same branch reports the same worktree: the claim is idempotent.
- Scripts and agents use it, for example an orchestrator that makes a worktree for each feature branch. It never asks a question when `<dir>` is already a project.
- An agent does not enter the worktree. It starts work there with `project spawn`.

**`project list [dir]`**

- Machine-facing. It prints the frontier of the project as one JSON envelope: the default branch, every branch with its worktree (its claim) and its merge state, and every worktree with its dirty state. An orchestrator reads it to see which work is in flight and which branches the merge slot accepts.

**`project review [<dir>] <n>`**

- It opens pull request `<n>` for review. It fetches `refs/pull/<n>/head` from origin, makes the branch `review/pr-<n>` at that head, makes or reuses the worktree of that branch, and opens the worktree in an `ide` window under `--identity owner`, so a commit made there carries the owner.
- Every run moves the branch to the current head of the pull request while the worktree is clean, so a review never reads a stale revision. A worktree with uncommitted work keeps its state, and the run prints why the branch stayed.
- The command owns the `review/pr-<n>` namespace alone. `project close` ends a review. It deletes the branch only when the pull request merged, so an open pull request keeps its review worktree for the next run.
- The fetch must succeed. When origin does not answer, the command fails with exit code 12 (unavailable), and the run is retried.
- The diff flow of a review worktree lives in nvim, under the `<leader>v` keys of `neovim/lua/genixis/review.lua` (see docs/keymap.md): the quickfix of the files that differ from the base branch, one file beside its base version, and the branch in a tmux popup through lazygit (delta renders its diffs), hunk, and tuicr. The base is the `projectBase` of the branch when the git config names one, else the branch that `origin/HEAD` names.

**`project board [<dir>]`**

- It prints one board that joins two reads: the frontier of `project list` and the open issues and the open pull requests of the forge. It reads the forge through tea list calls with JSON output; the token stays with tea, and the board writes nothing to the forge.
- Two keys carry the join: the head branch of a pull request names the branch of a worktree, and the body of a pull request holds a closing keyword for each issue it solves. A row names the pull request of an issue, the worktree of its head branch with the dirty state, and the review worktree of the pull request, when each exists.
- An open pull request that no open issue row carries gets its own row. A branch of the frontier that no open pull request carries gets its own row; the review branch of an open pull request rides on the row of that pull request instead.
- Inside tmux, the board opens in a popup that pages the text through less; `q` closes it. Outside tmux, it prints to stdout. When tea is missing or a list fails, the board prints a warning line and shows the rest.

**Include lists (`.worktreeinclude` and `.projectinclude`)**

- Two files list untracked files in `main/` to copy into new worktrees. The copy is copy-on-write where the file system supports it.
  - `main/.worktreeinclude` is in the repo. Commit it to share the list with every clone of the project.
  - `<dir>/.projectinclude` is outside every repo, so it is never committed. Use it for entries of one machine only.
- The command uses the entries of both files. Each file is optional.
- The command always reads `.worktreeinclude` from `main/`, not from the branch of the worktree. `project close` reads the same file that `project add` read, unless `main/` changed between the two commands. A change to `.worktreeinclude` in a branch takes effect after the branch merges and `main/` pulls it.
- Both files use gitignore syntax.
- Claude Code also reads `main/.worktreeinclude` when it makes its own worktrees. It does not know the `@` and `~` prefixes, so it copies only the entries without a prefix.
- A leading `@` makes a symlink instead of a copy.
- A leading `~` makes a copy that `project close` discards without a comparison. Use it for files that a build regenerates for each branch.

**`project close [worktree]`**

A `[worktree]` without `/` or `~` (and not `.` or `..`) is a name. It resolves to `<dir>/<worktree>` when the command runs in `main/`, in a worktree, or in `<dir>`. Write `./<worktree>` for a directory relative to the current one. `project discard` resolves its argument in the same way.

1. It refuses while `git status` shows uncommitted work. It ignores the links that `project` made from the include lists. Until this check passes, it changes nothing.
2. It refuses while a plain copy differs from `main/`.
3. It runs the veto command `project.closeCheck`, if the git config of `main/` sets one. The command runs in the worktree, with `PROJECT_MAIN` and `PROJECT_TREE` set. A non-zero exit status refuses the close. Git ignores the `~` files, so a project uses this to protect ignored files that hold work.
4. It removes the copies, discards the `~` files, and removes the links. It then makes every file in the worktree writable, because a build can leave read-only files that git cannot delete.
5. It runs `git worktree remove`.
6. It deletes the branch only if the branch is merged into the default branch or `origin/<default>`. When the branch has a `projectBase`, a merge into that base also counts. If the branch is not merged, it keeps the branch, prints a message, and exits with status 0.
7. It stops the background Claude sessions of the worktree and kills the `ide` window.

**`project discard [worktree]`**

- It does what `project close` does, but it removes uncommitted work, changed copies, and files that `project.closeCheck` protects. It keeps an unmerged branch, as `close` does.
- Only a person at a terminal can run it. It refuses when `CLAUDECODE` is set, and when stdin or stderr is not a terminal.
- Before it removes work, it lists that work. It then asks for a random six-digit code, which it reads from `/dev/tty`. A wrong code stops it, and it changes nothing.
- These checks stop an agent from removing work by accident. They cannot stop a process that sets out to get around them, because that process runs as the same user.
- The `project` skill tells agents to never run it.

**`project spawn <dir> <branch> [--from <base>] [--as <name>] [--plan <name>|none] [--identity <name>] [--headless] [--permission-mode <mode>] <prompt...>`**

- It makes the worktree like `project add`. It then starts a Claude Code session there. The words after the branch are the prompt, and the command needs one.
- When the fetch of a new branch fails, the command fails with exit code 12 and starts no leg. The base of a leg must be current. See the rule under `project open` above for the cases that keep the fallback.
- The session has the same memory settings as `project open`. `--permission-mode` sets its permission mode. The default mode is the one that your settings set.
- Without `--plan`, the session uses the plan of the session that runs the spawn. `--plan none` starts the session without a plan (see Plans).
- Without `--headless`, the command opens the worktree's window the way `ide --detach <dir>` does (see IDE layout). The claude pane of that window runs the session interactively.
  - The window goes into the tmux session named after the project. All worktrees of a project share that session. The session is one tab of the host window (see IDE layout). The tmux window of the caller does not change.
  - The window name is `<branch>`. The command prints it to stderr.
  - You can watch the agent and answer its permission prompts in the window.
  - The panes load the direnv environment of the worktree, as in `project open`.
  - The command fails when the worktree already has an `ide` window.
- With `--headless`, the command starts a background session with `claude --bg`. This form is machine-facing: it prints one JSON envelope whose `data` holds the `session` name and the `worktree` path, and exits per the exit-code table. The output of `claude` itself goes to stderr.
  - The session name is `<dir>: <branch>`.
  - The session runs inside the direnv environment of the worktree when the `.envrc` is allowed. If it is not allowed, the command warns and starts the session without the environment.
  - A background session cannot ask you for permission. Every other tool call that needs permission waits. The forge hook denies a forge command that it would ask about, so the session reports on its entity and stops. The command warns when `--permission-mode` is missing.
  - Each headless leg gets one view window in the tmux session named after the project, on the host of the spawn. The window name is `<branch>`. Its pane runs `claude attach` on the session, so you watch the leg work. You reach the window through the session of the project.
  - The view window goes to the tmux server that the spawn itself reaches. tmux puts its socket at `$TMUX_TMPDIR/tmux-$UID/default`, and at `/tmp/tmux-$UID/default` when the variable is empty. A login shell of the user exports `TMUX_TMPDIR`. A systemd user unit sources no profile, so the dispatcher units set the variable with `Environment="TMUX_TMPDIR=%t"`: `%t` is the runtime directory of the user (issue #143). Without it, a leg window lands on a second server, in a second session with the name of the project. No attach of the owner shows it.
  - The view window ends with the session. The attach client exits when the session stops, and tmux closes the pane and the window. The dispatcher release stops the session with `claude stop`, so the window ends with it.
  - The view window records the worktree path in `@leg_dir`. When the command cannot make the window, the leg starts anyway and the command prints a warning on stderr.
  - Manage the sessions with `claude agents`, `claude attach <name>`, `claude logs <name>`, and `claude stop <id>`.
- `project close` kills the `ide` window, which stops its session. It also stops the background sessions that started inside the worktree. It removes the view windows of the worktree, which read `@leg_dir`. It does all of this after it removes the worktree. It does not stop them while the worktree is still dirty, because the removal then fails first.

**Delegation over ssh (`user@host:dir`).** The `dir` argument of `project open` and `project spawn` can carry an scp-style prefix. `project open dev@services:genixis` runs the command on `services` as `dev` over ssh. The local machine then opens a tab that runs `ssh -t` and attaches to the tmux session of the project on the remote host. The tab goes into the WezTerm window of the remote host (see IDE layout).

- The user part is required. A prefix without it stops with an error. The reason: the `Host` block of a short name can default to another user, `root` on the servers. No ssh alias replaces the user part.
- Only `open` and `spawn` delegate. `add`, `close`, `clean`, and `discard` do not delegate. `discard` never will, because its terminal checks are the guard against an agent that destroys work.
- The remote form needs an existing project. A missing project or a plain repo stops with an error. The reason: the questions of a local run have no terminal to answer them over ssh. Create or convert the project with a manual ssh first.
- The `dir` after the colon names the project directory, not a checkout inside it. The local half computes the name of the tmux session from that directory name.
- Both machines must run a build that knows the prefix. The remote half of an older build ends in an attach that has no terminal, and the ssh call fails.
- The arguments travel base64-encoded in one variable, joined with `string join0`. ssh joins a command line with spaces, and the remote shell would re-parse it. That re-parse breaks a prompt that holds spaces.
- The remote runs the command through a login shell. A tmux server that a first delegated call starts then has a full environment for its hooks.
- The remote call never attaches. It makes or finds the `ide` window through `ide --detach`, and it prints the name of the tmux session. A rerun after a connection drop finds the open window and keeps it. When the plan of the window is not the requested plan, the remote restarts the claude pane under the requested settings (see Plans). The local half then opens the attach tab, and it selects the tab that is already open.
- The remote half prints no `tmux attach` command. The local half opens the attach tab, so the person needs no command. A run without the prefix, in an ssh login on the remote host, still prints the command when no terminal shows the session.
- The attach tab goes into the WezTerm window titled with `user@host`, so it stays distinct from the window of a local project with the same name. A rerun selects the tab that is already open. The reason: two clients on one tmux session mirror the current window of each other. The ssh of the attach tab carries the socket forward (see The host window). A detach leaves the tab open (issue #142). After the attach ends, the command of the tab runs a login shell on the remote host. That shell joins no session. The tab ends when that shell exits.
- A host that takes delegated sessions installs the wezterm package, for its cli. Through the socket forward, `project open` on that host opens tabs in the window of the login. `common/wezterm-cli.nix` installs the package, and `devServerConfiguration` loads the file, so `services` has the cli.
- With `--headless`, the remote starts the background session and makes its view window there. The local half opens no tab.
- A delegated `spawn` without `--plan` carries the plan of the session that ran it as an explicit `--plan`. The plan and its token must also exist on the remote host.
- The Claude memory of a project and the plan files stay per host. Notes that one host writes do not reach the other.

**The marker of a spawned session.** `project spawn` sets the environment variable `PROJECT_SPAWN_SESSION=1` for the session, through the `env` of its `--settings`. The variable then sits in the environment of the session and of every command that the session runs. The forge hook reads it (see docs/forge-hook.md). A headless spawn sets a second variable, `PROJECT_HEADLESS_SESSION=1`, beside it. The forge hook then denies a forge command that it would ask about, so the session reports on its entity and stops. A windowed spawn keeps its prompts, because a person can answer them.

**Plans (`--plan <name>`).** A plan starts the Claude Code session of `project open` or `project spawn` against another Anthropic-compatible endpoint. A session without a plan uses the login of Claude Code. A `project spawn` without `--plan` uses the plan of the session that runs the spawn.

- `genixis.claude.plans` in `claude.nix` writes each plan to `~/.config/project/plans/<name>.json`. The file holds the `env` of the plan and the path of its token file. It does not hold the token.
- The command merges the `env` into the `--settings` JSON. It also sets `apiKeyHelper` to `cat <token file>`. Claude Code runs this command for the token. So the token is in no argument, and `ps` does not show it.
- The `env` of the settings also holds `PROJECT_PLAN`. Its value is the name of the plan, or an empty string when no plan is in effect. Every session that `project open` or `project spawn` starts carries the variable.
- A `project spawn` without `--plan` uses the plan that `PROJECT_PLAN` names in the environment of the session that runs the spawn. An unset variable and an empty variable both mean no plan. The empty string stops the inheritance. A name in the environment would otherwise reach the children of a session without a plan.
- `--plan none` starts the session without a plan and writes an empty `PROJECT_PLAN`. The name `none` is reserved, so a plan file named `none` is not reachable.
- If the plan file does not exist, the command stops and lists the plans that exist. If the token file is not readable, the command stops.
- `project add` starts no session, so it refuses `--plan`. A plain repo also refuses `--plan`.
- If the `ide` window of the checkout is already open, `project open` selects it. When the plan of the window is not the requested plan, `project open` restarts the claude pane under the requested settings. The restarted claude continues the conversation with `--continue`. The old claude process ends. Work that waits at a prompt is lost.
- When no settings name a plan, `claude --resume` and `claude --continue` send the session to the login of Claude Code. The settings on the command line do apply. `claude --continue --settings <settings of a plan>` continues the session under that plan. To resume a session of a plan, start a session with the same `--plan` and use `/resume` in it.
- All plans share the memory of the project (`<dir>/.claude/memory`). Notes that one model writes, a model of another plan reads. This is deliberate.
- With a plan, the prompts and the code of the session go to the third party that runs the endpoint. The children of a session under a plan go to that third party too, because they inherit the plan.

**`project clean [dir] [--dry-run] [--gone]`**

- It runs in a project from any of its checkouts, or on `<dir>`. It does these steps:
  1. It fetches `origin` with `--prune` and a 10-second limit. It then fast-forwards the default branch, if `main/` has it checked out. If `main/` is on another branch, it warns and does not fast-forward. If a step fails, it warns and goes on.
  2. It deletes every merged local branch that has no worktree.
  3. It runs `project close` on every worktree whose branch is merged. It closes the worktree where you run it last, because closing it ends the shell.
- "Merged" has the meaning that `project close` uses, including `projectBase`. A branch with only its creation in the reflog has no work yet. The command skips it, with one exception. A finished review leg is such a branch: a reviewer makes no commits, so its branch holds only the creation entry. The forge deletes the remote branch of a pull request after it merges the pull request, so the upstream of the review branch is gone. When such a branch is merged and its upstream is gone, the command closes its worktree and deletes the branch. When the branch has no upstream, or its upstream still exists, the command keeps the branch and its worktree. A leg that a claim made but no session started has no upstream. The remote branch of a pull request in review still exists.
- `--gone` also cleans branches whose remote branch is deleted. A squash merge leaves such a branch, because the branch is not an ancestor of main. Use it only when the forge deletes branches after a merge. The command saves the upstream tip of each branch before it fetches. It deletes a gone branch only if the local tip equals that saved tip, which shows that no unpushed work exists. It keeps every other gone branch and says so. This includes a branch whose upstream an earlier fetch already removed.
- `--dry-run` prints the steps and changes nothing, except the fetch.
- A worktree with uncommitted work stays open. The command reports it.

**Git metadata of a worktree.** The git metadata of a worktree is in `main/.git`, outside the working directory of its agent. So `project open` and `project spawn` give the session of a worktree these extra permission rules in `--settings`:

- An allow rule permits reads of `main/.git/worktrees/<name>/`, the metadata of that worktree.
- Allow rules permit reads of each other entry in `main/.git`, except `worktrees`. The command finds the entries when it starts the session. An entry that git makes later still prompts.
- An allow rule permits the exact command `ls <dir>/main/.git`. No `Read` rule names `main/.git` itself, because such a rule also matches all the files below it.
- A deny rule blocks edits of every path in `main/.git`.

So the agent cannot read the metadata of another worktree without a prompt. Session rules use absolute paths (`//`). A path with a gitignore special character, for example `*` or `[`, does not match as expected.

**Worktree identity, selectable per leg.** A leg is one session on one worktree. The `--identity` flag of `project open`, `add`, and `spawn` names the git identity of that leg: `agent` (the default), `owner`, or a profile that `main/.claude/settings.local.json` lists under `project.identity.<name>` with `name`, `email`, and `sshCommand` fields. The command writes the identity as per-worktree git config, and git then applies it to every process in the worktree. A leg that the owner writes runs with `--identity owner`, so the commits carry the owner as author.

- The `agent` profile falls back to the `env` block of `main/.claude/settings.local.json`: `GIT_SSH_COMMAND` becomes `core.sshCommand`, and the author or committer name and email become `user.name` and `user.email`. No other env value moves, because the block can hold secrets.
- The `owner` profile falls back to the global git config of the user, and it clears `core.sshCommand`, so an owner leg pushes through the login key of the person.
- An unknown profile name stops the command, so a typo never silently writes the agent identity into an owner leg.
- When the profile resolves to no values, the command writes nothing and leaves the repository config unchanged.
- A worktree that already exists gets the identity of the leg the next time a command names its branch. Empty values are cleared, so a later agent leg does not keep the push key of an owner leg.
- Git applies the identity to every process in the worktree. This includes a person at a terminal.

The `GIT_SSH_COMMAND` entry names the push key of the machine, `~/.ssh/claude-bot`. The forge account `claude-bot` holds its public half, so every push from an agent worktree acts as `claude-bot`. See SSH logins in docs/secrets.md for the key rules.

The command sets `core.repositoryformatversion` to 1 and enables `extensions.worktreeConfig` once per repository, when it writes the first identity. Git reads an `extensions.*` key only at version 1. An older revision of `project` wrote the extension key without the version, so a clone can hold the key at version 0. The command repairs such a clone on the next `project add`, `open`, or `spawn`.

Per-worktree config then lives in `main/.git/worktrees/<name>/config.worktree`. Without the extension, `core.bare` and `core.worktree` of the shared config apply to main only. The extension ends this exception. So the command moves both keys into the `config.worktree` of main, and main works as before.

Main keeps the identity of the person, because per-worktree config applies only inside a worktree.

**The scratch directory.** Every worktree has an untracked `.scratch/` directory at its root. `git.nix` writes the global git ignore file and points `core.excludesFile` at it. The name is ignored in every repository of the user, not only in worktrees. A session puts files there that no commit must see, for example a body file for `tea`. `project close` removes the directory with the worktree. Copy a file out of `.scratch/` when you must keep it. Do not make a nested git repository inside `.scratch/`. When `git init` fails, a later git command of that test acts on the worktree itself. Make a directory outside the worktree for such a test instead. The `path:` source of `local-rebuild` also copies the directory, because a `path:` flake takes untracked files. This increases only the size of the store.

**Claude Code memory.** The memory lives in the project. `project open` starts `claude --settings '{"autoMemoryDirectory": "<dir>/.claude/memory"}'`. A committed `.claude/settings.json` ignores this setting, but a flag is honoured. `main/` and every worktree share this memory, and it stays after `close`. Transcripts stay under `~/.claude/projects/`.

**`project convert <repo>`**

- It moves a plain repo to `<repo>/main` and repairs the linked worktrees of the repo.
- It moves the Claude Code memory for the old path into `<repo>/.claude/memory`.
- It renames the per-path transcript directory to match. The directory is `~/.claude/projects/<path, non-alphanumerics as ->`.

**direnv.** Before `project open` builds the `ide` window, it runs `direnv exec <dir> true` once. This evaluates the `.envrc`, so the panes find the nix-direnv cache and load at once. The command stops after one minute, and the panes then evaluate it themselves. An `.envrc` that is not allowed yet fails silently, and the panes report it. `project add` does not do this. Run `direnv allow` by hand in each new worktree when the `.envrc` differs from `main/`.

## IDE layout (`ide`)

`ide [--detach <session> | --session <session>] [dir] [title] [claude args...]` is a subcommand of the `project` binary. It builds a tmux window named after the directory (or after the title). A fish function of the same name in `fish.nix` adds the change of directory of the caller's shell. When a lone-pane window becomes the ide window, the binary writes the directory to `PROJECT_CD_FILE`. The stub reads the file after the binary ends and changes the shell of the caller into it. This is the cd protocol of the `project` stub.

**Panes:** nvim (started with `--listen`) over a shell, and `claude` on the right, with any extra arguments (fish-escaped). The file tree is a left split inside the nvim pane (see The file tree), and the shell pane spans the width under the editor: the editor and the shell take the width that the yazi pane freed (issue #196).

`ide` writes the `claude` command to a script next to the nvim socket. It types ` source <script>` into the claude pane, and the script removes itself. The pane receives typed text before fish starts, and macOS drops input after about 1 KiB. A long `claude` command, for example one with the `--settings` of `project`, would then lose its Enter. The leading space keeps the line out of the fish history.

**Where the window goes:**

- Inside tmux, the window is a tab of the current session. If the current window is a single pane, `ide` builds the layout in place. Otherwise it makes a new window. A window already open on that directory (`@ide_dir`) is only selected.
- On Darwin, `ide` stops with an error when no tmux server runs (see docs/tmux-darwin.md).
- Outside tmux, `ide` attaches to a session. The session name is the title, or the directory name when no title is given. `--session <session>` sets a different session name.
  - If the session does not exist, `ide` creates it.
  - If the session has a window on that directory (`@ide_dir`), `ide` selects that window. Otherwise, it adds a window to the session.
  - `project open` outside tmux takes none of this path. It opens the session as a tab of the host window (see Projects).
- `ide --detach <session>` puts the window in the tmux session `<session>`. It never attaches and never changes the current tmux window. Scripts and agents use it. `project spawn` passes the project name, so all windows of one project are in one session.
  - In the session name, `_` replaces each run of `.`, `:`, and spaces.
  - If the session exists, `ide` adds the window to it in the background. If not, it creates the session. Inside tmux, a new session gets the size of the current window. Outside tmux, it gets the size of the current terminal.
  - When a terminal is attached to the session, the new window shows in the tmux status bar of that terminal. `ide` opens nothing more.
  - When no terminal is attached, `ide` runs `wezterm-attach` on the session. This opens a tab for the session in the host window.
  - When `SSH_CONNECTION` is set or WezTerm is missing, it prints the `tmux attach` command instead.
  - It fails when any tmux session already has a window on that directory (`@ide_dir`).

**`ide close`.** Run it from any pane of an `ide` window. It kills that window, and the session too if that window is the only one.

- It refuses while nvim has unsaved buffers. It asks nvim over the socket.
- If an `ide-view` viewer stands in for nvim, it first swaps nvim back. This leaves nothing in the throwaway session of the viewer.

**`ide reload`.** It does the same checks as `ide close`. It picks up a rebuild in that window:

1. It re-sources the tmux config.
2. It saves the nvim tabs with `mksession`. It does not use `options`, because `options` would restore the old runtimepath.
3. It quits nvim and starts the new nvim on the same socket from that session. The file tree comes back with nvim: the session restores its window, and the tree module replaces the restored dead window with a live tree.

It leaves the claude pane (possibly the caller) and the shell pane running.

**`ide pop`.** It moves the current tmux window into a new WezTerm window. It works in any tmux window, not only in an `ide` window.

1. It creates a detached session named `pop-<window name>-<window id>`.
2. It moves the window into that session.
3. It opens a WezTerm window of its own on that session. The host window never holds a pop session.

It refuses when the window is the only window of its session. Moving it would destroy the session and the client. When the window closes, the session ends, and the WezTerm window closes with it. Behind the forward of a window of a remote login, the new window attaches over ssh into the login of the session (issue #141). Over a plain ssh login it refuses, because no WezTerm window can show it.

**The host window.** One WezTerm window serves one user on one host, and each tmux session of that user on that host is one tab of it. `wezterm-attach` and every attach of `project` build this grouping.

- The host window carries `user@host` as its title. Both parts are in lower case, and the host part has no domain. The window of a remote login carries the user and the host of the `user@host:` prefix. Two users on one host get two windows: their tmux servers are apart, and their session names can be equal.
- The command finds the window by that title, and it makes the window when no window has the title.
- The `format-window-title` event of the WezTerm config computes the window title (issue #115), so the titles that tmux pushes (`set-titles`) and that a pane pushes cannot change it. The event writes the title back to the window, so `wezterm cli list` keeps reporting it. A command that makes a window writes the title once with `set-window-title`. Each session tab carries its session name, pinned by `set-tab-title`.
- A fresh host window starts with one home tab. The home tab of the local user runs fish in `~` and prints the OS logo and the system information through fastfetch once at its start. `modules/programs/cli/fastfetch.nix` installs fastfetch, so every host and every standalone home has it. No other pane runs it. The home tab of the window of a remote login runs on that login (issue #117): `ssh -t` connects as the user of the title on the host of the title. No local shell starts in that window. The login shell of the remote prints fastfetch when the remote build installs it. A remote host without fastfetch starts the login shell alone. The home tab of a remote login creates no tmux session and attaches to none (issue #134). Its remote command sets the variable `PROJECT_HOME_TAB` before the login shell starts. The tab title of the home tab is the marker of the window: `home` on this machine, or the `user@host` of the login of a delegated window. The marker stays pinned. The `format-window-title` event reads the marker and returns it as the window title. The tab bar shows the working directory of the shell of the home tab, not the marker (issue #135): fish pushes the directory as the pane title through `fish_title`, and the `format-tab-title` event computes the display from the pane title. The home tab of this machine shows the directory alone. The home tab of a remote login names its login before the directory, for example `dev@services: ~`. Every other tab keeps its default title, so a session tab keeps its pinned session name. The tab bar hides while the window holds one tab, so the home tab title shows from the second tab on.
- A remote host window holds three kinds of tab (issue #142). The home tab of the login is the first kind. A session tab is the second kind: it attaches to one tmux session on that host, and it keeps its session name pinned. Its command comes from one place, `remoteSessionCommand` in `modules/programs/cli/project/remote.go`. The command runs `tmux source-file` on the tmux configuration of the host before it attaches (issue #158). The command checks `tmux has-session` before it attaches, and it prints a message that names the session when the session is missing. The guard stops an attach against a host whose server is gone, and it keeps the tab from creating tmux state (issue #161). An attach starts no session. The `new-session -A -s 0` line of the tmux configuration created the stray session 0. The line also attached each client that sourced the configuration to that session. So a session tab landed on session 0 and never reached the guard. The fix of issue #163 removed the line. A tmux server loads its configuration once, at its start, so a server older than the last rebuild holds no binding that the rebuild added. The re-source applies the current configuration to the running server. After a detach, that command runs a login shell on the host. That shell sets `PROJECT_HOME_TAB` and joins no session. The tab ends when that shell exits. A hand-made tab is the third kind, and it pins no title. The new-tab key serves the window it is pressed in. It is the Meta-layer key of the keymap. In the window of a login, the key runs the ssh command of the home tab, so the new tab is a shell on that host. In every other window, the key keeps the default program of the local machine, and so does a new window. The WezTerm config in `modules/programs/gui/wezterm.nix` holds a copy of the remote home command. A test of the project tool holds that copy and `remoteHomeCommand` word for word the same.
- The ssh of the home tab and of every session tab forwards the socket of the WezTerm GUI over its connection, with `-R` (issue #141). The remote end of the forward is a socket path that is unique to the connection, so an ssh that dropped without cleanup blocks no later connection. The ssh command exports two variables to the remote host: `WEZTERM_UNIX_SOCKET` names the forwarded socket, and `PROJECT_GUI_SOCKET` names the socket on the machine that owns the window. With `WEZTERM_UNIX_SOCKET` set, `wezterm cli` on the remote host talks to the GUI on the machine that owns the window. `project open` and `wezterm-attach` on the remote host then open their tabs in the window of the login. A wezterm cli call that runs behind the forward starts from an empty environment that holds only `HOME` and `USER`, both derived from `PROJECT_GUI_SOCKET`, a `PATH` of system directories, `TERM=wezterm`, and `WEZTERM_UNIX_SOCKET`, because the GUI resolves the program of a spawned tab against the environment of the caller, and the `PATH` of the remote host holds no binary of the machine of the GUI (issue #160). The sshd of the remote host must allow stream local forwarding. The NixOS default allows it. The command that starts a tab reads the socket path of the GUI again for every tab, because a restart of the GUI changes the pid in the name of the socket. A restart of the GUI also ends the ssh of every tab, so no forward outlives its window. The tmux option `update-environment` of the remote host copies the two variables into the session environment, so new panes hold the forward. A shell that a detach leaves open keeps both variables, so it holds the forward too.
- A tab of the new-tab key carries no forward. The WezTerm config builds the ssh line of that tab with no socket path of the GUI, so the shell of that tab keeps the reach of a plain ssh login: `project open` there takes over the current terminal.
- The forward is a trust grant. Through it, the account of the login on the remote host can drive the GUI of the machine that owns the window, and it can start processes on it. The two variables reach the tmux server of the remote host and its panes, so an agent session there holds the grant too.
- The WezTerm GUI itself starts its first window as the host window. The gui-startup hook in modules/programs/gui/wezterm.nix opens the home tab in it, sets the window title to `user@host`, and pins the home tab title to `home`, the marker of the window. A start with a program of its own, for example wezterm start with a command, keeps that program and sets no titles.
- At most one tab attaches to one tmux session. When a tab with the name of the session is already open, the command selects it and adds no second client. The reason: two clients on one session mirror the current window of each other.

**`wezterm-attach <session>`.** This command of the `project` binary opens the tab of one tmux session in the host window of this machine, or in the window of the login behind a socket forward. A symlink of the same name in the package reaches it. `ide` and `project` use it.

- It runs `wezterm cli spawn` with `--window-id`, so the tab opens in the running WezTerm GUI.
- If no GUI answers, it runs `wezterm start` on the session. That window gets no title, so the host window appears with the next command.
- Use only this command to open such a tab. `wezterm start` in a tmux pane on Darwin starts a second GUI process, which is separate from the Dock app.
- It removes `TMUX` and `TMUX_PANE` from the environment, because `wezterm cli spawn` gives the environment of the caller to the new pane.

**Window options.** `ide` records the pane ids, the nvim socket, and the plan of the agent session as window options: `@ide_agent`, `@ide_dir`, `@ide_editor`, `@ide_plan`, `@ide_shell`, `@ide_sock`. `@ide_plan` is empty when the session runs no plan. The settings that `project` passes name the plan in `PROJECT_PLAN`, and `ide` reads the name from them. `project open` reads `@ide_plan` to tell whether the pane already runs the requested plan (see Plans).

**The tree refresh.** The tree follows file changes by itself, and no helper process of `ide` is part of the chain (issue #128). The libuv file watcher of the config (`use_libuv_file_watcher`) watches each directory that the tree shows, and neo-tree also registers a watch on the git directory of the worktree. A worktree event, after a write, `git restore`, or `git switch`, refreshes the rows. A git command that changes the index alone, such as `git add`, `git commit`, or `git rm --cached`, writes no file in the worktree, but it writes the index, and the index of a worktree lives in the git directory under `main/`: the watch there fires, and the filesystem source of the tree refreshes, which re-runs the git status of every row. The watcher skips files that end in `.lock`, but git writes `index.lock` and renames it onto `index`, so the event for `index` passes. The refresh runs also when the tree window is hidden.

**Layout hooks.** In `tmux.nix`, the hooks `client-attached` and `client-resized` run `ide-layout`. This command of the `project` binary re-proportions the panes to the window: claude gets 30% of the width (at least 40 columns), and the shell gets 20% of the height (at least 6 rows). The editor pane above the shell takes the rest of the width, and the file tree inside nvim takes its share of the editor.

**Environment.** The shell and claude panes get `IDE_NVIM_SOCK` and `IDE_EDITOR_PANE`. They are set per pane, so several IDEs can share a session. A yazi that starts in such a pane, through the `y` wrapper or the yazi float of nvim, inherits them, and its `edit` opener reaches the nvim pane.

**The file tree.** The tree is neo-tree in a left split of the nvim pane (issue #196), 34 columns wide. The keys sit in the leader-t group of nvim and in the tree window itself; docs/keymap.md holds the table row and the conflict check of each.

- The tree shows the worktree with expandable folders, dotfiles, and gitignored rows. Each row carries its git status at the right, ignored rows in grey. The tree follows the file of the current tab.
- `\t t` hides and shows the tree. `\t f` focuses it and reveals the file of the current tab; from the tree, the key goes back to the editor.
- Enter and `l` expand a folder, collapse an expanded one, and open a file into its own tab through `genixis.ide.open`, under the same tab rules as `ide-open`: a file that is already open switches to its tab, and a blank fresh buffer is reused. `h` collapses a folder, and `q` closes the tree.
- A bare nvim start (the ide editor pane) opens the tree by itself. A start with files keeps the full width for them.
- The tree refreshes itself after worktree events and git-directory events (see The tree refresh), so the marks move after a git command that changes the index alone.

**Opening files from yazi.** The yazi `edit` opener is `ide-open`, a command of the `project` binary. The opener rule sits in `yazi.nix`.

- It sends files to that nvim and focuses the nvim pane.
- Each file opens in its own tab through `genixis.ide.open` over `--remote-expr`. The call is scheduled, so it returns at once. A file that is already open switches to its tab. A blank fresh buffer is reused.
- If the old nvim was quit, it starts a new `nvim --listen` there. Outside an `ide` session, it opens nvim in a new tmux window.
- It must stay non-blocking. A blocking opener stalls yazi for seconds.

**Editing secrets.** In an `ide` window, the fish function `agenix` sets `EDITOR=ide-edit` and runs the real `agenix`.

- `ide-edit` opens each file in the nvim pane, in its own tab, through `genixis.ide.edit`.
- It blocks until the buffer of the file closes or nvim quits. Then `agenix` reads the file.
- Save with `:w` before you close the buffer. A closed unsaved buffer leaves the secret unchanged.
- Outside an `ide` window, `ide-edit` runs plain `nvim`.

**Yazi settings:** yazi keeps no permanent pane of the ide window (issue #196). The `y` wrapper and the yazi float of nvim run it full-screen and floating.

- Yazi shows a single column with no status bar. `mgr.ratio = [0 1 0]` means no parent pane and no preview. Dotfiles show through `mgr.show_hidden`.
- The `git` plugin (`yaziPlugins.git`, with its two `prepend_fetchers`) marks git status at the right of each row. Ignored files get a dark-grey sign, because yazi cannot hide gitignored files.
- `initLua` overrides `Root:layout` to give the status row a height of 0.
- `h` goes up. Enter uses the `smart-enter` plugin: it enters directories and does not send them to nvim.

**Viewer.** Shift+Enter in yazi runs `ide-view`, a command of the `project` binary, on the hovered file.

- The key is a Tool-layer key of the keymap. Yazi cannot see Shift+Enter under tmux, so tmux rewrites it to Alt+Enter in yazi panes.
- The viewer runs in a throwaway tmux session, swapped into the place of the editor pane. It uses glow for markdown and bat for other files. Option+arrows still move between panes.
- `q` swaps nvim back. `ide-open` also swaps it back before it opens a file.

**Tab keys:**

- The nvim tab keys sit in the Tool layer of the keymap. The tabline is numbered to match, and Ctrl+0 selects the 10th tab.
  - In an `ide` window, tmux takes these keys from any pane and runs `ide-tab`. It calls `genixis.ide.tab` over the socket and focuses the editor. For the next and the previous tab, `ide-tab` calls `genixis.ide.step`.
  - Elsewhere, tmux passes the keys through to the maps of nvim itself.
- tmux windows switch on an Option-layer key of the keymap. The stock `prefix 0..9` keys keep their tmux default action. `prefix 1..9` selects the window of its number; `prefix 0` selects no window, because `base-index 1` starts the window numbers at 1.

**Terminal title.** tmux sets it (`set-titles`). It is the session name, so a WezTerm tab keeps one title. The tmux tab shows the window name. The WezTerm config computes the title of the host window, so tmux cannot change it.

**Closing files:**

- `<leader>x` closes a file. If the file window is the only file window of one of several tabs, it also closes the tab; the tree window of the tab goes with it. In the tree window, `<leader>x` and `Ctrl+W` close the tree.
- `hidden` is off and `confirm` is on. So `:q` or `<leader>x` on a modified file asks to save right then. Without this, the changes would stay in a hidden buffer that appears only when you reopen the file.

**Popups.** The popups are Option-layer keys of the keymap: `tmux.nix` binds the lazygit popup, the lazydocker popup, and the keymap popup that shows the rendered keymap table. The lazydocker popup exists only where `programs.lazydocker.enable` is true.
