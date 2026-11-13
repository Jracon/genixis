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

When the denial text of the harness suggests other tools for the same goal, do not
follow that suggestion. The suggestion does not apply to a leg. The owner learns a
missing allow rule from the blocked comment of a leg.

Write each command so that an allow rule can match it. The permission check reads a
`|` in a search pattern as a pipe, also when the pattern sits in quotes. No allow rule
covers such a command. Search for one name in each command, not a set of alternatives.

Run one plain command in each shell call. Do not use a pipe, a chain, a loop, a command
substitution, or a shell variable. The forge hook denies a compound command in a session
of `project spawn`, and each deny costs one round trip.

A probe prompt names an output path under `.scratch/`, so no probe output lands in the
tracked tree.

## The readiness protocol

A leg runs unattended, so the brief of its issue resolves each ambiguity before the leg
starts. The brief answers six classes of questions. Each class holds one answer, or one
explicit not-applicable. The classes are:

1. Class A, reference and product: the exact reference of the work, the first milestone,
   and the subsystems in scope and out of scope.
2. Class B, oracle: the outputs that a correctness claim binds to, the oracle build with
   its flags, the platform, and the corpus with its success bar.
3. Class C, basis: the provenance and the legal basis of the work, for example clean-room
   work or readable sources, and the policy for copyrighted assets. The owner takes this
   decision.
4. Class D, materials: the inputs that the owner supplies, hash-pinned, and the hardware
   of the runners.
5. Class E, build rules: the dependency policy, the determinism strategy, and the
   performance floor.
6. Class F, loop contract: the authorship regime, the merge delegation below protected
   branches, the budgets and stop rules, the decision catalog, and the reporting cadence.

The answers live in the body of the issue, one line per class. A line holds the word
`Readiness`, the class letter, a colon, and the answer, for example `Readiness A: the
reference is release 1.21`. A not-applicable line names the login that answered it, for
example `Readiness C: not applicable by jracon`. The answerer of a not-applicable is part
of the record, because a later audit reads who dismissed the class.

The readiness gate of the dispatcher verifies the answers before a worker leg starts. An
issue that lacks an answer, or holds a not-applicable without its answerer, is parked:
the dispatcher posts one comment that names the classes, and no leg starts.

The charter layer: the product-level answers of a project live frozen in one document of
the project, its charter. An issue links to the charter for these answers instead of
restating them. The `diataxis` skill governs the form of the charter.

The spike class: a technically risky answer gets a timeboxed feasibility probe before the
plan of the issue freezes. The probe result lands in the answer of its class.

## The decision catalog

Machines execute and record. They do not decide (issue #350, principle 2). This catalog
names the decision classes that a leg may take alone, and the classes that always park.

A leg takes these classes alone, inside a brief that covers the work:

1. The mechanical shape of the named work: the placement of the files, the names, the
   order of the commits, and the formatting.
2. The choice between equivalent implementations, when each closes the same gap and
   passes the same gate.
3. The verification inside the gate of the project: which allowed command runs, and in
   which order.
4. The wording of comments, commit messages, and the pull request body, inside the
   writing rules of the project.

A leg always parks on these classes:

1. A decision that no readiness answer, no rule of the project, and no skill covers.
2. A workaround that outlives the leg. The owner takes the verdict, and the record
   lives with the concept that it serves.
3. A readiness answer that the run disproves. File an amendment on the entity, and
   stop.
4. A merge that no brief and no rule of the project delegates to the leg.

Gate files, allowlists, and the forge hook are spine for review, even when a machine
wrote them. A pull request that touches one of them names it for line-by-line review.

## The entity payload of a prompt

The prompt of a leg can carry the entity payload (issue #311). The payload holds the
reads of the entity of the leg, and it names the time of the read. A worker leg gets
its issue with its comments. A nudge or reviewer leg gets the pull request, its
comments, its review comments, and the linked issue with its comments when the prompt
names it.

The payload is the first entity read of the leg. Skip the `tea` read of each part that
it holds. Re-read a part with its `tea` command when you need a state newer than the
named time. A prompt that carries no payload names no read time. Read the entity with
the `tea` commands of your role. The reads of a reviewer immediately before its
verdict are re-reads in every case, whatever the payload holds.

## The forge commands of a leg

The forge hook answers for each `tea`, `gh`, and `git push` command. In a headless
session, it turns every ask answer into a deny, and that deny tells the leg to report on
its entity and stop. Run only the forms below. The `forgejo` skill holds the full verb
tables and the conditions behind them.

Forms that run with no prompt:

1. The read verbs of `tea` in the working repository: `tea issues`, `tea issues <n>`,
   `tea pulls`, `tea pulls <n>`, `tea pulls review-comments <n>`, `tea comments list
   <n>`, `tea labels list`, and `tea whoami`.
2. The write verbs of `tea` in the working repository: `tea comments add <n> <body>`,
   `tea comments <n> <body>`, and `tea issues create` and `tea pulls create` with
   `--description-file` under `.scratch/`. The form `tea issues create --repo
   jracon/genixis` runs in every project.
3. An edit of the title or the body of an entity that the login of the session wrote.
   The `forgejo` skill states the exact options.
4. The read verbs of `gh`: `gh issue list`, `gh issue status`, `gh issue view`,
   `gh pr checks`, `gh pr diff`, `gh pr list`, `gh pr status`, and `gh pr view`.
5. A `tea` or `gh` command that ends in `--help`, when only words stand before it.
6. `git push -u origin <branch>`, for a branch of your own.

Forms that stop a headless leg. Never run them:

1. `tea issues close`, `tea issues reopen`, `tea pulls close`, `tea pulls reopen`,
   `tea comments edit`, `tea labels update`, `tea labels delete`, `tea pulls merge`,
   and each edit of an entity outside the third form above.
2. A `tea` command with `--login`, `--owner`, `--org`, `--remote`, `-R`, or `-l`, or
   with a repository flag that names another repository.
3. A command with `$`, a backtick, or a command substitution anywhere in it, also in
   the text of a title or a body.
4. A `tea`, `gh`, or `git push` command inside another command, for example `bash -c`,
   `env`, `sudo`, `nix`, `timeout`, or `xargs`.
5. A push to a branch that is the projectBase of another branch. Push no form other
   than the one above.

When your entity needs one of these forms, state that in your closing comment and
leave the step to the owner.

## The worker role

Your branch is `ai/issue-N`. Your entity is issue `N`.

1. Read the entity: the payload of your prompt when it carries one, else the issue
   and every comment with `tea issues N --comments`. Read the `AGENTS.md`
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

Every risk, every not-verified item, and every deferral of your brief names its
disposition: fixed in the diff, a tracker issue that you open, or an accepted
reason on the record. A finding outside the scope of your entity becomes a
tracker issue that you open, not only a closing comment.

The pull request body holds the owner brief (see below), one `Closes #N` line for the
issue, and the test evidence. The commit trailer names the executor.

A nudge leg is a worker leg that works on an open pull request. Three events start
one: a comment of a person on the pull request, a comment of a person on the gated
issue of its branch, and a red machine gate on its head. Your branch is the branch
of that pull request. Your entity is the pull request. Address the blocking
findings by name, or address the red gate. Push the branch. Never open a second
pull request for the branch. Comment on the pull request and stop.

## The reviewer role

Your branch is `ai/review-N`. Your entity is pull request `N`. You review the change,
you do not fix it.

1. Run `git pull --ff-only` first, so your worktree holds the tip of the pull request.
2. Read the entity: the payload of your prompt when it carries one, else the pull
   request with `tea pulls N`, its comments with `tea comments list N`, its review
   comments with `tea pulls review-comments N`, and the issue that its body names,
   with its comments.
3. Verify that the body names its issue with a closing keyword, for example
   `Closes #N`. State the result in your verdict.
4. Challenge the brief. Read the diff against each claim of the brief. Name every
   claim that the diff does not support, every machine decision that the brief omits,
   and every risk that the brief plays down. When the change replaces one tool with
   another, examine what depends on the old tool. Name everything that the diff
   ports from it. Mark each item that the new tool makes unnecessary.
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

Write each finding of the verdict as one line. The line holds one label, one
decoration in parentheses, a colon, and the finding. One example line is:
`issue (blocking): The gate did not run.` The labels are `issue`, `suggestion`,
`question`, `todo`, `praise`, and `note`. The decorations are `blocking` and
`non-blocking`. The labels and the decorations come from Conventional Comments
(conventionalcomments.org).

A blocking finding carries one disposition before the owner merges: fixed on the
branch, rejected with a reason, or a tracker issue that exists and is open. A
blocking finding with no disposition keeps the verdict at `CHANGES`. A
non-blocking finding needs no disposition. A rejection is valid only when no
defect survives the merge: the finding is a misread, a duplicate, or a declined
preference. The verdict states which one holds.

Open one tracker issue for each finding that names a defect which survives the
merge. The decoration of the finding, blocking or non-blocking, does not change
this duty. Open each issue in the same verdict pass. The issue body names the
source pull request, the finding, and the acceptance criteria. The verdict cites
each issue number.

A nudge leg addresses the blocking findings by name, so the blocking decoration
also drives the nudge path.

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
- Never spawn an agent that writes. Work alone on your branch.

A leg may spawn read-only subagents inside its worktree. The permission has these
conditions:

1. Give the subagent search work and read work only.
2. The subagent edits no file. It commits nothing. It pushes nothing.
3. The subagent spawns no other subagent.
4. Spawn no more than three subagents at the same time. Subagents that run at the
   same time add load to the host. Thirteen sessions at the same time froze the
   host (issue #267).
