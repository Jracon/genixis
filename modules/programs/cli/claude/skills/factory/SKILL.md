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

One exception exists. A windowed leg runs watched: the owner answers each
permission prompt in the view window of the session. The prompt of a windowed leg
names the exception. The leg waits at a prompt and continues after the answer. A
denial still blocks the leg. The exception also rules the park (issue #505). A
windowed leg that meets a decision of a class that always parks asks its question
in the session. It waits for the typed answer of the owner and posts no park
comment while it waits. The answer continues the leg on the same branch, with no
new loop start. When the owner ends the session with no answer, the park comment
lands with the three parts of the park discipline.

The final comment of a leg can wake one other leg (issue #525). The word `/wake`
as the first word of the final comment of a leg wakes the continuation that the
dispatcher derives from the entity. Write the word only in two shapes: a reviewer
verdict with blocking findings wakes the worker continuation of that pull
request, and the final comment of a worker or nudge leg wakes the issue that a
`Refs` keyword of the pull request of its branch names. The wake carries no
payload and names no target. The loop bounds the agent wakes of one entity pair,
and a bound trip stops the thread until a person acts.

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
   decision. One standing record can carry this decision for a named scope of work.
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

The issue template seeds the section of the web form only. No template seeds an issue
that a leg files through `tea issues create`, so the filer seeds the section. A seeded
line is the empty `Readiness` line of the shape below. The line holds no answer text,
and the word `seeded` is not an answer. Write the six lines into the body of the issue,
filled or seeded, in this shape:

```
## Readiness

Readiness A:
Readiness B:
Readiness C:
Readiness D:
Readiness E:
Readiness F:
```

Fill each class that you can answer before you file the issue. A class that waits for
the owner keeps its seeded line. The readiness gate then parks the issue on the classes
that hold no answer, never on a missing section. When no answer of the owner sits on the
record, never name the owner as an answerer.

Class C holds one standing route. A standing record is one record of the register of the
project. In it, the owner dismissed the class once for a named scope of work. When the
scope of a standing record covers the filed work, fill class C from it. Name the owner
as the answerer and name the record, for example `Readiness C: not applicable by jracon,
standing record standing-basis-ruling`. A standing record counts as an answer of the
owner that sits on the record. Work outside the scope of the standing records keeps its
seeded line for class C.

The readiness gate of the dispatcher verifies the answers before a worker leg starts. An
issue that lacks an answer, or holds a not-applicable without its answerer, is parked:
the dispatcher posts one comment that names the classes, and no leg starts.

The charter layer: the product-level answers of a project live frozen in one document of
the project, its charter. An issue links to the charter for these answers instead of
restating them. The `diataxis` skill governs the form of the charter.

The spike class: a technically risky answer gets a timeboxed feasibility probe before the
plan of the issue freezes. The probe result lands in the answer of its class.

A produced project is any project that the factory serves besides the repository of the
factory itself. The class F answer of a produced project declares its authorship regime:
agent-built end to end, or the split between glue and novel work that the rules of the
project define.

## The quotes of a filed issue

Each quote of file content in the body of an issue names the read command that
produced it (issue #584). Before a leg files an issue, the leg verifies each quote
against the tree with a read command. A quote can be a path, a line, a title, or a
string. The command sits beside its quote in the body, so a reader reproduces the
quote with one run of the command.

A quote that the command output does not show does not enter the body. Text that the
filer derived from other text, for example a slug derived from a record title, is not
a quote. The body marks such text as derived, not as quoted.

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
3. A readiness answer that the run disproves. File an amendment, and stop (see The
   readiness amendment).
4. A merge that no brief and no rule of the project delegates to the leg.

Gate files, allowlists, and the forge hook are spine for review, even when a machine
wrote them. A pull request that touches one of them names it for line-by-line review.

## The merge policy

The owner merges into the protected branches: the default branch, a trunk branch, and
every branch that the forge protects. A leg never merges into a protected branch. Below
the protected branches, delegation is wide open (issue #350, decision D12): the brief of
an issue, or the rules of a project, may delegate a merge to a worker leg. A delegated
merge is an act of a worker leg under its brief. One merge needs no brief, because this
skill delegates it: the catch-up merge of the serving trunk into the branch of the
leg (issue #544, issue #571). The worker role names the serving trunk and states the
command shape. A merge that a leg cannot
conclude passes to a nudge leg, to a windowed leg, or to the owner. A reviewer leg
never merges. The `forgejo` skill states the merge forms that the forge hook answers
for, and the conditions of each form.

## The park

A park is the stop of a leg on one question. The leg posts one comment on its entity and
stops work. The comment holds three parts:

1. One precise question. Name the options when they are discrete.
2. The blocked step: the work that waits for the answer.
3. What the leg verified before the park, so the answer needs no new investigation.

Do not hide a decision inside a question. A question that changes no step of the work is
no park: continue the work, and name the question in the closing comment. The readiness
gate of the dispatcher parks an unready issue with the same three parts.

## The readiness amendment

A leg that disproves a readiness answer mid-run files an amendment. The amendment flow has
three steps:

1. The leg parks: one comment names the disproved answer, the evidence of the run, and the
   proposed amendment.
2. The owner answers the park with one comment: an approval, or a rejection with a reason.
3. The approved answer replaces its Readiness line in the body of the issue, and the forge
   versions the body. The leg that the approval comment starts applies the edit when the
   login of the session owns the issue. Otherwise the owner applies the edit first.

An amendment changes an answer, never a scope or an acceptance criterion: those stay with
the owner on the issue.

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

A hand-spawned leg receives the same payload. The spawner prints the prompt with
`dispatcher.py prompt <role> <entity>` of the genixis repository (issue #388). The
command renders the entity payload, names the time of the read, and starts no leg.
The spawner passes the printed text to `project spawn`.

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

Your branch is `ai/issue-N`. Your entity is issue `N`. The serving trunk of your leg
is the branch that the steps below start from, open into, and merge from: the default
branch of the project, or the trunk that your brief names when it differs.

1. Read the entity: the payload of your prompt when it carries one, else the issue
   and every comment with `tea issues N --comments`. Read the `AGENTS.md`
   of the project before you change anything.
2. Work the issue on your branch. Make one topic per commit. Follow Conventional
   Commits. Run `nix fmt` before each commit, when the project is a Nix flake.
3. Gate yourself after your last commit and before the push, with the commands of the
   project. Run the gate only on a clean worktree (`git status --short
   --untracked-files=no` prints no row). A run on a dirty worktree tests content that
   the push does not carry, so its outcome binds no head. In genixis:
   `nix fmt -- --ci`, then `nix flake check --impure`, then
   `bash .forgejo/scripts/check-commit-subjects.sh origin/main..HEAD`. The
   range names `origin/main`, because the local `main` of the clone can
   sit behind the merges of the forge. When the diff touches
   the Go module, also run `go test -C modules/programs/cli/project ./...`. Quote the
   outcome in your closing comment. When `go` is not on `PATH`, or the command is
   denied, write that in your closing comment and leave the run to CI.
4. Bring your branch level with the serving trunk before the push. Run
   `git fetch origin`. Run `git merge --no-ff origin/main -m "chore: merge
   origin/main into ai/issue-N"`. Put the name of the serving trunk of your leg
   in the place of `main`, in the ref and in the message. An allow rule of
   the user layer covers each command that
   starts with `git merge --no-ff`, and no rule covers another shape of the merge.
   When the merge reports a conflict, resolve each conflict on your branch. Stage
   each resolved file with `git add`, and conclude the merge with
   `git commit --no-edit`. When the merge creates a merge commit, gate yourself
   again on the merged head, with the commands of step 3. When the merge does not
   conclude, continue with the steps below. Name the catch-up merge as the blocked
   step in your closing comment. The closing comment is the blocked comment of the
   stop rule at the top of this skill. A nudge leg, a windowed leg, or the owner
   can take the merge.
5. Push the branch: `git push -u origin ai/issue-N`.
6. Open the pull request against the serving trunk with `tea pulls create`. Pass
   `--base <trunk>` when the serving trunk is not the default branch. Write
   the body to a file under `.scratch/` and pass it with `--description-file`. The
   subject line follows Conventional Commits.
7. Before a final comment that begins with `/wake`, post one context comment
   on the target issue of the handoff. The `Refs` keyword of your pull request
   names the target issue. The comment names the blocking relation and the
   entity that waits. One example body: issue N waits for this issue, and the
   open pull request of branch `ai/issue-N` names this issue with `Refs`. The
   context comment does not begin with `/wake`, so it wakes nothing. The
   prompt of the woken leg holds the body and the comments of its own issue,
   so the context comment reaches that prompt. The wake signal stays
   payload-free.
8. Comment on the issue with the pull request number, what you verified, and what you
   could not verify. Begin this comment with `/wake` only when your pull request
   names the next issue of the flow with a `Refs` keyword and that issue must run
   next. Stop after this comment.

Every risk, every not-verified item, and every deferral of your brief names its
disposition: fixed in the diff, a tracker issue that you open, or an accepted
reason on the record. A finding outside the scope of your entity becomes a
tracker issue that you open, not only a closing comment. A finding with a
structural cause becomes a tracker issue that you open mid-run, under a rule
outside this skill. Write the six lines into the body of each issue that you
open, filled or seeded (see The readiness protocol and The quotes of a filed issue).

The pull request body holds the owner brief (see below), one `Closes #N` line for the
issue, and the test evidence. The commit trailer names the executor.

A nudge leg is a worker leg that works on an open pull request. Four events start
one: a command comment (`/loop` or `/watch`) of a person on the pull request or on
the issue of its branch, a plain comment of a person on an entity that holds the
`needs-owner` label, a red machine gate on its head, and the `/wake` of a reviewer
verdict on the pull request. A plain comment starts nothing else. Your branch is
the branch
of that pull request. Your entity is the pull request. Address the blocking
findings by name, or address the red gate. Bring the branch of the pull request
level with the serving trunk, with step 4 of the worker role. A catch-up merge
that a closing comment names as a blocked step is a blocking finding: address it by
name. Push the branch. Never open a second pull request for the branch. Before
a final comment that begins with `/wake`, post the context comment of step 7
of the worker role. Comment on
the pull request. Begin the final comment with `/wake` only when the pull request
names the next issue of the flow with a `Refs` keyword and that issue must run
next. Stop after this comment.

## The reviewer role

Your branch is `ai/review-N`. Your entity is pull request `N`. You review the change,
you do not fix it.

1. Hold the tip of the pull request in your worktree before you read the entity.
   Run `git fetch origin`, then compare the outputs of `git rev-parse HEAD` and
   `git rev-parse @{u}`. When the two commands print the same commit, pull nothing.
   When they print different commits, run `git pull --ff-only`. Pull only in that
   case. A branch that moves allow rules into the user layer removes the pull rule
   from the project allowlist. The host gains the moved rule only at its next home
   switch, so a pull inside that window can stop at a denial (issue #515).
2. Read the entity: the payload of your prompt when it carries one, else the pull
   request with `tea pulls N`, its comments with `tea comments list N`, its review
   comments with `tea pulls review-comments N`, and the issue that its body names,
   with its comments.
3. Verify that the body names its issue with a closing keyword, for example
   `Closes #N`. A pull request of a composition flow names its issue with `Refs #N`
   instead, and its body holds no closing keyword for that issue. State the result in
   your verdict.
4. Challenge the brief. Read the diff at the merge base of the pull request, for
   example with the three-dot form `git diff origin/main...HEAD`. The example
   holds for a pull request whose base branch is `main`. When the base branch is
   not `main`, put it in the place of `main` in the form. Do not read the diff
   against the tip of the base branch. When the base branch moved after the
   branch started, a diff against its tip inverts each change that the base
   branch gained. Read the diff against each claim of the brief. Before a change
   that the brief does not
   name becomes a finding, confirm that the merge-base diff shows it. Name every
   claim that the diff does not support, every machine decision that the brief
   omits, and every risk that the brief plays down. When the change replaces one
   tool with another, examine what depends on the old tool. Name everything that
   the diff ports from it. Mark each item that the new tool makes unnecessary.
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
   verdict word alone on its line: `APPROVED` or `CHANGES`. Begin the comment with
   `/wake` when the verdict is `CHANGES`: the word wakes the worker continuation of
   this pull request under the bound of the loop. Begin no approved verdict with
   `/wake`. Stop after this comment.

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
this duty. Open each issue in the same verdict pass. Write the six lines into
the body of each issue that you open, filled or seeded (see The readiness
protocol and The quotes of a filed issue). The issue body names the source pull
request, the finding, and the acceptance criteria. The verdict cites each issue number.

A nudge leg addresses the blocking findings by name, so the blocking decoration
also drives the nudge path.

`APPROVED` means: the gate is green, the brief holds, and no finding blocks the merge.
`CHANGES` means: anything else. The owner merges into the protected branches. A reviewer
leg never merges.

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

## The campaign close record

A campaign closes with one record on its tracking issue. The record derives from the
forge: the loop writes no second record and creates no new standing state (issue #350,
decisions D11 and D13).

1. The intervention analysis reads the history of the issues and the pull requests of
   the campaign: every park, every answer, every reversal, and every reopened pull
   request. The content of each stop outranks the count (D11).
2. The analysis separates park stops from crash stops. A park stop is a decision that
   waited for the owner. A crash stop is an infrastructure fault: a denied command, a
   dead host, or a lost session. The two classes have different cures.
3. The record names each class that caused a stop, and the fix that removes the class.
   The lean claim reads at close: every stop of the campaign traces to a named
   ambiguity class or a named infrastructure fault.
4. The cost telemetry reads the token cost per leg per phase from the transcripts of the
   harness under `~/.claude/projects`. The analysis maps each turn to the phase of the
   leg that wrote it. The line format of a transcript is internal to the harness, so the
   analysis names the harness version that it read. The loop records no cost of its own.

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

- Never merge into a protected branch. Never merge without a delegation of a brief or of
  the rules of the project (see The merge policy). Never close or reopen an entity.
- Never push to a trunk branch. Never force-push. Push only your own leg branch.
- Never add or remove a label. The dispatcher alone sets and clears the
  `needs-owner` label.
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
