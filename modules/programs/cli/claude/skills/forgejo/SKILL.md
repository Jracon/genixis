---
name: forgejo
description: Use before you run `tea` or `gh`, for example to read, create, or edit issues, pull requests, or comments on Forgejo or GitHub. Lists the verified verbs of `tea issues`, `tea pulls`, and `tea comments`, the rules of the forge hook that allows, asks about, or denies each command, and the conventions for pull requests and comments.
---

# Forgejo and GitHub commands

`tea` is the command-line tool of the self-hosted Forgejo server. `gh` is the command-line tool of GitHub. A hook
reads each `tea`, `gh`, and `git push` command before it runs. The hook allows the command, asks the user, or denies
the command. A command with a wrong verb or a wrong form stops at a permission prompt, and the user must answer it.

## Before you run a command

1. Find the verb in the tables below.
2. If the verb is not in the tables, run `tea <entity> --help` or `gh <group> --help` first.
3. If a `tea` or `gh` command fails, run `--help` on the same entity before you try again. Do not guess a second verb.

A nil-pointer panic of a `tea` detail command, for example `tea issues <n>`, means that the Forgejo server was
unreachable. The panic does not mean a wrong verb. The version check of `tea` 0.16.0 raises it instead of a
network error. Check the network before you try a second verb.

The verbs below come from `tea` 0.16.0. Flags can change between versions. Run `tea <entity> <verb> --help` before you
use a flag that this skill does not show.

## Verbs of `tea`

Write the entity directly after `tea` and the verb directly after the entity. Put the flags after the verb.

`tea issues` (aliases `issue` and `i`):

| Command | Action |
| --- | --- |
| `tea issues` or `tea issues list` (`ls`) | Lists the open issues. |
| `tea issues <n>` | Shows issue `<n>`. Add `--comments` to also show its comments. |
| `tea issues create` (`c`) `--title <t> --description <d>` | Creates an issue. `--description-file <path>` reads the body from a file. |
| `tea issues edit` (`e`) `<n>` | Changes the title, the body, the labels, or other fields of an issue. |
| `tea issues close <n>` | Closes an issue. |
| `tea issues reopen` (`open`) `<n>` | Opens a closed issue again. |

`tea pulls` (aliases `pull` and `pr`):

| Command | Action |
| --- | --- |
| `tea pulls` or `tea pulls list` (`ls`) | Lists the open pull requests. |
| `tea pulls <n>` | Shows pull request `<n>`. Add `--comments` to also show its comments. |
| `tea pulls review-comments` (`rc`) `<n>` | Lists the review comments of a pull request. |
| `tea pulls create` (`c`) `--base <branch> --title <t> --description <d>` | Creates a pull request from the current branch. `--description-file <path>` reads the body from a file. |
| `tea pulls edit` (`e`) `<n>` | Changes the fields of a pull request. |
| `tea pulls close <n>` | Closes a pull request. |
| `tea pulls reopen` (`open`) `<n>` | Opens a closed pull request again. |
| `tea pulls checkout` (`co`) `<n>` | Checks out the branch of a pull request. |
| `tea pulls merge` (`m`) `<n>` | Merges a pull request. `--style squash` (`-s`) makes a squash merge. Run it only as "Merges into a composition branch" in `reference.md` permits. |

`tea pulls` also has the verbs `clean`, `review`, `approve`, `reject`, `reply`, `resolve`, and `unresolve`. The hook
does not answer for them, so they stop at a permission prompt.

`tea comments` (aliases `comment` and `c`):

| Command | Action |
| --- | --- |
| `tea comments list` (`ls`) `<n>` | Lists the comments of issue or pull request `<n>`, with the ID of each comment. |
| `tea comments add` (`a`) `<n> <body>` | Adds a comment to issue or pull request `<n>`. |
| `tea comments <n> <body>` | Does the same as `tea comments add`. |
| `tea comments edit` (`e`) `<id> <body>` | Changes the body of the comment with the ID `<id>`. |
| `tea comments delete` (`rm`) `<id>` | Deletes a comment. Never run it. |

Post a comment in the verb form: `tea comments add <n> <body>`. The hook allows the verb form in the working
repository, also with a multi-line body. Do not put a repository flag between the entity and the verb. The hook does
not see the verb behind a flag, and it gives no allow for that form.

`tea labels` (alias `label`):

| Command | Action |
| --- | --- |
| `tea labels list` (`ls`) | Lists the labels of the repository. |
| `tea labels create` (`c`) `--name <name> --color <hex>` | Creates a label. `--description <d>` sets its description. |
| `tea labels update` | Changes a label. A change of a name changes the label on each issue that has it. |
| `tea labels delete` (`rm`) | Deletes a label. The label goes off each issue that has it. |

`tea` also has other entities, for example `milestones` and `releases`. Run `tea --help` for the full list. The hook
does not answer for them, so they stop at a permission prompt.

`tea comments` has no verb `show` or `view`. To read the comments of an issue, run `tea comments list <n>` or
`tea issues <n> --comments`.

## What the hook answers

The hook gives one of four answers: allow, ask, deny, or no answer. A command with no answer goes to the permission
rules, and most of these commands stop at a permission prompt.

The hook allows the read verbs of the tables above in the working repository, the write verbs `tea issues create`,
`tea pulls create`, `tea comments add`, `tea comments <n> <body>`, and `tea labels create` in the working repository,
the read verbs of `gh`, and a `tea` or `gh` command that ends in `--help`, when no flag stands before `--help`. The
working repository is the `owner/repo` of the URL of `origin`.

`tea issues create --repo jracon/genixis` is the one exception to the working repository. The hook allows it in every
project. Use it to open an issue for a change in the global instructions, a global skill, or the global allowlist.

Three forms run with no prompt under conditions: an edit that changes labels only, an edit of the title or the body
of an entity that the login of the session owns, and a squash merge into a composition branch. `reference.md` beside
this file states each condition.

The hook asks about every other form of the verbs above: `close`, `reopen`, `tea comments edit`, `tea labels update`,
`tea labels delete`, and each merge form that no rule allows. It also asks about a command that selects another
repository or login, a command with `$`, a backtick, or a command substitution, a command inside another command,
and a `--description-file` path outside `.scratch/` of the worktree. The full list of these forms sits in
`reference.md`.

The hook denies `gh pr merge`, `tea comments delete`, `tea pulls merge` into a trunk branch, an edit that names a
human-only label, and a `git push` that overwrites or removes branches.

Put the file of a `--description-file` flag under `.scratch/` of the worktree, and name the path relative to the
worktree root. The hook asks for every other path, also `-` for stdin. Only `tea issues create`, `tea pulls
create`, and the edit of an owned entity carry the flag. The forge and its public mirror would carry any file
that the session can read, so the hook keeps the upload inside the scratch directory.

Run one plain command in each shell call. Do not pipe the output of `tea` or `gh`. The hook reads each part of a
pipe or a chain, and a part that it does not answer for stops the full command at a prompt. The rules of pipes, of
chains, and of the sessions that `project spawn` starts sit in `reference.md`.

## Text of titles, bodies, and comments

A `$` or a backtick in the text makes the command stop at a prompt. Markdown code spans use backticks. Do these steps
when the body of an issue or a pull request has a backtick or a `$`:

1. Write the body to a file in `.scratch/` at the root of the repository, with the file tool of your agent. Git
   ignores the directory, so no commit sees the file.
2. Pass the file with `--description-file <path>`.

`tea comments add` has no `--description-file`. Write a comment without a backtick and without a `$`.

Angle brackets in a comment swallow the span between them, because Forgejo renders them as HTML. A key name or a
ref template between angle brackets disappears from the posted comment. A title also passes through the command
line, so it cannot hold a code span. Write key names and ref templates in plain words in comments and titles.

## Conventions

1. Open a pull request against the branch in `branch.<name>.projectBase` in the git config. If no such entry exists,
   open it against the default branch. Pass the branch with `--base`.
2. In a pull request body on Forgejo, write the closing keyword before each issue number: `Closes #1, closes #2`.
   Forgejo can skip issues in a list that follows one keyword.
3. Never merge a pull request. The user reviews and merges. There is one exception: a project can let an agent merge a
   pull request into a composition branch. See "Merges into a composition branch" in `reference.md`.
4. Never delete a comment.
5. Push the branch before you run `tea pulls create`. `tea` uses the state of the remote, not the local state.
6. Push the current branch with `git push -u origin <branch>`. Read the rules of every other push form in
   `reference.md` before you push.

## The reference file

`reference.md` beside this file holds the full lists of the allowed, asked, and denied commands and the deep rules
behind them: human-only labels, edits of an entity that the login owns, merges into a composition branch, pipes and
chains, the sessions that `project spawn` starts, and every rule of `git push`. Read the section that names your
command before you run it.
