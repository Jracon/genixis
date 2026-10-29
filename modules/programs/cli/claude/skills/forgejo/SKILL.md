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
| `tea pulls merge` (`m`) `<n>` | Merges a pull request. Never run it. The user merges. |

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

`tea` also has other entities, for example `labels`, `milestones`, and `releases`. Run `tea --help` for the full list.
The hook does not answer for them, so they stop at a permission prompt.

`tea comments` has no verb `show` or `view`. To read the comments of an issue, run `tea comments list <n>` or
`tea issues <n> --comments`.

## Rules of the forge hook

The hook is `forge-hook.py`. It gives one of four answers:

1. Allow: the command runs with no prompt.
2. Ask: the command stops at a permission prompt.
3. Deny: the command does not run.
4. No answer: the permission rules decide. Most of these commands stop at a permission prompt.

### Commands that the hook allows

The hook allows these commands in the working repository. The working repository is the `owner/repo` of the URL of
`origin`.

1. `tea issues`, `tea issues list`, and `tea issues <n>`.
2. `tea pulls`, `tea pulls list`, `tea pulls review-comments`, and `tea pulls <n>`.
3. `tea comments list`.
4. `tea whoami`.
5. `tea issues create`, `tea pulls create`, `tea comments add`, and `tea comments <n> <body>`.
6. `gh issue list`, `gh issue status`, and `gh issue view`.
7. `gh pr checks`, `gh pr diff`, `gh pr list`, `gh pr status`, and `gh pr view`.
8. A `tea` or `gh` command that ends in `--help`, when no flag stands before `--help`.

`tea issues create --repo jracon/genixis` is the one exception to the working repository. The hook allows it in every
project. Use it to open an issue for a change in the global instructions, a global skill, or the global allowlist.

### Commands that the hook asks about

1. `tea issues edit`, `tea issues close`, and `tea issues reopen`.
2. `tea pulls edit`, `tea pulls close`, and `tea pulls reopen`.
3. `tea comments edit`.
4. A command that names a repository other than the working repository with a repository flag. The flags are
   `--repo` and `-r` in `tea`, and `--repo` and `-R` in `gh`.
5. A command with `--login`, `-l`, `--remote`, `--owner`, or `--org`. A `tea` command with `-R` is also in this
   group. In `gh`, `-l` is also in this group, although it selects a label in `gh pr list`.
6. A `gh` command, or a `tea` command that is not a write, with an argument in the form `owner/repo` or with `://`,
   for example a URL.
7. A command with a `$` in any argument. This includes the text of a title or a body.
8. A command with a backtick or a command substitution anywhere in it. This includes the text of a title or a body.
9. A command with a here document or a subshell.
10. A `tea` command with a flag between the entity and the verb, when a word after the flag is a write verb. For
    example, `tea issues --state all close 35` stops at a prompt.
11. A command inside another command that can run commands, for example `bash -c`, `env`, `sudo`, `nix`, `xargs`, or
    `timeout`.

### Commands that the hook denies

1. `tea pulls merge` and `gh pr merge`, with any flags.
2. `tea comments delete`.
3. `git push` to a trunk branch. See "`git push`" below.
4. `git push` with `--force`, `-f`, `--force-with-lease`, `--force-if-includes`, `--all`, `--branches`, `--mirror`, or
   `--prune`.
5. `git push` with a refspec that starts with `+`.

### Pipes and chains

The hook reads each part of a pipe or a chain. If it denies one part, it denies the full command. Otherwise, if it asks
about one part, it asks about the full command. It allows the full command only when it allows each part. A part that
it does not answer for, for example `head`, removes the answer, and the command stops at a prompt. Run one plain
command in each shell call. Do not pipe the output of `tea` or `gh`.

### `git push`

A trunk branch is `main`, `master`, the default branch, or a branch named `trunk` or `*/trunk`. The default branch
is `project.defaultBranch` in the git config. If that key is not set, it is the branch that `origin/HEAD` names.

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

## Text of titles, bodies, and comments

A `$` or a backtick in the text makes the command stop at a prompt. Markdown code spans use backticks. Do these steps
when the body of an issue or a pull request has a backtick or a `$`:

1. Write the body to a file in the scratchpad directory with the file tool of your agent.
2. Pass the file with `--description-file <path>`.

`tea comments add` has no `--description-file`. Write a comment without a backtick and without a `$`.

## Conventions

1. Open a pull request against the branch in `branch.<name>.projectBase` in the git config. If no such entry exists,
   open it against the default branch. Pass the branch with `--base`.
2. In a pull request body on Forgejo, write the closing keyword before each issue number: `Closes #1, closes #2`.
   Forgejo can skip issues in a list that follows one keyword.
3. Never merge a pull request. The user reviews and merges.
4. Never delete a comment.
5. Push the branch before you run `tea pulls create`. `tea` uses the state of the remote, not the local state.
