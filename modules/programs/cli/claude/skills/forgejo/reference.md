# The deep rules of the forge hook

This file holds the rules behind the summary of `SKILL.md`: the four answers of the hook, the full lists of the
commands that it allows, asks about, and denies, and the deep rules behind the conditions. Read the section that
names your command before you run it.

## The four answers

The hook is `forge-hook.py`. It gives one of four answers:

1. Allow: the command runs with no prompt.
2. Ask: the command stops at a permission prompt.
3. Deny: the command does not run.
4. No answer: the permission rules decide. Most of these commands stop at a permission prompt.

## Commands that the hook allows

The hook allows these commands in the working repository. The working repository is the `owner/repo` of the URL of
`origin`.

1. `tea issues`, `tea issues list`, and `tea issues <n>`.
2. `tea pulls`, `tea pulls list`, `tea pulls review-comments`, and `tea pulls <n>`.
3. `tea comments list`.
4. `tea labels list`.
5. `tea whoami`.
6. `tea issues create`, `tea pulls create`, `tea comments add`, and `tea comments <n> <body>`.
7. `tea labels create`.
8. `tea issues edit <n> --add-labels <labels>` and `--remove-labels <labels>`, when the command changes labels only,
   no label is human-only, and the repository sets the `forge.humanLabels` key. See "Human-only labels" below.
9. `tea issues edit <n>` and `tea pulls edit <n>` with `--title` (`-t`), `--description` (`-d`), or
   `--description-file`, when the login of the session owns the entity. See "Edits of an owned entity" below.
10. `tea pulls merge <n> --style squash`, when the base branch of pull request `<n>` ends in `/composition`. See
    "Merges into a composition branch" below.
11. `gh issue list`, `gh issue status`, and `gh issue view`.
12. `gh pr checks`, `gh pr diff`, `gh pr list`, `gh pr status`, and `gh pr view`.
13. A `tea` or `gh` command that ends in `--help`, when no flag stands before `--help`.

`tea issues create --repo jracon/genixis` is the one exception to the working repository. The hook allows it in every
project. Use it to open an issue for a change in the global instructions, a global skill, or the global allowlist.

Put the file of a `--description-file` flag under `.scratch/` of the worktree, and name the path relative to the
worktree root. The hook asks for every other path, also `-` for stdin. Only `tea issues create`, `tea pulls
create`, and the edit of an owned entity carry the flag. The forge and its public mirror would carry any file
that the session can read, so the hook keeps the upload inside the scratch directory.

## Commands that the hook asks about

1. `tea issues edit` in each case that "Human-only labels" and "Edits of an owned entity" below do not cover: an
   edit of a field other than the title and the body, an edit of an entity that the login does not own, an edit in
   a repository that sets no `forge.humanLabels` key, and an edit of several issues. `tea issues close` and
   `tea issues reopen` also stop at a prompt.
2. `tea pulls edit` in each case that "Edits of an owned entity" below does not cover. `tea pulls close` and
   `tea pulls reopen` also stop at a prompt.
3. `tea comments edit`.
4. `tea labels update` and `tea labels delete`.
5. A command that names a repository other than the working repository with a repository flag. The flags are
   `--repo` and `-r` in `tea`, and `--repo` and `-R` in `gh`.
6. A command with `--login`, `-l`, `--remote`, `--owner`, or `--org`. A `tea` command with `-R` is also in this
   group. In `gh`, `-l` is also in this group, although it selects a label in `gh pr list`.
7. A `gh` command, or a `tea` command that is not a write, with an argument in the form `owner/repo` or with `://`,
   for example a URL.
8. A command with a `$` in any argument. This includes the text of a title or a body.
9. A command with a backtick or a command substitution anywhere in it. This includes the text of a title or a body.
10. A command with a here document or a subshell.
11. A `tea` command with a flag between the entity and the verb, when a word after the flag is a write verb. For
    example, `tea issues --state all close 35` stops at a prompt.
12. A command inside another command that can run commands, for example `bash -c`, `env`, `sudo`, `nix`, `xargs`, or
    `timeout`.
13. `tea pulls merge` in each case that the hook does not allow or deny. See "Merges into a composition branch"
    below.
14. A `--description-file` path outside `.scratch/` of the worktree, also `-` for stdin, in `tea issues create`,
    `tea pulls create`, or the edit of an owned entity.

## Commands that the hook denies

1. `gh pr merge`, with any flags.
2. `tea pulls merge`, when the base branch of the pull request is a trunk branch. See "`git push`" below for the
   meaning of a trunk branch.
3. `tea comments delete`.
4. `tea issues edit` with `--add-labels`, `-L`, or `--remove-labels`, when the value names a human-only label. See
   "Human-only labels" below.
5. `git push` to a trunk branch. See "`git push`" below.
6. `git push` with `--force`, `-f`, `--force-with-lease`, `--force-if-includes`, `--all`, `--branches`, `--mirror`, or
   `--prune`.
7. `git push` with a refspec that starts with `+`.
8. A compound command in a session of `project spawn`. See "Sessions of `project spawn`" below.

## Human-only labels

A project can make a label human-only. Only a person adds this label to an issue or removes it from an issue. The
git config key `forge.humanLabels` of the repository lists these labels. The key can have more than one value. Each
value is a comma-separated list of label names. The hook ignores case when it compares the names.

The key also lets an agent change the other labels. When the repository sets the key, the hook allows `tea issues
edit <n>` with only these options: `--add-labels` (`-L`) and `--remove-labels`, and a `--repo` that names the working
repository. The command must name one issue only, and each label that it adds or removes must be outside
`forge.humanLabels`. The hook asks when the repository sets no key, and when the command also changes the title, the
body, or another field.

To read the list, run `git config --get-all forge.humanLabels`. Never add a human-only label to an issue, also not
with `tea issues create --labels`. Never remove a human-only label from an issue. Never change the key. If an issue
needs a change of a human-only label, tell the user.

## Edits of an owned entity

An entity is an issue or a pull request. The login of the `tea` session owns an entity when the login wrote the
entity. On this machine, the login of every session is `claude-bot`. The person acts as `jracon` through the web UI,
so an entity that `jracon` wrote is not owned.

The hook allows `tea issues edit <n>` and `tea pulls edit <n>` without a prompt for an owned entity. The command
must change the title or the body only, and it must meet all of these conditions:

1. It names one entity number only.
2. Its only options are `--title` (`-t`), `--description` (`-d`), `--description-file`, and a `--repo` (`-r`) that
   names the working repository.
3. The entity is in the working repository.
4. The login of the session wrote the entity.

The hook reads the entity with `tea issues <n> --output json` or `tea pulls <n> --output json`. It reads the login
with `tea whoami`, from the first stdout line that starts with a hash sign. It asks when it cannot read the entity
or the login.

The hook asks when the command names two entities or none. It asks when the command has another option: labels,
assignees, a milestone, a deadline, `--draft`, `--ready`, or an option that the hook does not know.

The deny for a human-only label comes first. The hook denies an edit that names a human-only label, also when the
edit changes the title at the same time. The allow for an edit of labels only stays as before.

## Merges into a composition branch

A composition branch is a branch whose name ends in `/composition`. A project can let an agent merge a feature pull
request into its composition branch. The `AGENTS.md` of the project gives the conditions. If the project does not
give them, do not merge.

The hook runs `tea pulls <n> --output json` to find the base branch of pull request `<n>`. It gives these answers to
`tea pulls merge <n>`:

1. Deny: the base branch is a trunk branch. This includes the default branch.
2. Allow: the base branch ends in `/composition`, and the command has `--style squash`.
3. Ask: every other case. Some examples are a merge without `--style squash`, a base branch that does not end in
   `/composition`, and a base branch that the hook cannot find.

An allowed merge can have only these options: `--style` (`-s`), `--title` (`-t`), `--message` (`-m`), `--output`
(`-o`), and a `--repo` (`-r`) that names the working repository. With another option, the hook does not allow the
merge. Give one pull request number only.

Run the merge in this form: `tea pulls merge <n> --style squash`.

## Pipes and chains

The hook reads each part of a pipe or a chain. If it denies one part, it denies the full command. Otherwise, if it asks
about one part, it asks about the full command. It allows the full command only when it allows each part. A part that
it does not answer for, for example `head`, removes the answer, and the command stops at a prompt. Run one plain
command in each shell call. Do not pipe the output of `tea` or `gh`.

## Sessions of `project spawn`

`project spawn` sets the environment variable `PROJECT_SPAWN_SESSION=1` for its session. In such a session, the hook
denies a compound command: a pipe, a chain, a loop, or a command substitution. The reason tells the agent to split the
command into one plain command for each shell call. A deny gives the reason at once, so the agent can correct the
command and continue. A prompt would stop the session until a person answers. In a session without the variable, the
hook gives no answer for these commands.

`project spawn --headless` sets a second variable, `PROJECT_HEADLESS_SESSION=1`, beside the first. Under that marker,
every answer of ask becomes deny. The reason tells the session to report on its entity and stop. No person sits behind
the prompts of a headless session. A windowed spawn keeps its prompts.

## `git push`

A trunk branch is `main`, `master`, the default branch, or a branch named `trunk` or `*/trunk`. The default branch
is `project.defaultBranch` in the git config. If that key is not set, it is the branch that `origin/HEAD` names.

A worktree push uses the push key of the machine, `~/.ssh/claude-bot`. The forge sees the account `claude-bot`.

The hook denies `git push` to a trunk branch. It allows `git push` to a branch that is not a trunk branch. These
forms stop at a prompt:

1. A push to a branch that is the `projectBase` of another branch, for example a composition branch. A `projectBase`
   that is also a trunk branch gets a deny.
2. A remote that is not a named remote of the repository.
3. `--delete`, `-d`, or a refspec with an empty source, such as `:feat/x`.
4. `--tags`, or a refspec that is a pattern or a ref outside `refs/heads/`.
5. `--repo`, `--receive-pack`, or `--exec`.
6. A `git push` with no refspec when `push.default` is `matching` or `upstream`.

Push the current branch with `git push -u origin <branch>`.

The forge backs these rules with branch protection. On the default branch, only `jracon` may push and merge, and the
forge denies force push and deletion. On every other branch, the forge denies force push.

A push that passes the hook can still fail at the forge. Treat that failure as a stop. Report it. Do not retry with
other flags.
