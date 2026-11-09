# Claude Code context and the forge hook

The `claude.nix` context of Claude Code: the skills, the permissions, the plans, and the answers of the forge hook.

### Claude Code context and permissions (`claude.nix`)

`claude.nix` writes the user-level context of Claude Code through Home Manager. The sources are in `claude/`:

- `claude/CLAUDE.md` becomes `~/.claude/CLAUDE.md`. It tells an agent in any project about this machine. It also holds the rules that apply in every project: commands, git and forges, work, and communication. Keep it short, because every session loads it.
  - Put a rule here only when it applies to every project. A rule for one project goes in the `AGENTS.md` of that project.
  - When you add a rule here, remove the copies of it from the `AGENTS.md` files of projects.
  - Write the rules for any agent. Name a feature of Claude Code only when no general word exists.
- Each `claude/skills/<name>/SKILL.md` becomes `~/.claude/skills/<name>/SKILL.md`. A session loads a skill only when a task needs it. These skills exist:
  - `factory` gives the worker and reviewer roles of the factory loop, the owner brief, and the five risk signals.
  - `forgejo` gives the verbs of `tea`, the rules of `claude/forge-hook.py`, and the conventions for pull requests and comments.
  - `project` explains the `project` command to agents.
  - `search` gives the routing rule between `rg`, `semble`, and `qmd`, and the commands of `semble` and `qmd`.
  - `semantic-diff` compares a rewrite with its original and finds each change in meaning.
  - `technical-english` gives the rules of Simplified Technical English for text that agents read.

`claude.nix` also appends the section "Installed tools" to that file. It builds the section from the option `genixis.claude.tools`, which maps a command name to a `description` and an optional `package`. The module that installs a general-purpose tool declares it there, next to the install. Set `package` when no `programs.<name>` module installs the tool. List only tools that change what an agent does in any project. Do not list every package.

Write each `description` from the documentation of the tool. Read its `--help` first. Do not write it from memory. Give one sentence: what the tool does and which tool it replaces. Do not put a command form or a setup step in the sentence. The skill of the tool holds the procedure, and the `AGENTS.md` of a project holds the setup that the project needs. Describe the command-line interface of the tool only. Name no MCP server and no HTTP API, because the agents on these machines use the command line. A description of a tool names no issue, pull request, or commit, and states what the tool does.

Tools for this repository only (`nixd`, `nixfmt`, `nh`) stay out of that option. Put them in the section "Tools" of this file.

`claude.nix` also sets `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=0` through `home.sessionVariables`. This turns off the automatic session recap. The variable beats `awaySummaryEnabled` in every settings file.

`genixis.claude.plans.<name>` declares a plan for `project --plan` (see docs/project.md). Its fields are `baseUrl`, `models.{haiku,opus,sonnet}`, `extraEnv`, and `tokenFile`.

- `tokenFile` is a path, for example `config.age.secrets.<name>.path`. Never put a token in `extraEnv`, because the plan file is in the Nix store.
- Use a Home Manager agenix secret for the token, not a system secret. A system secret belongs to root with mode `0400`, so the session of a user cannot read it. Every Home Manager user decrypts with `~/.ssh/genixis_user`, also in the standalone homes.
- `claude.nix` declares the plan `zai`, the Z.ai GLM Coding Plan, for every Home Manager user. Its token is the secret `claude/zai_token.age`.
- The plan and its secret exist only when `claude/zai_token.age` exists. To turn the plan on, run `agenix -e modules/programs/cli/claude/zai_token.age` and `git add` the file.
- Never commit an empty or invalid `.age` file for a plan. If agenix cannot decrypt one secret, it stops before it links the new secrets. So the other secrets of that user also fail, for example `.ssh/config.age`.

Claude Code rewrites `~/.claude/settings.json`, so Nix does not own that file. `claude.nix` changes only its `permissions` key and its `hooks` key, through the activation step `claudePermissions`:

- The `permissions` binding in `claude.nix` lists the global `allow` and `deny` rules.
- Each switch adds these rules to the file. It keeps the rules that Claude Code or the user added.
- `~/.claude/.genixis-permissions.json` records the rules and the hooks of the last switch. The next switch removes a recorded rule or hook that Nix no longer lists.
- Global rules allow read-only commands and deny actions that no agent may take. They do not allow `EnterWorktree` and `ExitWorktree`. An agent starts work in a worktree with `project spawn`. The one global forge write is `tea issues create --repo jracon/genixis`. The global `CLAUDE.md` tells agents to open an issue there for a necessary global change.
- Global rules also allow these local git writes: `git add`, `git commit`, `git merge --no-ff`, `git mv`, and `git switch`. Deny rules block `git commit` with `--no-verify` or `-n`.
- Put build commands, `git push`, and forge writes in the `.claude/settings.json` of each project. A prefix rule cannot stop a push to the default branch, so `git push` stays out of the global rules.
- A deny rule must cover the flags that make an allowed tool run other programs or write files, for example `rg --pre`, `fd -x`, `ast-grep -i`, and `ast-grep --custom-languages`.

The `hooks` binding of `claude.nix` lists one `PreToolUse` hook for the Bash tool. It runs `claude/forge-hook.py`. A permission rule is a text pattern and cannot see the working repository. The hook reads `git remote get-url origin` and answers for each `tea`, `gh`, and `git push` command. It also answers for a compound command in a session that `project spawn` started:

- It denies a compound Bash command (a pipe, a chain, a loop, or a command substitution) in a session that `project spawn` started. The environment variable `PROJECT_SPAWN_SESSION=1` marks the session (see docs/project.md). The reason tells the agent to split the command into one plain command for each shell call. A deny beats the allow rules of the session. A session without the marker keeps the old behaviour.
- It answers deny where it would ask, in a session that `project spawn --headless` started. The environment variable `PROJECT_HEADLESS_SESSION=1` marks the session (see docs/project.md). The reason tells the session to report on its entity and stop. No person sits behind the prompts of a headless session. A windowed spawn keeps its prompts.
- It gives no answer to any other command. The permission rules then decide.
- It answers `ask` when the command names another repository or login (`--repo`, `-r`, `--owner`, `--org`, `--login`, `--remote`, or an `owner/repo` argument). The one exception is `tea issues create --repo jracon/genixis`, which the hook allows in every project.
- It answers `ask` when it cannot read the command: `bash -c`, a command substitution, a here document, a subshell, or a shell variable in an argument.
- It allows the read-only subcommands of `tea` and `gh` in the working repository.
- It allows a `tea` or `gh` command that ends in `--help`, when no flag and no shell variable stands before `--help`. A flag can take `--help` as its value.
- It allows `tea labels list` in the working repository.
- It allows `tea pulls create`, `tea comment`, `tea issues create`, and `tea labels create` in the working repository.
- It answers `ask` for `tea issues close`, `tea issues reopen`, `tea pulls close`, and `tea pulls reopen`.
- It answers `ask` for `tea labels update` and `tea labels delete`. A change of one label changes every issue that has the label.
- It denies `gh pr merge` and `tea comments delete`.
- It reads the base branch of a pull request with `tea pulls <n> --output json` before it answers for `tea pulls merge <n>`:
  - It denies the merge when the base branch is a trunk branch. The meaning of a trunk branch is the same as for `git push` below.
  - It allows the merge when the base branch ends in `/composition` and the command has `--style squash`. The command can also have `--title`, `--message`, `--output`, and a `--repo` that names the working repository, or their short forms. It must name one pull request number only.
  - It answers `ask` in every other case. This includes a base branch that the hook cannot find.
  - The global `CLAUDE.md` lets an agent merge into a composition branch only when the `AGENTS.md` of the project gives the conditions.
  - No global deny rule names `tea pulls merge`, because a deny rule beats a hook `allow`. `gh pr merge` keeps its deny rule.
- The git config key `forge.humanLabels` of each repository lists its human-only labels. Each value of the key is a comma-separated list. The comparison ignores case. The hook reads the key before it answers for `tea issues edit`:
  - It denies the edit when `--add-labels`, `-L`, or `--remove-labels` names a human-only label.
  - It allows the edit when the repository sets the key. The command must also change labels only: one issue number, `--add-labels`, `-L`, `--remove-labels`, and a `--repo` that names the working repository.
  - It answers `ask` in every other case. This includes an edit in a repository that sets no key. The rule for an owned entity decides an edit of the title or the body.
- It reads the writer of an entity (an issue or a pull request) with `tea issues <n> --output json` and `tea pulls <n> --output json`, and the login of the session with `tea whoami`, before it answers for `tea issues edit` and `tea pulls edit`:
  - It allows the edit when the login wrote the entity and the url of the entity belongs to the working repository. The command must name one entity number only, and its only options are `--title`, `-t`, `--description`, `-d`, `--description-file`, and a `--repo` that names the working repository.
  - It answers `ask` in every other case. This includes several entity numbers, any other option, an entity of another repository, an entity that another login wrote, and an entity or a login that the hook cannot read.
- It allows `git push` when no pushed branch is a trunk branch or a `projectBase` of a branch. The hook reads the branch from the refspec, or from `git branch --show-current` when the refspec is missing. A trunk branch is `main`, `master`, the default branch, or a branch named `trunk` or `*/trunk`. The default branch is `project.defaultBranch`. If that key is not set, it is the branch that `origin/HEAD` names.
- It denies `git push` to a trunk branch, whatever the order of the flags. It also denies `--force`, `-f`, `--force-with-lease`, a `+` refspec, `--all`, `--branches`, `--mirror`, and `--prune`.
- It answers `ask` for `git push` to a `projectBase` of a branch that is not a trunk branch, for example a composition branch. An orchestrator can push such a branch when the user allows the push at the prompt. The reason of the answer names the branch as a `projectBase`.
- It answers `ask` for a deleting push: `--delete`, `-d`, or a refspec with an empty source, for example `:feat/x`. A person approves each deletion at the prompt.

The forge enforces the same trunk rules through branch protection. On `main`, a rule permits push and merge for `jracon` only, and it denies force push and deletion. A glob rule denies force push on every other branch. The forge deletes the remote branch of a pull request after it merges the pull request (see docs/project.md). A branch of a merged pull request needs no deletion by hand. The hook is the first layer, and the forge is the second.

A push that the hook allows can still fail at the forge. Treat a forge rejection as a stop. Report it, and do not retry with other flags. The local rules stay until the phase 5 probes on issue 74 pass and replace them.

Every machine that runs agent sessions uses one scoped token for its `tea` login. The token belongs to `claude-bot`. Its scopes are user read, repository write, and issue write. The hook needs the user scope for `tea whoami`.

A hook `allow` skips the prompt in the `manual` and `dontAsk` permission modes. A deny rule still beats a hook `allow`. A hook `ask` overrides an allow rule. The probes ran on Claude Code through `claude -p`. Other permission modes are untested.

After you change `claude/forge-hook.py`, run `python3 modules/programs/cli/claude/forge-hook-test.py`. The script has `allow`, `deny`, and `ask` cases. Add a case for each new rule.

A change to `claude/forge-hook.py` needs a change to the `forgejo` skill in the same commit. The skill tells agents which commands the hook allows, asks about, and denies.

Do not manage any other key of `~/.claude/settings.json` from Nix. Use an environment variable, as for the session recap.

Do not edit these files in `~/.claude`. Change the source and rebuild. When you change the options of `project`, change the skill in the same commit.
