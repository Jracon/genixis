# agent-context

Claude Code context of the machines this flake builds: the settings layers, the plans, and the answers of the forge hook.

## Settings, Plans, and Hook

Three pieces form the agent context:

1. Settings layers. A user layer lives in `~/.claude/settings.json`, and each switch of a home writes it from claude.nix. A project layer lives in `.claude/settings.json` of a repository, tracked by git, and holds the build, push, and forge rules of that repository.
2. Plans. An endpoint configuration names a base URL, the three model slots, and a token file. A project binary starts a session under a plan.
3. Forge hook. A PreToolUse hook answers allow, ask, or deny for each `tea`, `gh`, and `git push` command, by the working repository.

## User Settings Layer

1. Claude Code rewrites `~/.claude/settings.json` itself, for example on an always-allow choice, so the file stays mutable. Each switch adds the rules of the flake and removes only the rules that the previous switch added, through the state file `~/.claude/.genixis-permissions.json`.
2. One allow list holds the routine read-only commands, the local git writes, and the two index commands of `qmd`: the search tools, the read verbs of tea, gh, qmd, and semble, `qmd update` and `qmd embed` for a fresh checkout, zat, jq, `git add` through `git worktree list`, and the project verbs that never discard. Both index rules cover the bare commands only, because `qmd update --pull` also runs `git pull`.
3. Read grants name the machine context: the Nix store, `~/.claude/settings.json`, and `~/.claude/skills`.
4. One deny list holds the flags that make a search tool run other programs or write files, the nix forms that run code or read any file, `gh pr merge`, `git -C`, the bypassed commit hooks, every force push, `project discard`, and the read and edit of `.env` files.

## Machine Context of a Session

1. `~/.claude/CLAUDE.md` is built from modules/programs/cli/claude/CLAUDE.md, with the installed-tools list appended from the `genixis.claude.tools` option.
2. Skills land in `~/.claude/skills`: adr, diataxis, factory, forgejo with its reference, project, search, semantic-diff, technical-english. One hunk skill comes from its package, so no vendored copy drifts.
3. Agent tools themselves come from the llm-agents input, with `claude-code`, and each tool declares one description sentence beside its install.
4. Session recap stays off through a declared variable, because the settings file cannot hold it reliably.

## Plans

1. Plan `zai` is on for every user exactly when the encrypted token file is committed. A secret that agenix cannot decrypt fails every secret of the user, so the token file gates the plan (docs/secrets.md).
2. One token file lands at `~/.config/project/plans/zai.token`, and the session reads it through the helper of the plan, never from a settings value.
3. Each plan file holds the endpoint variables and a timeout, and no token.

## Forge Hook Answers

1. A hook reads the working repository, the branch, the remotes, and the login from git and tea.
2. It allows the read verbs and the create verbs of the working repository, the `--help` forms, and the read verbs of gh. One exception holds in every project: the hook allows `tea issues create` for the repository `jracon/genixis`, where the issues of the global instructions live.
3. It asks about the entity edits, closes, reopens, merges, and label changes, a command that names another repository or login, a command that holds a dollar, a backtick, or a substitution, a tea, gh, or push command inside another command, and a description file outside the scratch directory of the worktree.
4. It denies the delete of a comment, a merge of a pull request through gh, a merge into a trunk branch, an edit that names a human-only label, and a push that overwrites or removes branches.
5. A spawned session gets a deny for a compound command (a pipe, a chain, a loop, or a substitution), so it splits the command into one plain command for each shell call. A headless session turns every ask into a deny, so the session reports on its entity and stops. The settings of a spawn carry the marker, and a replan of an ide window restores it from the recorded session kind of the window (docs/project.md).
6. Full verb tables and deep rules sit in the forgejo skill and its reference file.
7. A hook allow skips the prompt in the manual and dontAsk permission modes. A deny rule still beats a hook allow, and a hook ask overrides an allow rule. Its probes ran through the nested print-mode session; the other permission modes are untested.

Human-only labels: a hook reads the git config key `forge.humanLabels` of the repository, and each value is a comma-separated list. A repository that sets no key gets an ask on every label edit. No step of this repository writes the key: each clone sets it by hand, and the produced-project runbook step lives in docs/runbook.md.

## Trust Criteria

1. The forge hook is one enforcement layer that an agent session cannot influence, beside the OS, the network, and the identity (Stance item 3, docs/design.md).
2. Least privilege per identity. Each machine holds one scoped token and one push key. A missing scope is added alone, and a wider role is never the answer. Its agent login holds no admin role.
3. Env-tier denies stay at every tier. A commit can carry a secret out through the forge and the public mirror, so no local sandbox replaces the upper tiers.
4. A headless session never waits for a person. What enforcement would ask about, it denies, and the session reports on its entity and stops.
5. Enforcement stands in two layers. A local gate answers first, and the forge answers last. Both hold the same trunk rules. docs/ci.md holds the gate side.
6. A replacement lands and passes its probe before the rule it replaces is deleted.
7. Each plan token reaches its process through the file that the process reads, under the token rule of docs/secrets.md (docs/adr/project-tool-plan-tokens.md).
8. A description file reaches the forge only from the scratch directory of the worktree, because the forge and its mirror would carry any file that a session can read (docs/adr/scratch-description-files.md).
9. Rules, skills, and memory stay harness-neutral in their source. Each harness materializes its own format from one declarative source, so a second harness changes no policy.
10. Hook, hook rules, sandbox profiles, branch protection, and the tea wrapper are security spine: they stay human-authored with agent assist.
11. Workaround record, the local permission rules of claude.nix (docs/adr/earlier-records-clause-scope.md). Context: the sandbox probes of phase 5 of issue 74 have not passed, so no probe backs a rule. Decision: the rules stay temporary until the probes pass. Options that lost: none on record. Consequences: no probe verifies a rule of the local layer, and the env-tier denies of item 3 stay load-bearing. Status: solve. Reopen trigger: the probes of phase 5 pass.
12. Deferred with a trigger: per-agent forge users, while the single scoped login with branch protection stands.

## Purpose of the Agent Context

Purpose of the topic: agent sessions act inside rules they cannot change, on every machine this flake builds, and the same rules answer on every forge command. Trust criteria above and docs/design.md state the rules.

## Run and Change the Rules

Run a forge command: read the forgejo skill first. It holds the verbs and the forms that run with no prompt.

Change the rules of a repository: edit `.claude/settings.json` of that repository, and state each allowed command in the AGENTS.md of the repository in the same commit. A rule matches the start of a command only. One allow rule of this repository, `tea comment` with a body, learned that limit under dontAsk: a multi-line body did not match the rule, and the verb form `tea comments add`, which carries its body as the last argument, replaced it for comments (issue 226).

Change the user layer: edit modules/programs/cli/claude.nix, never `~/.claude` itself, and rebuild the home.

Probe the settings behaviour: start the nested print-mode session with the scratch settings file that the AGENTS.md of the repository names. Each scratch settings file must carry the `env` block of the plan and the `apiKeyHelper` of the plan, because a plan reaches a session only through its settings file. Without them, the nested run dies on `unrecognized_model` and a `401` answer (issue 236).

Test the hook: run `python3 modules/programs/cli/claude/forge-hook-test.py`. CI runs it on every pull request. Add one case to the harness for each new rule, and change the forgejo skill in the same commit, because the skill tells agents the answers of the hook.
