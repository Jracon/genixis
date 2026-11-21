# agent-context

Claude Code context of the machines this flake builds: the settings layers, the plans, and the answers of the forge hook.

## Settings, Plans, and Hook

Three pieces form the agent context:

1. Settings layers. A user layer lives in `~/.claude/settings.json`, and each switch of a home writes it from claude.nix. A project layer lives in `.claude/settings.json` of a repository, tracked by git, and holds the build, push, and forge rules of that repository.
2. Plans. An endpoint configuration names a base URL, the three model slots, and a token file. A project binary starts a session under a plan.
3. Forge hook. A PreToolUse hook answers allow, ask, or deny for each `tea`, `gh`, and `git push` command, by the working repository. The policy lives in the tea wrapper, and the hook delegates each command to it.

## User Settings Layer

The user layer and the project layer hold different rules. The user layer gives the read-only tools and the git workflow that every project shares. It denies command forms: a flag, a command shape, a file read. No deny rule of the user layer names a whole tool, so each project can allow the tools of its own stack. The project layer gives the build, test, and forge commands of its one repository.

An allow rule of the project layer adds to the rules of the user layer. A deny rule of the user layer overrides every allow rule. A command that no allow rule covers stops at a prompt. The owner adds the rule to the `.claude/settings.json` of the project.

Two commands stay in the project layer alone, by the ruling of the owner (issue 509). `git rm` can destroy file content that no commit holds. The user layer holds no command that destroys content. `printenv` can read a token of the tooling of another project. The user layer reads no environment.

`nix eval` over flake attributes and `nix build` over the `system.build.toplevel` of a host sit in the project layer of this repository alone, by the ruling of the owner (issue 510). The deny rules that close `--expr` and `--apply` stay in force above the eval rule.

`git ls-remote`, `git remote -v`, and `git config --get*` sit in the user layer, by the ruling of the owner (issue 510). The first two are read verbs of the remote state. The third reads the git config keys, and it replaced `git config --get-all forge.humanLabels`, a strict subset of it. The headless probe of nvim holds no rule, by the same ruling. A rule for `nvim --headless` covers each headless call, and headless lua runs any code, so each call of the probe stops at a prompt.

`qmd trust` holds no rule, by the same ruling (issue 540). The bare command approves the checked-in config of the current tree. An approved config can run code, so the approval stays with the owner of the host. The search skill records the hand-off, and the trust state is per host and per config path.

1. Claude Code rewrites `~/.claude/settings.json` itself, for example on an always-allow choice, so the file stays mutable. Each switch adds the rules of the flake and removes only the rules that the previous switch added, through the state file `~/.claude/.genixis-permissions.json`.
2. One allow list holds the routine read-only commands, the local git writes, and the two index commands of `qmd`: the search tools, the read verbs of tea, gh, qmd, and semble, `qmd update` and `qmd embed` for a fresh checkout, zat, jq, `which`, `hostname`, `uname`, the session verbs of `hunk`, `mkdocs serve`, `git add` through `git worktree list`, `git config --get*`, `git config branch.*.projectBase`, `git rev-list`, `git pull --ff-only`, `git ls-remote`, `git remote -v`, and the project verbs that never discard. Both index rules cover the bare commands only, because `qmd update --pull` also runs `git pull`. The hunk rules cover the session verbs alone, and each destructive or interactive verb of the tool stops at a prompt.
3. One Read grant names the machine context: `Read(~/.claude/settings.json)`. The skills home and the store read through the working-directory entries of item 6. The store grant served no read beside its entry, so it left the tree (issue 598). The Read Rule Matrix below states which rule form serves a read.
4. One deny list holds the flags that make a search tool run other programs or write files, the nix forms that run code or read any file, `gh pr merge`, `git -C`, the bypassed commit hooks, every force push, `project discard`, and the read and edit of `.env` files.
5. The outside-directory read block of Claude Code gates the Bash commands that it recognizes as file-reading. The probes of 2026-11-16 saw it stop rg, grep, cat, ls, and wc, and each refusal names the verb of the command. The block resolves each path argument before it decides, also a relative path that climbs out of the working directory, and it stops the call when a target sits outside the allowed working directories of the session. It acts before the allow rules. No rule shape covers such a call. The `Bash(rg *)` rule lost to it, an allow rule that matched the whole command text lost to it, and an allow rule that named the path lost to it. The switch `permissions.blockReadsOutsideWorkingDirectories`, set to false in the settings file of a nested probe, did not lift the block, and no settings layer of this host sets the switch: where the on state comes from stays unnamed. Each permission mode that asks, asks for such a call, and a session that no person answers refuses it. fd is not a command that the block recognizes, so an fd call that names an outside path runs on its `Bash(fd *)` rule. An `rg` call over the skills home ran in the print-mode probe of 2026-11-20 and in the background probe of 2026-11-21 (issue 598). The block did not stop it in either session kind. This command table is the asymmetry of issue 437. In auto mode with the built-in classifier on, the classifier answered such an rg call (issue 436).
6. The user layer names the Nix store and the skills home in `permissions.additionalDirectories`, so the read commands of item 5 run over the store tree. The store carries no Read grant: the entry alone serves every read of the tree (issue 598). An entry of a repository settings file does not count for the block, so the user layer carries each entry. The skills home entry is the ruled route of issue 585: the home is flake-built and holds instruction text only, the glob Read grant did not serve the file tool in the harness build of 2026-11-20, and the entry served the same read with no prompt, in every session that the skills serve. Each other outside path still stops its call, in every mode: the limit is final. A deny rule still denied an rg call with `--pre` over the store in the probe, so the flag surface of the search tools stays closed. The skills-home entry opens no write surface. The write probes of 2026-11-20 (issue 601) ran in two nested print-mode sessions. One session held the skills home in `permissions.additionalDirectories`, and the other session held no entry. In both runs, the Write tool and an `rm` call under the home met the same refusal. An exact allow rule covered the `rm` call, and each refusal names the path a sensitive file. The sensitive-file ask sits above the allow rules, as the read block of item 5 does. A session that no person answers refuses each such call. The probes covered the print-mode session alone, because the `--print` flag of the nested probe and the `--bg` flag of the harness conflict. No allow rule covers the background form of the probe, so the write answer of a background session stays open (issue 601).

## The Read Rule Matrix

1. The probes of 2026-11-21 measured each `Read` rule form for the file tools, with reads of paths outside the working directories (issue 598). A rule serves a read when the read runs with no prompt. A rule refuses a read when the read stops at a permission refusal.
2. The probes covered each rule form (exact and glob), each path form (tilde, one leading slash, two leading slashes), and each layer (user, project, settings file of a spawn). They ran in the nested print-mode session and in one background session that `project spawn --headless` started. Each rule that both session kinds measured gave the same answer.
3. The path form of the rule alone decides the answer. The rule form, the layer, and the session kind change nothing.

| Path form of the rule | Exact rule | Glob rule |
| --- | --- | --- |
| Tilde | Serves | Serves |
| One leading slash | Refuses | Refuses |
| Two leading slashes | Serves | Serves |

4. The tilde probe rule was `Read(~/projects/genixis/main/README.md)`. The one-slash probe rule was `Read(/home/dev/projects/genixis/main/README.md)`. The two-slash probe rule was `Read(//home/dev/projects/genixis/main/README.md)`.
5. The user-layer row ran with a relocated config directory (`CLAUDE_CONFIG_DIR` in the settings file of the probe), so no live rule masked the probe rule. The project-layer row ran with `.claude/settings.local.json` of the worktree. The settings-file row ran with the `--settings` file of the probe, which carries the rule shapes that a spawn writes.
6. The tree `~/.claude/skills` refuses every probed rule form, in every layer and in both session kinds. The working-directory entry of the user layer names the serving route of the skills home (issue 585).
7. The store needs no Read grant. The `additionalDirectories` entry of the user layer serves every read of the store tree, and the one-slash glob form serves no read in any layer.
8. The grant `Read(~/.claude/settings.json)` is alive. A probe that held no rule refused the read of the settings file. The exact tilde form serves the read in every probed layer.
9. The Read rules that a spawn writes use the two-slash form (modules/programs/cli/project/internal/settings/settings.go). The form serves in a print-mode session and in a background session, so the spawn settings carry no dead Read rule.

## Machine Context of a Session

1. `~/.claude/CLAUDE.md` is built from modules/programs/cli/claude/CLAUDE.md, with the installed-tools list appended from the `genixis.claude.tools` option.
2. Skills land in `~/.claude/skills`: adr, diataxis, factory, forgejo with its reference, project, search, semantic-diff, technical-english. One hunk skill comes from its package, so no vendored copy drifts.
3. Agent tools themselves come from the llm-agents input, with `claude-code`, and each tool declares one description sentence beside its install.
4. Session recap stays off through a declared variable, because the settings file cannot hold it reliably.

## Plans

1. Plan `zai` is on for every user exactly when the encrypted token file is committed. A secret that agenix cannot decrypt fails every secret of the user, so the token file gates the plan (docs/secrets.md).
2. One token file lands at `~/.config/project/plans/zai.token`, and the session reads it through the helper of the plan, never from a settings value.
3. Each plan file holds the endpoint variables and a timeout, and no token.
4. The zai plan sets `CLAUDE_CODE_AUTO_MODE_SERVER` to 0. The endpoint does not pass the server-side safety check of auto mode through, so auto mode without the variable asks about each Bash call that no allow rule covers, and a session that no person answers refuses the call. The variable keeps the built-in classifier of auto mode on (issue 436).

## Forge Hook Answers

1. The hook delegates each command to the tea wrapper, which reads the working repository, the branch, the remotes, and the login from git and tea.
2. It allows the read verbs and the create verbs of the working repository, the `--help` forms, and the read verbs of gh. One exception holds in every project: the hook allows `tea issues create` for the repository `jracon/genixis`, where the issues of the global instructions live.
3. It asks about the entity edits, closes, reopens, merges, and label changes, a command that names another repository or login, a command that holds a dollar, a backtick, or a substitution, a tea, gh, or push command inside another command, and a description file outside the scratch directory of the worktree.
4. It denies the delete of a comment, a merge of a pull request through gh, a merge into a trunk branch, a create verb or an edit that names a human-only label, and a push that overwrites or removes branches.
5. A spawned session gets a deny for a compound command (a pipe, a chain, a loop, or a substitution), so it splits the command into one plain command for each shell call. A headless session turns every ask into a deny, so the session reports on its entity and stops. The settings of a spawn carry the marker, and a replan of an ide window restores it from the recorded session kind of the window (docs/project.md).
6. Full verb tables and deep rules sit in the forgejo skill and its reference file.
7. A hook allow skips the prompt in the manual and dontAsk permission modes. A deny rule still beats a hook allow, and a hook ask overrides an allow rule. Its probes ran through the nested print-mode session; the other permission modes are untested.
8. The merge check of the hook reads the pull request with tea under a 15-second timeout. When the read fails, for example at the timeout, the hook asks. The owner accepted this behavior on 2026-11-18 (issue 381). A failed read never becomes an allow. A session that a person watches gets the decision, and a headless leg reports on its entity and stops.
9. The merge check reads the base branch of the pull request one time and trusts this answer. The merge command carries no base, so the forge merges into the base that the pull request holds at the merge. The base can change between the read and the merge, and the merge then lands on the new base. The owner accepted this window on 2026-11-18 (issue 381). The only allow form is a squash merge into a composition branch. The window is seconds wide, and the forge answers last on the default branch, where the agent login cannot merge.
10. The policy home is `tea-wrapper.py` (modules/programs/cli/claude/): the verb tables of tea and gh, the ownership rule, and the trunk rules. The hook delegates each plain `tea`, `gh`, or `git push` command to the wrapper. The delegation runs the wrapper with the interpreter of the hook under a 60-second bound. A wrapper that crashes or times out leaves the hook with no answer, so the permission rules decide (Trust criterion 13e).
11. The wrapper also runs at a terminal under the name `tea-wrapper`, and each home of this flake installs it (claude.nix). It prints the response envelope of the project tool and exits from the vendored table: 0 for an allow and for no opinion, 2 for a wrong call, and 7 for each refusal. The command `tea-wrapper check-permissions -- <command>` answers for one plain command. The command `tea-wrapper --dry-run tea <command>` prints the envelope and runs nothing. The command `tea-wrapper tea <command>` runs tea when the policy allows it or holds no opinion, and refuses on an ask and a deny. The decision of an ask belongs to the person at the terminal (docs/runbook.md).
12. The hook asks about a `tea-wrapper` command in a session. The wrapper runs a tea command inside it, so it sits in the wrapper table of the hook, beside `bash` and `env`.

Human-only labels: the wrapper reads the git config key `forge.humanLabels` of the repository, and each value is a comma-separated list. A repository that sets no key gets an ask on every label edit. No step of this repository writes the key: each clone sets it by hand, and the produced-project runbook step lives in docs/runbook.md.

## The Command Inventory

The table maps each command form that this repository names for agent work to the layer that allows it. The layers are the project rules of `.claude/settings.json`, the user rules of `claude.nix`, and the allow answers of the forge hook. A form with no rule names the reason that covers it. Issue 538 holds the probe evidence of the audit of 2026-11-19.

| Command form | Allowed by | Named by |
| --- | --- | --- |
| `nix fmt` | project rule | AGENTS.md |
| `nix fmt -- --ci` | project rule | AGENTS.md, factory skill |
| `nix flake check --impure` | project rule | AGENTS.md, factory skill |
| `nix build .#checks.x86_64-linux.<check> --no-link` | project rule | AGENTS.md |
| `nix build .#nixosConfigurations…` (dry build) | project rule | AGENTS.md |
| `nix eval .#…` | project rule | AGENTS.md |
| `nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath` | project rule | AGENTS.md |
| `nix flake archive --json --dry-run` | project rule | docs/flake.md |
| `bash .forgejo/scripts/check-commit-subjects.sh <range>` | project rule | AGENTS.md, factory skill |
| `go test -C modules/programs/cli/project ./...` | project rule | factory skill |
| `gofmt -l modules/programs/cli/project`, `gofmt -w` on the same path | project rule | AGENTS.md |
| `python3 --version` | project rule | AGENTS.md, docs/ci.md |
| `python3 modules/programs/cli/claude/forge-hook-test.py` | project rule | factory skill |
| `python3 modules/services/dispatcher/dispatcher-test.py` | project rule | docs/services.md |
| `python3 modules/services/dispatcher/sandbox-probe.py` | no rule; the live probe runs on `services` inside a session, and the settings-file gate keeps the rule with the owner until the sandbox tier lands (issue 470) | dispatcher/README.md, docs/services.md |
| `claude -p --settings .scratch/<file>` | project rule | AGENTS.md |
| `claude --bg <prompt>` (nested background probe) | no rule; the `--print` flag and `--bg` conflict, so a headless leg runs no nested background probe (issue 601) | docs/agent-context.md item 6 |
| `git push -u origin ai/<branch>` | project rule | factory skill |
| `git rm <paths>` | project rule | AGENTS.md |
| `printenv <name>` | project rule | no source names it for agent work; issue 509 keeps the rule as an orientation command of legs |
| `tea pulls create --repo jracon/genixis --description-file .scratch/<file>` | project rule, hook allow | factory skill, forgejo skill |
| `rg <pattern> <path>` | user rule | search skill |
| `fd <pattern> <path>` | user rule; deny rules close the exec flags | search skill |
| `qmd update`, `qmd embed` | user rule, bare form only | search skill |
| `qmd search`, `qmd query`, `qmd vsearch`, `qmd get`, `qmd multi-get`, `qmd status`, `qmd doctor`, `qmd collection list`, `qmd trust list`, `qmd --help` | user rule | search skill |
| `semble search <query>`, `semble find-related <file> <line>` | user rule | search skill |
| `zat <file>` | user rule | search skill |
| `mkdocs serve` | user rule | AGENTS.md, docs/cli.md |
| `hunk session <session verb>` | user rule | AGENTS.md |
| `git status`, `git diff`, `git log`, `git show`, `git rev-parse`, `git rev-list`, `git fetch`, `git merge-base` | user rule | factory skill |
| `git add`, `git commit`, `git pull --ff-only` | user rule | factory skill |
| `git merge --no-ff origin/main -m <subject>` | user rule | factory skill |
| `git merge origin/main` | no rule; the catch-up merge runs in the `--no-ff` shape that the user layer allows (issue 544) | factory skill |
| `git config branch.<name>.projectBase` | user rule | AGENTS.md |
| `git config --get-all forge.humanLabels` | user rule, through `git config --get*` | AGENTS.md |
| `tea issues`, `tea issues <n> --comments` | hook allow | factory skill, forgejo skill |
| `tea pulls`, `tea pulls <n>`, `tea pulls review-comments <n>` | hook allow | factory skill |
| `tea comments list <n>` | hook allow, user rule | factory skill |
| `tea labels list`, `tea whoami` | hook allow | factory skill |
| `tea comments add <n> <body>` | hook allow | AGENTS.md |
| `tea issues create --repo jracon/genixis` | hook allow, the one exception | forgejo skill |
| `tea issues create --description-file .scratch/<file>` | hook allow, in the working repository | factory skill |
| `tea issues create --repo jracon/genixis --description-file .scratch/<file>` | user rule, hook allow | factory skill |
| `tea-wrapper tea <command>`, `tea-wrapper --dry-run tea <command>` | no rule; the wrapper serves the owner at a terminal, and the hook asks about it in a session (issue 556) | docs/runbook.md, forgejo skill |
| `tea-wrapper check-permissions -- <command>` | no rule; the hook is the one caller, through its delegation (issue 556) | forgejo skill, reference.md of the skill |
| read verbs of `gh` | hook allow, user rule | forgejo skill |
| `qmd trust` | no rule in any layer; the bare command approves the checked-in config of the current tree, and the approval stays with the owner of the host (issue 540) | search skill |
| `nix repl .#…` | deny rule of the user layer; the AGENTS.md block that names it serves a person at a terminal | AGENTS.md |
| `nix flake update` | no rule; the nightly workflow runs it (docs/ci.md) | AGENTS.md |
| `nixos-rebuild`, `darwin-rebuild`, `home-manager switch`, `rebuild`, `rehome` | no rule; the TOOLS section of AGENTS.md forbids a rebuild by an agent | AGENTS.md |
| destructive and TUI verbs of `hunk session` | no rule; each call stops at a prompt (issue 510) | AGENTS.md |
| entity edits of `tea`: `close`, `reopen`, `edit`, `labels update`, `labels delete`, each merge | hook asks; a headless session gets a deny | forgejo skill |

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
13. Acceptance record, the heuristic limits of the forge hook (issue 378). Context: the hook reads each
    command with a tokenizer and word tables, so its reading is heuristic. The risks of pull request 37
    named five limits of that design, and no record held a decision on them. The owner took each decision
    in the windowed session of the issue, and ruled the route of the text: an agent writes this record.
    Decision: the owner accepts each limit as a stated design, for the reasons below. Options that lost:
    a fix or a tracker for each limit. The layers behind the hook hold each gap, so no fix is scheduled.
    The limits follow, each with its reason and its review trigger.
    a. Heuristic parse. The tokenizer needs only the plain command shapes that the global instructions
       prescribe. A shape that it cannot read falls through to a prompt or a deny, not to an allow.
       Review trigger: a rewrite of the hook.
    b. The `Bash` tool only. The forge verbs run through the `Bash` tool. The other tools hold no shell
       to hide a command in, and the settings layers gate them. Review trigger: a forge verb that runs
       through another tool.
    c. The interpreter and the PATH. Every home this flake builds puts `git` and `tea` on PATH. The
       store `python3` pins the interpreter against the host. A missing binary degrades to an ask where
       the hook needs it. Review trigger: a host that runs the hook without `git` or `tea` on PATH.
    d. The stray-verb check. No allow rule covers a `tea` command with flags before the entity word, so
       the shape still stops at a prompt or a headless refuse. The taught forms put the entity first.
       Review trigger: an allow rule that covers flag-first shapes.
    e. No answer on a crash or a timeout. The allow rules and the deny rules of the settings layers stay
       in force under no answer. A crashed or timed-out hook degrades to the pre-hook permission state,
       never to an open gate. Review trigger: a hook answer that becomes load-bearing for a deny that no
       settings rule backs.
    Consequences: no entity tracks a fix, because no limit was rejected. The ruling on the text covers
    this file alone. The hook code and the settings rules stay hand-authored (item 10, issue 378). The
    probe status of the permission modes stays out of scope (issue 378). Status: keep as a stated design.
    Reopen trigger: a change that a review trigger above names.

## Purpose of the Agent Context

Purpose of the topic: agent sessions act inside rules they cannot change, on every machine this flake builds, and the same rules answer on every forge command. Trust criteria above and docs/design.md state the rules.

## Run and Change the Rules

Run a forge command: read the forgejo skill first. It holds the verbs and the forms that run with no prompt.

Change the rules of a repository: edit `.claude/settings.json` of that repository. State each allowed command in the AGENTS.md of the repository, and update the command inventory, in the same commit. A rule matches the start of a command only. One allow rule of this repository, `tea comment` with a body, learned that limit under dontAsk: a multi-line body did not match the rule, and the verb form `tea comments add`, which carries its body as the last argument, replaced it for comments (issue 226). The flag-first rule `tea comment --repo jracon/genixis *` and its two deny rules left the project layer on 2026-11-18, because no consumer remained (issue 509, docs/adr/stale-tea-comment-rules-removed.md).

Change the user layer: edit modules/programs/cli/claude.nix, never `~/.claude` itself, and rebuild the home.

Change the allowlist from the loop: the gate of the harness on a settings file sits above the allow rules, and a headless leg gets a denial for an edit (issue 470). The ruled route is the windowed leg. The owner starts the leg with one `/loop window` comment, on the gated issue or on the open pull request of the branch (issue 516). The dispatcher spawns the leg with a permission mode that waits, and the owner answers the consent prompt in the view window of the session. The route and its probe live in modules/services/dispatcher/README.md.

Write files from a background session: the isolation guard of the harness also sits above the allow rules (issue 511). It rejects each edit of a background session in a shared checkout until the session isolates its changes. No allow rule lifts it. The guard names two isolation routes, and the global instructions forbid both.

A background session in the main checkout therefore writes no file under `.scratch/`. The owner ruled the route on 2026-11-18. The guard stays, and each background session starts in a worktree. The session writes the tree that it holds, and each dispatcher leg already runs this way.

Options that lost: the `worktree` switch with `bgIsolation` set to `none`. It lifts the guard for the full checkout, so a background session would also write the tracked files of the main checkout. The prompt-approval route lost, because each watched background session repeats the round trip of the consent prompt. Consequences: a watched background session in the main checkout writes only through an approved consent prompt. That approval is no standing answer, and an unwatched background session writes no file there. Reopen trigger: a switch of the harness that lifts the guard for the scratch directory alone.

Probe the settings behaviour: start the nested print-mode session with the scratch settings file that the AGENTS.md of the repository names. Each scratch settings file must carry the `env` block of the plan and the `apiKeyHelper` of the plan. A plan reaches a session only through its settings file. Without them, the nested run dies on `unrecognized_model` and a `401` answer (issue 236). A background session runs each probe in its worktree (issue 511).

A probe prompt names a command file under `.scratch/`. The nested session runs each line of that file as one command. No probe names a command in prompt prose (issue 495). Punctuation of the prompt text can attach itself to a command as a trailing argument. The call then misses the rule under test.

Test the hook: run `python3 modules/programs/cli/claude/forge-hook-test.py`. The harness drives the hook and the wrapper. CI runs it on every pull request. Add one case to the harness for each new rule, and change the forgejo skill in the same commit, because the skill tells agents the answers of the hook.
