---
name: factory
description: Use when a session acts as a worker leg or a reviewer leg of the factory loop on a forge ticket, when it writes the brief of such a leg, or when a person runs a leg by hand. Covers the two roles, the brief obligation, and the risk score.
---

# The factory loop

The loop turns a forge ticket into work. The dispatcher on the `services` host starts
each leg with `project spawn --headless`. A leg is one session on one branch of a
project. The worker writes the change. The reviewer writes the verdict. The owner
reviews and merges. The reference of the dispatcher is
`modules/services/dispatcher/README.md` of the genixis repository.

Every leg runs unattended. No person answers a prompt. Stay inside the verbs of this
skill. When a command is denied or stops at a permission prompt, comment on your
entity that you are blocked, name the command, and stop. Do not try a second way
around the denial.

## The worker role

Your branch is `ai/issue-N`. Your entity is issue `N`.

1. Read the issue and every comment: `tea issues N --comments`. Read the `AGENTS.md`
   of the project before you change anything.
2. Work the issue on your branch. Make one topic per commit. Follow Conventional
   Commits. Run `nix fmt` before each commit, when the project is a Nix flake.
3. Gate yourself before the push, with the commands of the project. In genixis:
   `nix fmt -- --ci`, then `nix flake check --impure`. When the diff touches the Go
   module, also run `go test -C modules/programs/cli/project ./...`. Quote the
   outcome in your closing comment. When `go` is not on `PATH`, or the command is
   denied, write that in your closing comment and leave the run to CI.
4. Push the branch: `git push -u origin ai/issue-N`.
5. Open the pull request against the default branch with `tea pulls create`. Write
   the body to a file under `.scratch/` and pass it with `--description-file`. The
   subject line follows Conventional Commits.
6. Comment on the issue with the pull request number, what you verified, and what you
   could not verify. Stop after this comment.

The pull request body holds the owner brief (see below), one `Closes #N` line for the
issue, and the test evidence. The commit trailer names the executor.

A nudge leg is a worker leg that works on an open pull request. Three events start
one: a comment of a person on the pull request, a comment of a person on the gated
issue of its branch, and a red machine gate on its head. Your branch is the branch
of that pull request. Your entity is the pull request. Address the findings that
the pull request names, or the red gate. Push the branch. Never open a second pull
request for the branch. Comment on the pull request and stop.

## The reviewer role

Your branch is `ai/review-N`. Your entity is pull request `N`. You review the change,
you do not fix it.

1. Run `git pull --ff-only` first, so your worktree holds the tip of the pull request.
2. Read the pull request: `tea pulls N`. Read its comments: `tea comments list N`.
   Read its review comments: `tea pulls review-comments N`. Read the issue that the
   body names, with its comments.
3. Verify that the body names its issue with a closing keyword, for example
   `Closes #N`. State the result in your verdict.
4. Challenge the brief. Read the diff against each claim of the brief. Name every
   claim that the diff does not support, every machine decision that the brief omits,
   and every risk that the brief plays down.
5. Run the machine gate in your worktree. In genixis: `nix fmt -- --ci`, then
   `nix flake check --impure`. When the diff touches the forge hook, also run
   `python3 modules/programs/cli/claude/forge-hook-test.py`. Quote the outcome of
   each command in your verdict. When a command of the gate is not permitted to you,
   say so in the verdict instead of running it.
6. Score the five risk signals below. Each signal scores 0, 1, 2, or 3.
7. Read the entity again immediately before the verdict: the pull request, its
   comments, its review comments, and its issue. The worker leg can write its
   closing comment after your first read. Do not name a comment as missing when
   the entity holds the comment at that moment.
8. Comment your verdict on the pull request: the findings first, then the challenge
   of the brief, then the risk score with one line of reason per signal, then the
   verdict word alone on its line: `APPROVED` or `CHANGES`. Stop after this comment.

`APPROVED` means: the gate is green, the brief holds, and no finding blocks the merge.
`CHANGES` means: anything else. The owner merges; you never do.

## The owner brief

Every pull request that a worker leg opens carries an owner-oriented brief, written
for the owner, not for another agent. It has these parts:

1. **What changed.** One paragraph, in plain words.
2. **Why.** The reason, and the issue it solves.
3. **Alternatives rejected.** Each with one line of reason.
4. **Where the risk sits.** The parts that the owner should read twice.
5. **Machine decisions.** Every choice that the machine made where a person could
   have decided otherwise. A pull request where the machine chose the approach states
   that here. One pull request where the owner specified the work and the machine
   executed it needs only the commit trailer.
6. **Spine files.** Every file of the pull request that is security spine under
   standing principle 7 of the factory plan, named for line-by-line review.
7. **Test evidence.** The commands that ran and their outcome, including what was
   not verified.

## The five risk signals

Score each signal 0 to 3. The verdict carries the sum.

| Signal | 0 | 3 |
| --- | --- | --- |
| Security-surface touch | The diff touches no rule, no secret, and no boundary. | The diff changes the forge hook, an allowlist, the secrets topology, the dispatcher, or a sandbox setting. |
| Probe failure | Every gate command and probe ran and passed. | A gate command failed, was skipped, or could not run. |
| Session health | The worker leg hit no prompt and no denial. | The worker leg hit prompts, denials, or errors, or it stopped early. |
| Blast radius | One host rebuilds, no data moves. | Several hosts or homes rebuild, or data migrates. |
| First-time pattern | The repository knows this kind of change. | The repository sees this kind of change for the first time. |

## What a leg never does

- Never merge a pull request. Never close or reopen an entity.
- Never push to a trunk branch. Never force-push. Push only your own leg branch.
- Never add or remove a label, above all the gate label.
- Never run `project discard`. Never read a `.env` file.
- Never spawn a second agent on your worktree. Work alone on your branch.
