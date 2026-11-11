# forge-hook

The Claude Code context of the machines this flake builds: the settings layers, the plans, and the answers of the forge hook.

Domain: what. Reader: a session that changes the agent context or the hook, or debugs a permission answer.
Code: modules/programs/cli/claude.nix, modules/programs/cli/claude/, common/llm-agents.nix, .claude/settings.json.

## What is the topic?

Three pieces form the agent context:

1. The settings layers. The user layer lives in `~/.claude/settings.json`, and each switch of a home writes it from claude.nix. The project layer lives in `.claude/settings.json` of a repository, tracked by git, and holds the build, push, and forge rules of that repository.
2. The plans. An endpoint configuration names a base URL, the three model slots, and a token file. The project binary starts a session under a plan (modules/programs/cli/claude.nix:215-231, 234-276).
3. The forge hook. A PreToolUse hook answers allow, ask, or deny for each `tea`, `gh`, and `git push` command, by the working repository (modules/programs/cli/claude.nix:111-122; forge-hook.py:1-6, 770-795).

## How is the topic realized?

The user settings layer (modules/programs/cli/claude.nix):

1. Claude Code rewrites `~/.claude/settings.json` itself, for example on an always-allow choice, so the file stays mutable. Each switch adds the rules of the flake and removes only the rules that the previous switch added, through the state file `~/.claude/.genixis-permissions.json` (claude.nix:161-183).
2. The allow list holds the routine read-only commands and the local git writes: the search tools, the read verbs of tea, gh, qmd, and semble, zat, jq, `git add` to `git worktree list`, and the project verbs that never discard (claude.nix:14-60).
3. The read grants name the machine context: the Nix store, `~/.claude/settings.json`, and `~/.claude/skills` (claude.nix:62-67).
4. The deny list holds the flags that make a search tool run other programs or write files, the nix forms that run code or read any file, `gh pr merge`, `git -C`, the bypassed commit hooks, every force push, `project discard`, and the read and edit of `.env` files (claude.nix:69-109).

The machine context of a session:

1. `~/.claude/CLAUDE.md` is built from modules/programs/cli/claude/CLAUDE.md, with the installed-tools list appended from the `genixis.claude.tools` option (claude.nix:126-128, 185-194).
2. The skills land in `~/.claude/skills`: factory, forgejo with its reference, project, search, semantic-diff, technical-english (claude.nix:195-204). The hunk skill comes from its package, so no vendored copy drifts (common/llm-agents.nix:36-41).
3. The agent tools themselves come from the llm-agents input, with `claude-code`, and each tool declares one description sentence beside its install (common/llm-agents.nix:9-34).
4. The session recap stays off through a declared variable, because the settings file cannot hold it reliably (claude.nix:206-208).

The plans (modules/programs/cli/claude.nix:132-158, 234-276):

1. The `zai` plan is on for every user exactly when the encrypted token file is committed. A secret that agenix cannot decrypt fails every secret of the user, so the token file gates the plan (claude.nix:132-140; docs/secrets.md).
2. The token file lands at `~/.config/project/plans/zai.token`, and the session reads it through the helper of the plan, never from a settings value (claude.nix:215-231).
3. The plan file holds the endpoint variables and a timeout, and no token (claude.nix:217-231).

The forge hook (modules/programs/cli/claude/forge-hook.py):

1. The hook reads the working repository, the branch, the remotes, and the login from git and tea (forge-hook.py:134-255).
2. It allows the read verbs and the create verbs of the working repository, the `--help` forms, and the read verbs of gh (forge-hook.py:522-615).
3. It asks about the entity edits, closes, reopens, merges, and label changes, a command that names another repository or login, a command that holds a dollar, a backtick, or a substitution, a tea, gh, or push command inside another command, a loop, and a description file outside the scratch directory of the worktree (forge-hook.py:47-131, 409-426, 478-519).
4. It denies the delete of a comment, a merge into a trunk branch, an edit that names a human-only label, and a push that overwrites or removes branches (forge-hook.py:429-475, 544, 618-697).
5. A session of `project spawn` or a headless session turns every ask into a deny, so the session never waits for a person (forge-hook.py:118-122, 753-767).
6. The full verb tables and the deep rules sit in the forgejo skill and its reference file (modules/programs/cli/claude/skills/forgejo/).
7. A hook allow skips the prompt in the manual and dontAsk permission modes. A deny rule still beats a hook allow, and a hook ask overrides an allow rule. The probes ran through the nested print-mode session; the other permission modes are untested.

The human-only labels: the hook reads the git config key `forge.humanLabels` of the repository, and each value is a comma-separated list (forge-hook.py:191-199). A repository that sets no key gets an ask on every label edit (forge-hook.py:587). No step of this repository writes the key: each clone sets it by hand, and the produced-project runbook step lives in docs/runbook.md.

## Why is the topic that way?

1. The harness is a replaceable part, and the enforcement lives where an agent cannot influence it: the OS, the network, the identity, and the forge (Stance item 3, docs/design-philosophy.md).
2. A headless session never waits for a person. What enforcement would ask about, it denies, and the session reports and stops (Layering item 8, docs/design-philosophy.md).
3. Enforcement stands in two layers: the local gate answers first, and the forge answers last (Layering item 9, docs/design-philosophy.md).
4. A description file reaches the forge only from the scratch directory of the worktree, because the forge and its mirror would carry any file that a session can read (docs/decisions.md, record 4).
5. A token reaches a process only through a file that the process reads, so no token sits in a command argument or a plan file (Security law item 3, docs/design-philosophy.md; docs/decisions.md, record 10).
6. The `.env` read denies stay at every tier, because the forge and the public mirror form an exfiltration channel (Security law item 5, docs/design-philosophy.md).
7. The hook is security spine: it stays human-authored with agent assist (Layering item 1, docs/design-philosophy.md).

## What does the topic enable?

The end of the topic: agent sessions act inside rules they cannot change, on every machine this flake builds, and the same rules answer on every forge command. The Layering and trust section of docs/design-philosophy.md states the criteria.

## How does a reader use and change the topic?

Run a forge command: read the forgejo skill first. It holds the verbs and the forms that run with no prompt.

Change the rules of a repository: edit `.claude/settings.json` of that repository, and state each allowed command in the AGENTS.md of the repository in the same commit. A rule matches the start of a command only.

Change the user layer: edit modules/programs/cli/claude.nix, never `~/.claude` itself, and rebuild the home.

Probe the settings behaviour: start the nested print-mode session with the scratch settings file that the AGENTS.md of the repository names.

Test the hook: run `python3 modules/programs/cli/claude/forge-hook-test.py`. CI runs it on every pull request (.forgejo/workflows/ci.yaml:26-27). Add one case to the harness for each new rule, and change the forgejo skill in the same commit, because the skill tells agents the answers of the hook.
