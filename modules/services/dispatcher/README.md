# The dispatcher of the factory loop

The receiver and the dispatcher of phase 4 (issue #74, issue #83) run on `services`
as systemd user services of the `dev` user. The receiver takes the webhook deliveries
of the forge. The dispatcher turns each accepted delivery into one agent leg, through
the same `project spawn --headless` command that the owner could type. Nothing in this
directory runs as root. The long reference for the roles that the legs follow is the
`factory` skill (`modules/programs/cli/claude/skills/factory/SKILL.md`).

## Files

| File | Purpose |
| --- | --- |
| `dispatcher.py` | One program with five entry points: `serve` (the receiver), `run` (one spool pass), `poll` (the tea fallback), `prompt` (print the brief of one leg, and start no leg), `release` (free the in-flight entry of one branch, and start no leg). |
| `dispatcher-test.py` | The stub harness of the program: stub `project`, `tea`, `git`, `systemd-run`, `systemctl`, and `claude` binaries in a temporary state directory. The CI of a pull request runs it. |
| `leg-run.py` | The request executor of the leg template of the sandbox tier: reads the request file of the leg state and execs its argv with its env as the user the template names. |
| `sandbox-probe.py` | The probe harness of the sandbox tier of issue 555: one probe per control, run live on `services` inside a session. The CI of a pull request runs the static checks of the file and no live probe. |
| `dispatcher.nix` | The secret declaration, the linger of `dev`, and the user services with the gate environment of a leg. Loads only on the `services` host. |
| `webhook.age` | The shared secret of the webhook. The owner creates it with `agenix -e`. The module stays off until the file exists. |

## State

All state lives in `~/.local/state/dispatcher` of `dev`. Standing principle 6 of
issue #74 adds it to the backup set.

| File | Content |
| --- | --- |
| `events/` | Accepted deliveries that wait for a spawn. One JSON file per delivery, named after the delivery ID. |
| `processed/` | Deliveries that a spawn consumed or that a pending event superseded. A superseded record names the pending delivery in its `superseded_by` field (issue #665). Pruned after 14 days. The file name is the delivery record. |
| `failed/` | Deliveries whose leg failed after every retry. |
| `inflight.json` | The in-flight map: branch to session name, session id, entity, the windowed mark of its leg, start time, the deliveries that arrived while the branch was blocked and were superseded, and under the sandbox tier the config directory and the template instances of the leg. |
| `links.json` | The pull request to issue links, read from the closing keyword or the `Refs` keyword of each pull request body. |
| `sessions.json` | The session record of the branches: branch to the latest transcript UUID of its leg, the worktree it runs in, whether a windowed leg holds it, and under the sandbox tier the config directory that holds the transcript. The record survives the release of the in-flight entry, so a later worker or nudge leg of the branch resumes the session (issue #524). |
| `poll-cursor.json` | The cursor of the poll fallback: the newest comment id of each issue and of each open `ai/` pull request, the pull requests it already queued, and, per pull request, the last CI status with its head commit that it saw. |
| `redgate.json` | The bound of the red gate: per pull request, how many nudge legs a red gate started, which head commit got the last one, and whether the dispatcher already told the owner. |
| `wakegate.json` | The bound of the wake: per entity pair, how many agent wakes the pair queued, and whether the dispatcher already told the owner. |
| `breedgate.json` | The bound of the agent-chained starts (issue 631, stage 2): per entity, how many ruled transitions fired, and whether the dispatcher already told the owner. |
| `wakehold.json` | The parked entries of the dead-session release (issue #612): one record per freed entry, with its entity, its branch, the entry itself, and the time of the release. The record answers the wake rule of a final comment that the forge delivers after the release, and it lives no longer than `DISPATCHER_WAKE_HOLD` (default 10 minutes). |
| `stopfail.json` | The released sessions whose stop failed (issue #696): per entity, one record per session, with the session id, the branch, the reason of the failed stop, and the time of it. A comment of the agent login that releases in-flight entries of the entity inside the window posts one comment that names the exception, and a record older than `DISPATCHER_STOPFAIL_HOLD` (default 2 hours) answers nothing. |
| `pace.json` | The pace of the spawns: the time of the last spawn attempt. One sweep pass starts one leg at most, and a pass inside the spacing of the last start starts none. |
| `sweep.lock` | The lock that keeps one sweep at a time. |

## Event rules

The receiver verifies the HMAC-SHA256 signature of each delivery against the secret,
then applies these rules. Every rejected or ignored event still answers 200, so the
forge does not retry it. Only a delivery with a wrong signature gets 403.

| Event | Rule | Result |
| --- | --- | --- |
| `ping` | Always. | Ignored. |
| any | `repository.full_name` of the payload, or of its `run` object, is not `jracon/genixis`. | Ignored. |
| `issue_comment` | The sender is the agent login `claude-bot`. | The in-flight entries of the entity are released, and the sessions of their legs stop. A comment that releases an entry may begin with `/wake` (see The wake rule and its bound); every other agent comment starts nothing. A comment that begins with the research mark frees the research entries of the entity alone and starts the adversarial review of a freed research entry inside the breed bound (issue 631, stage 2, see The chained starts and their bound). The stall report of a stalled leg releases nothing (issue #665): it names the block of the predecessor, and the same pass spawns the replacement leg of the entity. A stop-failure report releases nothing either (issue #696): it names a session that a release could not stop, and the successor leg of that session may hold the slot when the delivery arrives. This is the self-trigger rule, narrowed by issue #525 and extended by the ruled list of stage 2. |
| `issue_comment` | The issue is closed. | Ignored. |
| `issue_comment` | An open issue, and a comment of a person whose first word is `/loop` or `/watch`. The prose of the answer may sit on the same line, on later lines, or nowhere. The command `/watch` starts the windowed variant (see The windowed route of allowlist work). The branch of the issue holds no open pull request. The readiness gate passes. | Worker leg on `ai/issue-N`. A class that the gate finds unanswered parks the issue, and no leg starts. |
| `issue_comment` | The same, and the branch of the issue holds an open pull request. | Nudge leg on that pull request. The worker prompt would tell the leg to open a second pull request, and the forge refuses that. |
| `issue_comment` | An open issue that holds the `needs-owner` label, and a plain comment of a person: the loop stopped the thread, and the prose continues it (issue #525). | Worker leg, or nudge leg by the branch state, through the same branch-state rule as a command comment. The same comment resets the wake bound and removes the label. |
| `issue_comment` | An open issue that holds the ask status, and a plain comment of a person: the prose is the answer that the ask status names (issue 631, machine decision 36). | Refinement continuation leg on `ai/issue-N`, with a cause that names the answers of the thread. An issue that holds both the `needs-owner` mark and a status routes through the row above. |
| `issue_comment` | A pull request whose head branch starts with `ai/`, and a comment of a person whose first word is `/loop` or `/watch`. The command `/watch` starts the windowed variant (see The windowed route of allowlist work). | Nudge leg on the head branch: a worker leg that continues the work of that pull request. The head comes from one `tea pulls` read. The variant of the comment starts the nudge leg in the windowed shape. |
| `issue_comment` | A pull request whose head branch starts with `ai/`, that holds the `needs-owner` label, and a plain comment of a person. | Nudge leg on the head branch, with a cause that names the stop. The same comment resets the wake bound and removes the label. |
| `issue_comment` | A plain comment of a person on any other entity. | Ignored. Plain prose starts nothing (issue #525); the commands, the status edges, the answer of the ask status, and the `needs-owner` label carry every start. |
| any | A label action (`label_updated`, `label_cleared`) of the issues shape on an open issue, and the sender is a person. The rule keys on the payload shape, not the event header (machine decision 34), and the diff of the label state of the payload against the recorded state yields a new status edge (see The status labels and the refinement role). | The leg that the edge names: the rough status starts the refinement leg on any issue content, and the ready status takes the command-comment path, whose gate parks an issue whose brief answers no class. The person-set change is the human act that resets the wake bounds and the breed bound of every pair that names the issue, the same reset that a human comment carries (stage 2). |
| any | The same, and the sender is the agent login. | Ignored, with one ruled exception (issue 631, stage 2): the diff shows the ask status gone and no new edge, the clear that the refinement continuation writes when its report names the brief final, and the ruled chain starts inside the breed bound (see The chained starts and their bound). The label state is recorded for the diff either way. |
| any | A label action of the issues shape on a closed issue, any other action or shape, or a diff that yields no new status edge. | Ignored. |
| `pull_request` | `opened` or `synchronized`, head branch starts with `ai/`. | Reviewer leg on `ai/review-N`. |
| `pull_request` | `closed`, head branch starts with `ai/`. | The in-flight entries of both legs of the pull request are released. The red-gate bound of the pull request ends, and the wake bounds of every pair that names it reset. The `needs-owner` mark comes off the pull request when it holds one, through one label read (issue #582). No spawn. |
| `pull_request` | Any other action or head branch. | Ignored. |
| `status` | The state is `failure` and the commit is the head of an open `ai/` pull request. | One nudge leg on that pull request, under the red-gate bound below. |
| `status` | The state is `success` on the same head. | The red-gate bound of that pull request ends. No spawn. |
| `status` | Any other state, or a commit that no open `ai/` pull request holds as its head. | Ignored. |
| `run_completed` | The `run.status` is `failure` and the run names an open `ai/` pull request: `run.prettyref` names its number or its branch, or, when the payload names neither, `run.commit_sha` is the head of one. | One nudge leg on that pull request, under the red-gate bound below. |
| `run_completed` | The `run.status` is `success` on a run that names the same pull request. | The red-gate bound of that pull request ends. No spawn. |
| `run_completed` | Any other `run.status`, or a run that no open `ai/` pull request answers. | Ignored. |

## The readiness gate

A worker leg starts only on an issue whose brief is ready (issue #356, L2; decision D10
of issue #350). The readiness protocol of the factory skill names six ambiguity classes,
A to F. Each class holds one answer, or one not-applicable that names the login that
answered it (L12: the gate records who answered, and the body of the issue is the
record). The answers live in the body of the issue, one plain line per class:
`Readiness <letter>: <answer>`. The issue template seeds the section of the web form.
The filing rule of the factory skill seeds it in each issue that a leg files through tea.
A match stops at the end of its own line, so an empty `Readiness` line counts as its own
unanswered class and captures no text of the line below it (issue #409). A whole answer
of the word `seeded` counts as no answer, because the word names the seeded empty line
of the protocol (issue #566).

The gate runs inside `queue_gated_issue`, before the worker event is queued, so the
webhook path and the poll fallback share it. It reads the body of the issue with one
`tea` call. A nudge leg, a reviewer leg, and a red-gate nudge run no gate: they continue
work that a ready brief started.

1. An issue that answers every class queues the worker leg.
2. An issue with a missing class, or with a not-applicable that names no answerer, is
   parked. The park comment names each unanswered class with its reason, asks one
   question, and names the blocked step. No event is queued, and the delivery is
   answered. The park sets the ask status `status/needs-input`, so the board names the
   wait. A plain answer of a person on the parked issue starts the refinement
   continuation, which folds the answers into the body of the issue (see The status
   labels and the refinement role). A re-set of the ready status, or a new `/loop`
   comment on the issue, requeues the leg, so the gate runs again after the owner edits
   the body.
3. A read that fails fails open, like every `tea` read of the receiver. The gate logs a
   warning, the leg starts, and the gate runs again on the next trigger. A payload
   fetch that fails too sends the leg to read the issue itself.
4. The park comment comes from the agent login, so the self-trigger rule treats it as a
   release of the entity, never as a trigger. The wake rule agrees: a park comment
   releases no in-flight entry, so it wakes nothing. The label write of the park is a
   change of the agent login too, and the ask status that the park sets is no edge
   label, so it starts nothing on both paths: the ruled clear of stage 2 names the
   final report of a continuation, and the park writes the ask, never the clear.

The gate writes no state of its own beyond the ask status of the park (decision D13):
the park is a comment, the answers are the body of the issue, and no second record of
the answers exists. The ask status records no answer; it names the wait, like the
`needs-owner` label names a stopped thread. Campaign A of issue #350 reads
the not-applicable lines for abuse.

## The status labels and the refinement role

The status family (issue 631) is the second human surface of the loop beside the
commands. The forge holds the labels `status/needs-spec` (the rough status),
`status/needs-input` (the ask status), `status/agent-ready` (ready),
`status/needs-review` (the report of an open pull request), and `status/verified` (the
human-only confirmation). The labels sit in the exclusive `status/` scope, so the forge
replaces one label of the scope with the next one that a person adds, and an issue
holds at most one status label; the owner verifies that replacement on a test issue
before the re-set protocol of this section runs (machine decision 35). The
`needs-owner`
label sits outside the scope, so a stopped thread keeps its status. The git config key
`forge.humanLabels` of the repository names `status/needs-spec`, `status/agent-ready`,
and `status/verified`, so the forge hook denies every agent command that names one of
them; `status/needs-input` and `status/needs-review` stay outside the key, so a leg
writes each with `tea issues edit <n> --add-labels <name>` and no prompt. The owner
creates
the labels on the forge, sets the key, and ticks the label events of the issue events
on the webhook page; until the ticks exist, the poll fallback carries the edges alone.

A person sets a status; the change is an edge. The rough status starts the refinement
leg on any issue content, and no readiness check runs for that spawn; the gate keeps
its place before every worker start, whatever the label says (issue #356, L2). The
ready status runs the same path as a `/loop` comment: the branch-state rule picks the
worker or the nudge, and the readiness gate runs before the worker event is queued.
The ask status, the report label, and `status/verified` trigger nothing as a set. The
write of the report label
replaces the status that the issue holds through the exclusivity of the scope, so
the report of an open pull request ends the state before it. A label change of the
agent login starts no leg, with one ruled exception (stage 2): the webhook path
filters the deliveries of the agent login and routes the cleared ask status below,
and the poll path needs no filter for the edges, because the only edge labels are
human-only in the key.

The ask status names a wait for a human answer. Three writers set it: the refinement
leg writes it when its report asks at least one question, the readiness park sets it
beside the park comment, and the mid-run park of a worker leg writes it beside its
park comment (stage 2, entry 4 of the ruled list), so the plain answer of a person
resumes every park of an issue through the refinement continuation with no command.
The answer of the person is prose on the thread, and that
prose is an edge: a plain comment of a person on an open issue that holds the ask
status starts the refinement continuation, which folds the answers of the thread into
the brief, then either asks its next question and writes the ask status again, or
reports the brief final and clears the ask status, so the board names no wait that
ended (machine decision 36). A re-set of the rough status runs a refinement
continuation after an ask as well, and a re-set of the ready status requeues a parked
issue. A
re-set is one add, because the exclusivity of the scope replaces the ask status with
the status that the person adds; when the forge holds two status labels, the re-set is
a removal and then the add.

The cleared ask status is an edge itself (stage 2, entry 2 of the ruled list): the
continuation that reports the brief final writes the clear, and the dispatcher takes
the next stage from it, with no human act between the refinement and the
implementation. Inside the breed bound, the ruled chain runs: the dispatcher writes
the ready status itself, through the tea login that no hook governs, so the
human-only name stays in `forge.humanLabels` and every leg keeps its denial; the
research leg starts on the research branch of the issue, `ai/research-N`, beside the
worker branch, because the owner ruled no hard gate sits before the worker, so the
research record and the implementation run in parallel; and the ready path runs,
whose readiness gate parks an issue whose brief answers no class, whatever the
continuation reported. The record of the label state follows the ready write, so the
diff of the poll path reads no new edge in the write of the dispatcher: the poll
cannot see the author of a change, and without the record it would route the write as
the person-set ready edge. A person that clears the ask status by hand, with no add,
fires the chain on the poll path alone: the poll reads no author, the webhook path
sees the sender and ignores the change, and the deviation sits on the record of the
register. A re-set that adds a status routes its edge alone on both paths, because
the diff that shows the ask clear together with a new edge belongs to the re-set,
not to the continuation.

The receiver derives each edge from the label state of the payload against the state
that `labels.json` records for the issue, and the poll fallback runs the same diff
over the label state of the detail read that it already makes, so both paths start the
same legs from the same edges and share one state. A first label delivery for an issue
routes the edges that its state carries, because the forge fired the delivery for a
change; the first sighting of an issue in the poll records its labels as the baseline
and queues nothing, the same rule as the comments. A status set while the issue is
closed starts nothing and records no state, so a re-opened issue takes the baseline of
the poll again.

The refinement leg works the brief of the issue on branch `ai/issue-N`. It drafts one
Readiness line per class, fills each class that the content answers, edits the body of
the issue when the login of the session owns it, and posts one comment that holds the
filled classes, one precise question per class that waits for the owner, the blocked
step, and what it verified. When that comment asks at least one question, the leg
writes the ask status `status/needs-input` on the issue with
`tea issues edit <n> --add-labels status/needs-input`. It writes no code: no commit, no
push, and no pull
request. The owner answers on the thread: a plain answer on an issue that holds the ask
status starts the refinement continuation on the recorded session, which folds the
answers into the brief and either asks again or names the brief final and clears the
ask status. The owner also runs the next stage by hand: a re-set of the rough status
runs a refinement continuation on the recorded session, and the ready status or
`/loop` runs the gate and the
worker. The hand prompt is
`dispatcher.py prompt refinement <issue>`, and the spawn of the leg names the verified
trunk like a worker spawn (machine decision 34).

## The windowed route of allowlist work

The harness gates each edit of a settings file above the allow rules. No allow rule
answers that gate. A leg in dontAsk mode gets a denial for the edit, so an unattended
leg cannot apply an allowlist entry that an issue rules (issue #470).

The owner ruled the windowed route (option C of issue #470). The dispatcher starts
allowlist work as a leg that the owner watches. One person answers the one consent
prompt of the settings-file edit.

The trigger is the watch command, `/watch`: the first word of the comment, its own
command since the split of issue #525. The owner writes `/watch` on the issue,
or in a comment on the open pull request of the branch (issue #516). The prose of the
ruling may sit behind the word, on the same line or on later lines. A command of the
loop takes no word arguments, and every variant is its own command, so the word
`window` behind `/loop` is prose: `/loop window` starts a plain leg.

The command starts the worker leg of the issue in the windowed shape. When the branch
already holds an open pull request, it starts the nudge leg of that pull request in
the same shape. A `/watch` comment on an open pull request whose head branch
starts with `ai/` starts the nudge leg of that pull request in the same shape. The
shape has these properties:

1. The spawn keeps every headless property: the same `project spawn --headless`
   command, the same envelope, the same session id, and the same view window.
2. The permission mode changes to `DISPATCHER_WINDOWED_PERMISSION_MODE` (default
   `default`). Every ask of the harness waits for an answer. The consent prompt of
   the settings-file edit is the ask that no allow rule answers.
3. The prompt of the leg says that a person watches the view window and answers each
   permission prompt. The leg waits at a prompt and continues after the answer. A
   denial still blocks the leg.
4. The session keeps the headless markers, so the forge hook still turns its asks
   into denials. The forge work of the leg stays inside the allow rules.
5. The prompt of a windowed leg also rules its park (issue #505). A windowed leg
   that meets a decision of a class that always parks asks its question in the
   session. The leg waits for the typed answer of the owner and posts no park
   comment while it waits. The answer continues the leg on the same branch, with no
   new loop start. When the owner ends the session with no answer, the park comment
   lands. The comment holds the three parts of the park discipline of the factory
   skill. The rule binds the windowed leg alone. A plain leg parks on its entity,
   and the readiness gate parks before any session exists.
6. Each answer of the owner to a question of the leg follows the route of the
   factory skill (issue #563). The answer reaches the forge entity word for word.
   An answer of a permission prompt does not reach the forge entity. The leg
   posts the answers as a comment on its entity in the same run, and the first
   line of the comment is the provenance mark. A review verifies the quoted
   answer of the owner against that comment. No leg reads a transcript of the
   harness, in any scope. The register record
   `docs/adr/window-session-words-ride-the-forge.md` carries the ruling.

The pane of the view window runs `claude attach` on the session of the leg. The owner
watches the work there and types the answer of each prompt into the same pane.

A windowed leg can wait longer than the in-flight TTL of two hours, at a permission
prompt or at its park question (issue #505). The release then
drops its entry while its session still waits. The owner answers late and the leg
continues, or stops the session by hand. The dead-session release of dispatcher
rule 2 keeps this wait intact: a windowed entry releases only on `failed` and
`stopped`, because the park wait reads `done`. The TTL keeps its role as the backstop of a
crashed leg.

The probe of Readiness B of issue 470 binds the correctness claim: one ruled allowlist
entry lands on the branch of a watched leg, and a later headless session reads the new
rule with no denial.

## The red-gate rule and its bound

A red gate starts a leg with no human comment (issue #110). Two delivery kinds
feed the rule: the status event and the workflow run event. Each delivery
carries one conclusion word and one head commit, and both kinds run through one
shared rule.

The mapping of a delivery to its pull request first uses the fields of the
delivery itself (issue #583). A workflow run delivery names its pull request or
its branch in `run.prettyref`, and one listing of the open pull requests
resolves the name: one `tea` call, and no per-pull head-sha read, whatever the
count of open `ai/` pull requests is. A delivery that names neither keeps the
sha scan, which reads the head sha of every open `ai/` pull request until one
matches the commit of the delivery. The status payload of the forge family
names no branch, so it always takes the scan. The named form trusts the name
over the commit, so a stale conclusion of an older commit of the named pull
request reaches the bound, where the sha scan ignored it (machine decision 31).

A delivery with the conclusion `failure` on the head of an open `ai/` pull
request queues one nudge leg on that pull request. A delivery with the
conclusion `success` on the same head ends the red episode. A delivery with any
other conclusion word spawns nothing.

The status delivery has the shape `api.CommitStatusPayload` of the forge
family: `sha`, `state`, `context`, `repository`, `sender`. The forge of this
repository runs Forgejo 17, and its webhook page offers no status event. The
rule stays for a forge of the family that delivers status events.

The workflow run delivery is the live path of this repository. The recorded
delivery of 2026-11-09 (issue #228) holds the shape: the top level carries the
action word `run_completed` and the `run` object, and nothing else. The `run`
object carries the conclusion in `status`, the head commit in `commit_sha`, and
the repository in `repository`. The rule matches the payload shape, not the
event header, because the record holds the body only.

The owner ticks `Failure` and `Success` under the workflow run events on the
webhook page of this repository. The owner ticks no box under the action run
events, because the forge marks that section "do not use". Until the ticks
exist, the poll fallback owns the red gate (see The poll fallback).

The bound stops a loop of push and fail:

1. At most two nudge legs per pull request while the gate stays red
   (`DISPATCHER_REDGATE_LIMIT`, default 2). One leg per head commit: a second
   failure status of the same commit, for example of a second workflow, starts
   no second leg.
2. A red gate that arrives after the bound comments on the pull request, names
   `jracon`, sets the `needs-owner` label (issue #525), and starts no leg. No
   further leg starts on its own.
3. A success status on the head, or the closed pull request, ends the red
   episode. The next red gate gets a fresh bound.
4. The count records a queued leg, not a spawned one: an event that fails at
   spawn still spends one nudge, so the bound stays honest about how often the
   loop tried.

## The wake rule and its bound

The final comment of a leg can wake exactly one other leg (issue #525). The
wake is one reserved command, `/wake`, as the first word of the final comment
of a leg: the comment of the agent login that releases the in-flight entries
of its entity. A mid-run comment of the agent login never wakes anything,
because only the comment that releases an entry is eligible, so a confused
leg cannot summon work while it runs. The command takes no arguments and
names no target: the entity thread carries the routing, and the woken leg
reads its entity fresh.

One comment of the waker carries the context of the handoff (issue #581).
Before the `/wake` final comment, the worker or nudge leg posts one comment
on the target issue of the `Refs` keyword. The comment names the blocking
relation and the entity that waits. The sweep fetches the body and the
comments of the woken issue at spawn time (machine decision 23), so the
context comment reaches the prompt of the woken leg. The size cap of the
render bounds the length of the comment. The wake signal stays payload-free.

The context comment is a mid-run comment of the agent login on the target
issue. It releases the in-flight entries of the target, as every comment of
the agent login does (Dispatcher rules 2). The comment does not begin with
`/wake`, so it wakes nothing.

The final comment of a leg and the end of its session are two events
(issue #612): the leg posts the comment, the harness ends the session, and
the forge delivers the comment webhook seconds later. A sweep pass inside
that delivery window runs the dead-session release of dispatcher rule 2
before the receiver reads the comment, and a comment that frees no entry
derives no wake target. The release parks its freed entry in `wakehold.json`,
and the read of `release_entity` folds the parked pairs in when the in-flight
map holds no live entry of the entity, so the wake of that comment still
lands. The parked record answers the first comment of the agent login on the
entity, whatever that comment frees, and it lives no longer than
`DISPATCHER_WAKE_HOLD` (default 10 minutes), so a spent or a late record
wakes nothing.

1. The target derives from the released entry. A released reviewer branch
   (`ai/review-N`) wakes the worker nudge of the same pull request: the
   verdict continuation, the first milestone of the issue. A released worker
   or nudge branch wakes the issue that the `Refs` keyword of the branch's
   open pull request names: the composition handoff, and the cross-entity
   form for a leg that another entity blocks. A closing keyword wakes
   nothing, because it names the work of the same branch (issue #356, L7).
2. The wake enqueues the same event shape as a human comment, through the
   same inbox, sweep, pacing, and in-flight rules, so the spawn-storm layers
   hold unchanged. A wake to an issue resolves through the branch-state rule
   of a human comment on an issue, and the readiness gate runs before a
   woken worker leg is queued.
3. The bound (`DISPATCHER_WAKE_LIMIT`, default 2) is the red-gate rule as
   the template: at most this many agent wakes per entity pair, waker entity
   to woken entity, until a human act resets. A wake past the bound comments
   on the entity that carried the command, names `jracon`, sets the
   `needs-owner` label, and starts no leg; later wakes of the pair stay
   quiet. A human comment on either entity of the pair, or the closure of
   the pull request, clears the pair and removes the label, so the next wake
   gets a fresh bound. The removal of the commented entity runs only when
   the entity holds the label (issue #582). The delivery of the comment, or
   the entry of the poll listing, carries the state, and the closure of a
   pull request reads it with one `tea` call. A human comment on an entity
   that never stopped writes no label change, and the wakegate entries clear
   as before.
4. A `/wake` comment from which no target derives — a branch without an open
   pull request, or a body without a `Refs` keyword — posts one comment on
   its entity and wakes nothing, so a broken handoff stays visible.
5. The poll fallback parses the same grammar on the same comments it reads
   (see The poll fallback), so the webhook path and the poll path wake the
   same legs.
6. The self-trigger rule narrows, it does not lift: the receiver still
   ignores every agent comment that releases no entry. The reversal of the
   recorded rule carries the register record `docs/adr/agent-wake-command.md`.

## The chained starts and their bound

The ruled list of issue 631, stage 2, extends the self-trigger rule: the
agent authors four transitions, and each starts its continuation inside the
breed bound. The owner ruled the list in the windowed run of 2026-11-25 on
the issue, word for word: `yes`, `dispatcher writes the label`, `confirm`,
`in`.

1. The refinement continuation that reports the brief final starts the
   research leg of stage 4 on its issue. The clear of the ask status is the
   edge that carries the start: the continuation writes the clear, and the
   ruled chain of the section above runs from it.
2. The same final continuation advances the board: the dispatcher writes
   the ready status, so the readiness gate and the worker start with no
   human act between the refinement and the implementation. The dispatcher
   writes the label itself, the route that the owner picked over giving the
   human-only name up: `forge.humanLabels` keeps the name, every leg keeps
   its denial, and the tea login of the loop service carries the write,
   which no hook governs.
3. The research leg posts its record comment with the research mark as the
   first word, `/research`, and the marked comment starts one adversarial
   review of the approaches, which posts its verdict comment with the same
   mark. The record and the verdict free the research entries of their
   entity alone, so the worker leg that runs in parallel on the worker
   branch keeps its slot and its session whatever the research side posts,
   and a plain comment of the agent login frees the plain entries alone, so
   the closing comment of the worker never stops the research mid-run. A
   research entry whose leg posts no marked comment frees through the
   dead-session release of the sweep, the same path as a leg that crashed
   with no comment. The review start keys on the freed entry of the
   research kind, the eligibility rule of the wake: a marked comment that
   frees no research entry starts nothing, and the marked verdict of the
   review frees its own entry and chains nothing, so the person reads
   record and verdict as the last words of the thread.
4. The mid-run park of a worker leg writes the ask status beside its park
   comment, so a plain answer of a person resumes the park through the
   refinement continuation with no command: the answer edge of machine
   decision 36 carries the resume, and the continuation that reports the
   brief final after the answer starts the chain of entry 2 again, so the
   worker leg resumes on the recorded session.

The bound (`DISPATCHER_BREED_LIMIT`, default 2) is the wake bound as the
template: at most this many fired transitions of the agent on one entity
until a human act resets. The count records the fired transition, not the
legs it queues, so one clean chain of an issue spends one count on the
final refinement and one on the review of its research record, and the
default of two admits exactly one chain per human act. A transition past
the bound comments on the entity, names `jracon`, sets the `needs-owner`
label, and starts no leg; later transitions of the entity stay quiet. A
human comment on the entity, the closure of its pull request, and a
person-set label edge reset the bound, the reset that a human comment
carries (the design default of the stage park, which the owner let stand),
and the same reset clears the wake bounds of every pair that names the
entity.

The research leg spawns on the research branch `ai/research-N` of its
issue, beside the worker branch: the two run in parallel, because the owner
ruled no hard gate sits before the worker. The spawn copies the refinement
spawn — the verified trunk for the new branch, the plan, the tier — and
resumes no session, so a repeated research run reads its issue fresh, the
token cost that dedicated the role. The adversarial review spawns on the
same branch with a fresh session, because a review reads independently of
the author it attacks, and neither leg runs windowed, because a chained
start names no permission mode. The hand prompt of both roles is
`dispatcher.py prompt research <issue>` and
`dispatcher.py prompt research-review <issue>`. Stage 4 of the issue
deepens the research role itself: the shape of the record and the verdict
that the prompts of this stage name are the working minimum.

## The needs-owner label

The `needs-owner` label (issue #525) marks a thread that the loop stopped and a
person must act on. The dispatcher sets it when a bound trips — the wake bound
above and the red-gate bound — beside the comment that names the owner. The
human act that resets the bound removes it: a human comment on the entity, or
the closure of the pull request. The removal runs only when the entity holds
the label (issue #582). The payload of a comment delivery and the entry of the
poll listing carry the label state, and the closure reads it with one `tea`
call, so a human comment on an entity without the label costs no label write.
The removal of each waker of a cleared pair keeps its unconditional shape,
because the label state of the waker is not in the payload of the comment.

The label also carries the one plain-text trigger of the human surface. A plain
comment of a person starts nothing on any entity; on an entity that holds the
label, the prose continues the thread: the loop stopped it to wait for exactly
that answer. The comment queues the leg through the branch-state rule of a
command comment, resets the wake bound, and removes the label. Commands work on
a labeled entity as on any other.

## Dispatcher rules

1. Each delivery ID is a file name. A delivery that arrives twice is processed once.
2. The in-flight map blocks a second leg on a branch that a leg already works. The
   final comment of a leg, a comment of the agent login on its entity, releases its
   entry. The release also stops the background session of the leg (see The
   background-session machinery of a leg). Before an entry blocks a spawn, the sweep
   reads the state of its session from `claude agents --json --all` (issue #605): a
   plain leg whose session the listing reports `done`, `failed`, or `stopped`
   releases at once, inside the TTL, so a leg that dies with no comment holds the
   commands of its entity for one sweep pass, not two hours. A windowed leg releases
   on `failed` and `stopped` alone, because its park question waits for the answer
   of the owner and a session at that wait reads `done` (issue #505). An entry with
   no windowed mark predates the mark and names no kind, so `done` holds it the
   same way: a windowed leg of the code before the mark can sit at its park wait
   when the new code first sweeps, and that sweep must not release it. A read that
   fails, an entry with no session id, and a listing that names no state word
   release nothing, so the two-hour TTL stays the backstop, and an entry older than
   two hours counts as a crashed leg whatever the listing says. A plain leg whose
   session the listing reports `working` and whose transcript the harness wrote
   nothing to past the stall grace (`DISPATCHER_STALL_GRACE`, default 30 minutes)
   releases its entry the same way, with one comment on its entity that names the
   session and the block (issue #665). The transcript of the session is the
   progress signal: the harness appends to it as the session works, so a live leg
   on a long step keeps its budget, and a grace that finds no transcript to read,
   no session record, or no entity judges nothing and holds the entry. A windowed
   entry and an entry with no windowed mark release never on the stall: the wait
   at a permission prompt or at a park question shows no progress and is no hang,
   so the TTL stays their backstop. The release of the stalled session stops it,
   comments once, and wakes nothing, the same rule as the dead-session release.
   The release of the
   dead session wakes nothing by itself: only the comment of the agent login
   carries the wake rule, and the release parks its freed entry in the wake
   hold, so a final comment that the forge delivers after the release still
   wakes its target (issue #612, see The wake rule and its bound). The stall
   release and the two-hour TTL release park nothing: the stall release stops
   a session that still works, so no final comment of that leg sits in
   delivery, and a leg past the TTL posted its final comment long before the
   release or posted none. A stop of a release that fails leaves its session
   live (issue #696): the release posts one comment on the entity of the leg
   that names the session, the branch, and the entity, and records the session
   in `stopfail.json` for `DISPATCHER_STOPFAIL_HOLD` (default 2 hours, the TTL
   of a crashed leg). The session can finish its turn at the timeout of its
   hung call and post its final comment, and no rule tells that comment from
   the genuine final comment of the leg that holds the entry, so the release
   keeps its shape: each comment of the agent login on the entity that
   releases in-flight entries inside the window posts one comment that names
   the exception, so no successor stops silently. The self-trigger rule skips
   both comments by their first words (`dispatcher: the stop of a leg
   session `), the same exception as the stall report. An entry that names no
   entity comments nothing: the journal alone holds the failure, the same
   shape as the stall report. An event that finds its branch busy stays in
   `events/`, and the next sweep retries it, so an event that arrives during a
   live leg runs when the
   leg ends. A delivery for a branch that already has a pending event is
   superseded: it is recorded and never spawns, because one pending event per
   branch is enough, and a leg reads its entity fresh. The record names the
   pending delivery in its `superseded_by` field, and the journal names both
   deliveries, so the trace shows outside the state directory (issue #665). When
   the branch holds an in-flight entry, the delivery joins the list that the
   entry carries, and the release of a stalled leg names those deliveries in its
   comment, because the supersede feedback belongs to the block and not to every
   command.
3. The spawn runs `systemd-run --user --scope --collect --quiet
   --expand-environment=no project spawn <project> <branch> --plan zai --headless
   --permission-mode dontAsk <prompt>`. A windowed event swaps `dontAsk` for
   `DISPATCHER_WINDOWED_PERMISSION_MODE` (issue #470, see The windowed route of
   allowlist work). A worker or nudge event on a branch whose session record
   names a live transcript adds `--resume <uuid>`: the session of the leg
   continues the recorded conversation under its own id, or the harness starts
   a copy under a new id with one note line (issue #524, machine decision 29).
   A reviewer event and a windowed event add nothing, and a record whose
   transcript the cleanup removed resumes nothing: that leg starts fresh with
   the full brief. A worker event adds `--verified-trunk <serving trunk>`: the
   trunk knob (`DISPATCHER_TRUNK`) names it, and an instance with an empty knob
   names the default branch that `origin/HEAD` holds in the clone, so the branch
   starts at the tip that rule 4 verified (issues #571 and #637). The tool runs
   no fetch of its own for that flag, so the spawn also starts inside the
   sandbox tier, where no key answers a fetch (issue #607). An instance that
   cannot name a trunk passes no base, and the spawn keeps its own guard. A
   nudge branch exists already, and rule 6 prepares the reviewer branch, so
   neither names a base. Every other part of the command stays the same. The
   prompts name the `factory` skill. The scope keeps the background-session
   machinery of the leg out of the cgroup of the receiver unit (issue #93).
4. Before every spawn, the sweep fetches `origin` in `main/` of the project clone
   (`refresh_clone`). The fetch follows the retry schedule of the spawn. A fetch that
   fails after every retry fails the event and comments on the entity: no leg starts
   on a base that the clone cannot verify against the origin of the serving trunk
   (issue #100). The fetch also gives the reviewer branch its fresh tip. The
   spawn itself refuses the same case with exit code 12, so the guard has two
   layers. A spawn that names a verified trunk runs no fetch of its own
   (issue #637), so this rule is the only layer that verifies its base.
5. The envelope of the phase 3 binary decides the outcome. Exit codes 11 and 12 are
   retried twice, after 30 and 120 seconds. In the sandbox tier, each retry stops the
   leg unit before the start of the next attempt. The retry also empties the envelope
   files of the leg state. The retry stops no agent unit, because the agent of the leg
   holds the push key of the retry. The cgroup exit type of the template keeps the
   unit active while one process of the failed spawn stays (issue 634). A start of an
   active unit answers success and runs nothing. Without the stop, the retry reads the
   envelope of the failed attempt as its own outcome (issue 652). When the stop fails,
   the start of the retry runs nothing, and the empty envelope file names no code. The
   read then answers a plain failure. The first start holds the same clear (issue
   653): the spawn empties the envelope files after the pre-spawn stop, and a stop
   that the system manager denies logs its answer. A denied stop leaves a leftover
   instance active, the first start of the spawn runs nothing, and the empty envelope
   file names no code: the read answers a plain failure, and no envelope of an
   earlier spawn of the branch answers for the new one. Exit code 7 comments on the entity and
   names `jracon`: this needs the owner. Exit code 2 comments on the entity: it names
   a defect in the dispatcher. Every other failure comments on the entity and stops.
   A failure before the envelope names the phase that failed and its error line in
   the comment (issue 621): the agent unit start, the ssh-add handshake, the leg
   unit start job, and the spawn itself. An event that dies by exception moves to
   `failed/` and comments on the entity with the phase that raised and the error
   line.
6. The reviewer branch is not created with `--from`. A `--from` spawn would record the
   worker branch as a `projectBase`, and the forge hook then answers `ask` for every
   later push of the worker, which a headless leg cannot answer. Instead, the
   dispatcher points the reviewer branch at the tip of the worker branch with plain
   git in `main/` and sets its upstream. Rule 4 fetched the clone before this step,
   so the tip is current. The reviewer pulls only when its worktree does not hold
   the tip. It runs `git fetch origin`, then compares `git rev-parse HEAD` with
   `git rev-parse @{u}`. It runs `git pull --ff-only` only when the two commands
   print different commits. A branch that moves allow rules into the user layer
   removes the pull rule from the project allowlist. The host gains the moved rule
   only at its next home switch, so an unconditional pull can stop at a denial
   inside that window (issue #515).
7. One sweep pass starts at most one leg, and a pass starts no leg within
   `DISPATCHER_SPAWN_SPACING` seconds (default 60) of the last start (issue #225). The
   sweep timer (one minute) drains queued events one leg per pass, so a burst of
   deliveries cannot start a burst of legs: the audit of the loop found the
   first-response stalls and the weak legs inside the bursts. The pace records an
   attempt, also one that fails at the fetch or the spawn, so the floor stays honest
   about how often the loop tried. The cost is latency: an event that queues behind
   another leg or inside the spacing starts on the next pass, about one minute later.
8. The sweep fetches the entity of an event at spawn time, after the fetch of the
   clone and before the spawn command, and renders the reads into the prompt of the
   leg (issue #311). The prompt names what the payload holds and the time of the
   read. A comments read of an empty set answers the sentence `No comments found`
   with exit 0, and the read treats that answer as the empty list (issue #421), so
   the payload of a first reviewer leg stays whole: the first comment of a factory
   pull request is the verdict of its reviewer. A payload that the fetch cannot
   get, or that passes the cap, is cut whole. The prompt then falls back to the
   read commands, with one sentence that names the cut, and the leg runs (machine
   decision 23).

## The environment of a leg

A spawned leg inherits the environment of the dispatcher unit, so the unit is
the only place that can give the leg the machine gate (issue #96):

1. The unit PATH starts with the store path of python3, then the store path of
   go. The two allowlisted harness commands of the repository and the Go gate of
   the project tool run inside a leg. The devShell of a worktree holds go too,
   but only when the direnv environment of that worktree loaded, and the spawn
   starts a leg outside that environment when the load fails: the run of issue
   #110 proved it, so the unit PATH is the source that always holds.
2. The sandbox tier (issue 607, section S of issue 393) bounds each leg: the
   spawn starts an instance of the leg-unit template of the tier module
   (modules/services/sandbox-tier.nix) on the system manager, whose
   properties the module authored, so the dispatcher units themselves set
   no sandbox option — each of them must still reach the ssh config of dev,
   the tea login, and the whole home. The leg runs on the system manager
   because only it enforces the IP firewall (the user manager skips
   IPAddressDeny and IPAddressAllow for non-root, the manager warning of
   the first tier spawn), and the spawn and stop calls of the receiver
   ride the polkit delegation that the tier module scopes to the two
   template names and the start and stop verbs (machine decision 33). The
   spawn call carries no unit properties — a transient-unit spawn passes
   its properties beside the name in one authorized call, so a name-scoped
   delegation could not stop a caller from smuggling User= into a leg
   unit — and the per-spawn argv and env ride the request file of the leg
   state, which the ExecStart of the template execs
   (modules/services/dispatcher/leg-run.py). The bound of the leg cuts the
   ssh route of the leg itself, because no file of `~/.ssh` is visible
   inside the unit: the git transport runs through an ssh agent that the
   dispatcher starts with the push key alone in its own leg-agent
   instance, the ssh options come from the dispatcher, and the transport
   connects by the name of the forge ssh host: the publish of the port
   DNATs the connect to the container address of the forge, which the
   allow list of the tier names (machine decision 32). The spawn
   preparation removes a stale agent socket of the branch before the agent
   start (issue 678): ssh-agent unlinks its socket at a clean exit, but an
   unclean stop of the leg or of the host leaves the file, and ssh-agent
   refuses to bind a path that exists, so one stale file fails every later
   spawn of the branch (dispatcher.py, remove_stale_agent_socket). The tier
   knob is the DISPATCHER_TIER environment of the dispatcher units
   (dispatcher.nix), and a host without the knob leaves every spawn on the
   plain scope of the code before the tier, so the loop keeps working
   there. An impure flake check passes inside a leg even inside the unit.
   The ZFS pool supplies a default `hostId`, so the
   evaluation of `nixosConfigurations.media` needs no `hostId` from the
   machine-local configuration (docs/containers.md holds the record). A leg
   gates itself with the local run of that check before the push. The CI gate
   of the pull request stays the authoritative run of the merge.

## The sandbox probe harness

The sandbox tier of issue 555 bounds each spawned session with a systemd service unit on the system manager
and an allowlisting forward proxy on `services`. The tier is security spine: an agent writes the unit and the proxy config, and
the owner reviews both line by line and merges (docs/design.md, Stance item 10;
docs/adr/spine-work-by-agents.md). The probe harness is the oracle of the tier, and it is glue. Run it
inside a session, from a checkout on `services`, with the command `python3
modules/services/dispatcher/sandbox-probe.py`. One probe answers one control:

1. The write probe writes one file under the home directory, outside every carve-out of the unit, and
   removes the file when the write answers.
2. The ssh probe reads one byte of each key and config file of `~/.ssh`. It prints no file content.
3. The egress probe connects to one address that no allowlist entry names.
4. The proxy probe reads the plan files for the endpoint hosts, the one source that the allowlist of the
   proxy also derives from, and connects to each host with a raw socket, which no proxy governs.
5. The leg-placement control reads the placement of the leg instead of trying a blocked action (issue 633):
   the cgroup of the probe process must name the service unit of the leg and no tmux spawn scope, the
   mount table must name the bind of the daemon socket directory over the daemon root of the harness, and
   the supervisor socket must resolve to the leg state through the harness path and the leg state path as
   one inode. The control fails while the supervisor socket is unreachable from outside the unit, or while
   a session process of the leg sits outside its unit.
6. The push-path control of issue 658 runs one `git ls-remote` through the transport that the
   environment of the leg carries, the same ssh command and agent socket that a push uses, and it
   holds when the route answers. The note of the control names the connect target that the
   transport pins.
7. The forge probe reads the session settings for the hook, and feeds one push to the default branch, one
   compound command, and one entity edit to `forge-hook.py` of the same tree, with the markers of a spawned
   headless session set. No case reaches the network.

A control holds when the action fails; the leg-placement control holds on the placement it reads. Before the
tier lands, the six tier controls quote the open state and the run exits 1. After the tier lands, every
control holds and the run exits 0. The forge control
holds before and after, because the hook answers above every local tier. The run of 2026-11-25 held every
control on the switched host, and it backs the verdict of Trust criterion 11 of docs/agent-context.md
(issue 607).

The harness runs live on `services` alone, because the runner of the gate is not the sandbox: the pull
request gate runs the static checks of the file and no live probe (lib/checks.nix). The direct command runs
under one project rule in `.claude/settings.json`, landed through the windowed route of the settings-file
gate (issue 470): a `/watch` comment started the windowed nudge leg of pull request 617, and the owner
answered the one consent prompt of the settings-file edit in the view window. A leg runs the harness
directly under the rule, and the owner runs it by hand after each rebuild of `services`.

## The background-session machinery of a leg

A `claude --bg` run starts no session process of its own. It reaches one
supervisor daemon, and every session runs as a process of that daemon
(verified live, issue #93). The supervisor is per config directory: the
harness runs one instance with its own sessions under each value of
`CLAUDE_CONFIG_DIR` (the harness docs, Where state is stored). The sandbox
tier (issue 607) builds on that fact: each spawn sets the config directory
of its branch — `<project>/.claude-legs/<branch>/config` — and starts its
supervisor inside the unit of the leg. The unit is an instance of the
leg-unit template of the tier module on the system manager
(modules/services/sandbox-tier.nix), and every session of the leg lands in
the cgroup of that unit, where the bounds of the tier hold. The
dispatcher copies the live user layer of `~/.claude` into the directory
before each spawn, because the config directory holds the whole harness
state: the settings with the allow rules and the forge hook, and the
instructions. The session settings that the spawn builds also carry the
tracked project rules of the worktree beside the rules of that copy (issue
627): the resumed and restarted background sessions on record kept the
config directory, the forge hook, and the settings file, and lost exactly
the project layer of the working directory, so the copy closes that gap.
The onboarding state of `~/.claude.json` — the file sits
beside the config directory of the user, not inside it — is copied once as
the base of a fresh leg config, and the trust of the leg's own worktree is
seeded into the config state on every spawn, in the config file and in the
backups the harness restores from, because a session of the tier answers no
trust dialog and the harness refuses an untrusted working directory (issue
607, the records of 2026-11-21 14:10 and 14:44). A spawn on a host without
the tier knob (dispatcher.nix, DISPATCHER_TIER) runs the plain scope of the
code before the tier, and its leg joins the supervisor of the interactive
sessions of the user.

A restart of the session process lands in the unit while the supervisor
lives. The unit ends when the last process of its cgroup leaves
(`ExitType=cgroup`, machine decision 32). The exit of one session process
does not end the unit and does not kill the supervisor. The supervisor
serves every session of the leg (verified live, issue #93), so the session
process that the harness restart starts runs inside the cgroup of the
unit.

A supervisor that died before the restart leaves no listener on the linked
socket, and a restart after that starts a new supervisor outside the unit.
The probe harness carries the placement: the leg-placement control fails
while a session process of the leg sits outside its unit (issue 634).

Every release of an in-flight entry stops the session of its leg, then ends
the sandbox half: the comment of the agent login on the entity, the closed
pull request, the dead-session release of dispatcher rule 2, the stall
release of dispatcher rule 2 (issue #665), the release
entry point of the owner steps, and the two-hour TTL of a crashed leg. The
spawn envelope records the session
id that `claude --bg` printed, and the release stops that id, so the stop
names one session alone: a stopped session stays listed under its name
for about an hour, so the name of a re-looped leg can name two sessions
and a stop by name can hit the wrong one (issue #208). An entry that
predates the id falls back to the name lookup of issue #144: `claude
stop` accepts no name, so the release reads `claude agents --json` and
stops every listed background session under the recorded name. A stop
that fails leaves its session live, and the failed stop names itself on
the entity of the leg, so a session that stays live stays visible
(issue #696, dispatcher rule 2). The
conversation stays, so the owner can resume it — and the loop does: the
session record of the branch (`sessions.json`, issue #524) survives the
release, names the config directory of the branch, and the next worker or
nudge leg of the branch resumes the
transcript through the UUID of the latest envelope, inside its own new unit
against the same config directory. A stop of a resumed
leg names the id of the latest envelope, whatever id the harness printed
for the resume. A session that ended
stops by itself only after about one hour, and a name that no listed
session holds needs no stop. The stop also ends the view window of the
leg (see The view window of a leg). After the session stopped, the release
runs `claude daemon stop` with the config directory of the leg, so the
supervisor of the leg ends, the cgroup of the unit empties, and `--collect`
removes the unit; the agent unit of the leg stops with one `systemctl --user
stop`. The dispatcher stops the supervisors of legs alone: the supervisor of
the interactive sessions of the user serves other work of this host, and
the dispatcher never stops it. The transcripts of the legs sit under the
config directories, so the leg-state member of the backup set covers them
(docs/backups.md).

## The socket placement of a supervisor (issue 633)

The harness builds the control socket path of the per-config-directory
supervisor from the uid alone: `/tmp/cc-daemon-<uid>/<hash>/control.sock`,
with the first eight hex chars of the sha256 of the config directory
string as `<hash>`. The harness honors no variable for the root, so the
socket path admits no configuration. Under the tier, `PrivateTmp=yes` puts
that path into the private tmp of the unit of the leg. The attach of the
view window runs outside the unit, resolved the same path in the real
`/tmp`, found a live supervisor pid in `daemon.lock`, could not reach the
socket, and retried; after about 30 seconds its stall recovery replaced
the supervisor from the tmux pane, and the replacement supervisor and the
respawned session ran in the tmux spawn scope, outside every bound of the
tier (issue 633).

The fix meets the harness on its path. The dispatcher prepares one socket
directory of the leg state before the unit starts —
`<base>/daemon-socket/<hash>`, rebuilt on every spawn, so a supervisor of
a previous run that died without its own cleanup leaves no socket file a
fresh supervisor could refuse to bind (dispatcher.py,
prepare_daemon_socket). The unit of the leg binds that directory over
`/tmp/cc-daemon-<uid>` with the daemon-socket entry of the leg-unit
template (modules/services/sandbox-tier.nix, the BindPaths list of
legBinds). The `%i` of the instance name expands inside the source path of
the entry, so the template itself names the per-leg source, and the spawn
call passes no bind property, the same shape as the state bind of the
leg-agent template. The dispatcher
links the same directory into the real daemon root under the hash name
that the harness itself derives (dispatcher.py, daemon_socket_hash), so
both namespaces resolve one socket path to one inode: the supervisor binds
its socket into the leg state, and the attach of the view window and every
claude call of the dispatcher reach it from the host, while the rest of
`/tmp` stays private. The bind rides the mechanism that the plan token
bind proved: systemd applies the bind entries after the private tmp is set
up (modules/services/sandbox-tier.nix, the plan token comment). The link
may dangle until the supervisor binds its socket; the spawn opens the view
window only after the envelope, and the supervisor binds before the
envelope. The release removes the link after `claude daemon stop`, whose
call itself reaches the supervisor through the link
(dispatcher.py, remove_daemon_socket_link). The probe harness of the tier
holds the leg-placement control, which fails while the socket is
unreachable from outside the unit or while a session process sits outside
its unit (see The sandbox probe harness).

## The view window of a leg

Each spawn opens one view window for its leg, in the tmux session named after
the project on this host (issue #116). The window is named after the branch,
and its pane runs `claude attach` on the background session of the leg, so the
owner watches the leg work. Under the sandbox tier the pane command carries
the config directory of the leg with `env`: the pane runs under the tmux
server, outside the unit of the leg, and the attach must reach the supervisor
of that leg. The attach resolves the socket path of the supervisor through
the link that the dispatcher prepares before the unit starts, so the pane
command itself is unchanged (see The socket placement of a supervisor,
issue 633). A windowed leg also takes its answers there: the
owner types the answer of each prompt into the pane (issue #470). The pane
attaches by the session id that
`claude --bg` printed: a stopped session stays listed under its name for about
an hour, so the name of a re-looped leg — a nudge leg after its worker, a
reviewer after a push — can name a stopped session beside the running one, and
an attach that picks the stopped one ends its pane at once, which closes the
window. The id names one session alone, so the window stays open for the whole
leg (issue #208). Without an id the pane attaches by the name. The window ends
with the session: the attach client exits when the session stops, and tmux
closes the pane and the window. The release of the in-flight entry stops the
session, so its window ends with it. `project close` stops the sessions of a
worktree and removes the windows that outlived them. When the spawn cannot
make the window, the leg starts anyway, the spawn prints a warning on stderr,
and the dispatcher writes that stderr to its journal.

The view window goes to the tmux server that the spawn itself reaches, so the
environment of the spawn decides the socket. tmux puts its socket at
`$TMUX_TMPDIR/tmux-$UID/default`, and at `/tmp/tmux-$UID/default` when the
variable is empty (tmux(1), section ENVIRONMENT). A login shell of `dev`
exports `TMUX_TMPDIR` through the session variables of Home Manager, but the
dispatcher units are user services and source no profile, so the units set
`TMUX_TMPDIR=%t` themselves. `%t` is the runtime directory of the user,
`/run/user/1000` (systemd.unit(5), Specifiers), which is the socket that
`project open dev@services:genixis` attaches to. Without the setting, every
leg opened its window on a second server under `/tmp`, in a second session
named after the project, and the owner saw no leg window (issue #143).

## The poll fallback

The receiver binds to the gateway of the Podman default bridge, `10.88.0.1` port
`8741`. Verified on `services`: the default bridge is the network named `podman`, its
subnet is `10.88.0.0/16`, and its gateway is `10.88.0.1`. Confirm it with
`podman network inspect podman`. When the bridge facts fail, switch to the fallback,
as `dev` on `services`:

```fish
systemctl --user disable --now dispatcher-receiver.service
systemctl --user enable --now dispatcher-poll.timer
```

The fallback polls the open issues with `tea` every two minutes and queues the same
worker legs from new command comments. The detail read of each issue also carries its
label state, and the diff of that state against `labels.json` routes the same status
edges as the webhook path, with the per-issue baseline of the first sighting and a
prune of the entries of the issues that left the open listing (see The status labels
and the refinement role). The same diff carries the ruled clear of stage 2: an ask
status that the recorded state held and the detail read holds no more, with no new
edge beside it, fires the chained starts of the final refinement (see The chained
starts and their bound), and the ready label that the dispatcher itself writes
records its state with the write, so the poll reads no edge in it. The event name of
a label pass carries the time of the pass, so a second edge of the same issue inside
the prune window of the processed records still queues its leg. A plain comment on
an issue that holds the
`needs-owner` label continues that thread, and a plain comment on an issue that holds
the ask status starts the refinement continuation, the same rules as the webhook path.
It also
queues one reviewer leg for each new
open pull request on an `ai/` branch. It also reads the newest CI status of each
open `ai/` pull request, with its head commit, and queues the same red-gate nudge
leg when a head commit fails that it has not seen red. A status that turns green
ends the red episode. The first poll records the baseline, of the comments and of
the CI statuses, and queues nothing, so the fallback never replays the history of
the repository: a comment or a red gate that arrived before the first poll needs
one new comment, one new CI run, or the webhook. A cursor file without the pull
request comment map predates that surface, and its issue entries cover the gated
issues of the old listing only, so the first poll after that upgrade records the
baseline again. An unreadable cursor file takes the same branch. An agent
comment that the poll
reads releases the worker slot of that issue, and a final comment that begins
with `/wake` wakes through the same rule as the webhook (issue #525); a comment
that begins with the research mark frees the research entries of the entity alone
and starts the adversarial review, the same surface as the webhook path (issue 631,
stage 2); the
stall report of a stalled leg and a stop-failure report release nothing, the
same exceptions as the webhook path (issues #665 and #696). The poll
also reads the comments of each open `ai/` pull request: an agent comment
releases the slots of the legs of that pull request, a final comment with
`/wake` wakes, a command comment of a person continues the work, and plain
prose continues a thread under the `needs-owner` label. That continuation
reads the label before the same comment resets the bound and removes the
label, the state that the payload of a webhook delivery carries. The fallback
does not
re-review after a push to the same pull
request: that part needs the webhook. The cursor file makes each poll idempotent.

## The owner can run every step by hand

Standing principle 8 of issue #74. Each step of the loop, as the owner or as `dev`:

1. Read the entity: `tea issues N --comments`, `tea pulls N`, `tea comments list N`.
2. Print the prompt of a leg: `python3 modules/services/dispatcher/dispatcher.py prompt
   worker N`, run from a checkout of this repository. Use `prompt nudge N` or
   `prompt reviewer N` with a pull request number instead. Use `prompt worker N
   watch` for the brief of a windowed leg (issues #470 and #525). The command renders the
   entity payload into the prompt, names the time of the read, and starts no leg
   (issue #388). A hand spawn and a looped spawn then deliver the same brief shape.
3. Start a worker leg: `project spawn genixis ai/issue-N --plan zai --headless
   --permission-mode acceptEdits "<printed prompt>"`. A windowed leg takes
   `--permission-mode default` and the printed windowed brief. A project whose
   serving trunk differs from its default branch takes `--from <trunk>` in the
   same command, the value of the `DISPATCHER_TRUNK` knob of its instance: a
   hand spawn runs where the fetch of the tool answers, and the projectBase it
   records is the count of close and clean. The looped route alone takes
   `--verified-trunk` (rule 3), because the sandbox tier denies the fetch of
   the tool. Stay near the session and answer its prompts.
4. Start a reviewer leg: point `ai/review-N` at `origin/ai/issue-N`, set its upstream,
   then spawn it the same way.
5. Watch the sessions: `claude agents`, `claude attach <id>`, `claude logs`,
   `claude stop`. Each headless leg has one view window in the
   tmux session of the project, named after the branch (see The view window of
   a leg). `project open dev@services:genixis` shows that session, and its
   status bar lists the window of each leg.
6. See the state of the loop: `cat ~/.local/state/dispatcher/inflight.json` and
   `project list genixis`.
7. Release a held entry: `python3 modules/services/dispatcher/dispatcher.py release
   ai/issue-N`, run from a checkout of this repository. The command frees the
   in-flight entry of the branch at once and stops the session of its leg,
   whatever the session does. A queued event of the branch runs on the next sweep
   pass. Use it when a leg crashed with no comment, or after a stop of a
   misbehaving leg by hand: `claude stop` alone frees no entry, and before this
   step an owner who stopped a leg locked its entity until the TTL (issue #605).
   The command starts no leg, comments on nothing, and wakes nothing.

## Security notes

1. This directory is security spine under standing principle 7 of issue #74. Review
   `dispatcher.py` and `dispatcher.nix` line by line.
2. The secret file is `0400`, owned by `dev`, group `users`. The receiver reads it
   once per delivery, so a rotation needs no restart.
3. The dispatcher writes only inside its state directory. It starts processes only
   through `project` (inside a transient user scope), `git` (in `main/` of the
   project clone), `tea` (entity reads, `tea comments add`, and the one label
   write of the `needs-owner` mark through `tea issues edit --add-labels` and
   `--remove-labels`, issue #525), and `claude stop`
   with the recorded id of a released session. The `claude agents --json` reads of
   the name fallback and of the dead-session release only read the session
   listing.
4. The receiver has no authentication beyond the webhook signature. It is reachable
   only from the Podman bridge of the host: the module opens the port on the bridge
   interface alone, and no other network reaches it.
5. The receiver answers one thread per delivery. Two limits hold one
   connection short. `DISPATCHER_READ_TIMEOUT` (default 10) closes a
   connection that sends no data for that long. `DISPATCHER_REQUEST_TIMEOUT`
   (default 30) bounds the total time of one request, from the accepted
   connection to the written reply, whatever the sending pattern: a client
   that sends one byte at a time keeps every single read under the first
   limit, and the second limit still cuts it (issue #91, issue #97). The
   bound ends at the reply. The work after the reply stays inside the spawn
   timeout and its retries.
6. Legs run under the dontAsk permission mode: a command that no rule allows is
   denied at once, and the leg comments on its entity that it is blocked, then
   stops. A windowed leg runs under `DISPATCHER_WINDOWED_PERMISSION_MODE`
   instead: each ask of the harness waits for the owner (issue #470, see The
   windowed route of allowlist work). The forge hook denies a forge command that
   it would ask about. The mode
   is interim: when the sandbox probes of phase 5 of issue 74 pass, the mode
   becomes bypassPermissions, and the sandbox, the proxy, and the hook become the
   boundary.

## Machine decisions

The phase text leaves these open. The brief of the pull request repeats them.

1. The worker branch of every instance names its serving trunk through
   `--verified-trunk` (issue #637): the trunk knob names the trunk, and an
   instance with an empty knob names the default branch that `origin/HEAD`
   holds in the clone. The sweep verified that tip with its own fetch (rule 4),
   and the flag asserts the verification, so the tool runs no fetch of its own.
   Inside the sandbox tier no key answers that fetch (issue #607), and the
   spawn of the code before the flag exited 12 on every new branch, because the
   guard of issue #100 read the failed fetch as a stale base. The earlier route
   was `--from <serving trunk>` for an instance whose trunk differs (issue
   #571), and no base at all for an instance that serves the default branch:
   the tool recorded the trunk as the `projectBase` of the branch, and that
   record was correct, because the pull request of the leg opens against the
   same trunk. The flag records no `projectBase`, so close and clean of a
   second-trunk instance lose the merge counting through the trunk; issue #643
   tracks that gap. Preparing the worker branch with plain git, the pattern of
   rule 6, lost: it copies a base path that the tool already owns, and a trunk
   name that no ref holds would need its own failure handling, while the flag
   answers through the exit-code table of the tool.
2. The reviewer branch is prepared by the dispatcher with plain git, not with
   `--from`, for the reason in dispatcher rule 6.
3. The final comment of a leg releases its in-flight entry, because the prompts
   make that comment the declared end of a leg. The release also stops the
   background session of the leg, so an agent comment that arrives before the end
   can no longer let a second leg run on a branch whose first leg still lives.
   The two-hour limit stays the backstop for a leg that crashed without a
   comment. Issue #605 replaced the earlier claim that no script can read the
   liveness of a `claude --bg` session: `claude agents --json --all` answers one
   state word per background session (`working`, `blocked`, `done`, `failed`,
   `stopped`), and the harness docs name the listing the supported way to read
   the state of a session from a script (code.claude.com/docs, agent view, List
   sessions as JSON). The sweep releases a plain entry on `done`, `failed`, and
   `stopped`, and a windowed entry on `failed` and `stopped` alone, because the
   park wait of issue #505 reads `done`. An entry with no windowed mark names no
   kind and holds on `done` the same way (the review of the pull request): a
   windowed leg of the code before the mark can sit at its park wait when the
   new code first sweeps. A read that fails holds the entry, so a
   harness build that answers no `--all` listing keeps the two-hour backstop,
   and the release entry point of the owner steps works whatever the build
   answers. The machine decision that lost: a shorter TTL, because it would cut
   legs that legitimately run long and windowed legs that legitimately wait.
4. Both legs run under the plan `zai`. A second plan for the reviewer, when one
   exists, is one environment change in the unit (`DISPATCHER_REVIEWER_PLAN`).
5. The `/loop` and `/watch` command prefixes are fixed. A command comment of a
   person starts a leg on an open issue; a plain comment starts nothing, on an
   issue and on a pull request, unless the `needs-owner` label marks the thread
   as one the loop stopped (issue #525). The status edges of issue 631 join
   this surface beside the commands: a person-set rough or ready status starts
   the leg that the edge names. The retired `gate` label triggered a
   leg for every comment while it stood; it triggers nothing now, and the
   owner deletes it on the forge after the merge.
6. A command comment on a pull request starts a nudge leg: a worker leg on the head
   branch of that pull request. Its prompt tells it to work the blocking findings
   of the pull request and to open no second pull request.
7. The first poll of the fallback records the baseline and queues nothing. It
   trades a one-time blind spot for the guarantee that the fallback never replays
   the comment history of the repository.
8. Headless legs run under dontAsk until the sandbox of phase 5 of issue 74
   passes its probes. dontAsk makes an unallowed command a visible denial
   instead of a hang, and the owner learns the missing rule from the comment of
   the blocked leg. bypassPermissions follows only after a probe confirms that
   the deny rules and the forge hook still hold in that mode.
9. The read timeout of the receiver defaults to 10 seconds. A real delivery
   sends its whole body at once and stays far below it, so the timeout costs no
   delivery. `DISPATCHER_READ_TIMEOUT` overrides it, and the unit sets nothing:
   the default is the deployment value.
10. The gate environment of a leg lives in the dispatcher units, not in the
    Home Manager profile of `dev`: the unit PATH carries python3 from the nix
    store. A python3 package for the profile of `dev` would install it on every
    host that loads `llm-agents.nix`, for every user of that host.
11. The isolation of `/etc/nixos` stays out of the units until phase 5 of
    issue 74: no sandbox option may enter a user unit, because the implied
    user namespace breaks ssh of the legs through the root-owned store symlink
    of the ssh config. The harness pins this with a negative check on the unit
    source.
12. The dispatcher stops the session of every released leg, but it never stops
    the supervisor daemon: the legs of other projects on this host share it.
    The daemon that predates the scopes needs one manual stop (see The
    background-session machinery of a leg).
13. Each spawn runs in its own auto-named scope. One fixed scope name would
    collide with the scope that still holds the shared daemon, because systemd
    refuses a second unit with the same name.
14. The request deadline defaults to 30 seconds through
    `DISPATCHER_REQUEST_TIMEOUT`, and the unit sets nothing (the reasoning of
    machine decision 9). One timer thread per connection enforces the deadline:
    it shuts the socket down when the time passes, which wakes the blocked read
    of the handler thread. A socket timeout cannot enforce a total, because it
    bounds one operation, and a signal alarm cannot, because it works only in
    the main thread. The timer stops when the reply is written, so the deadline
    bounds the request alone. The handler catches ConnectionError around the
    whole request. A cut request then ends its thread with one info line in
    the journal (issue #280). Without the catch, the stdlib writes an error
    reply to the dead socket. The error handler of the server prints the
    traceback on stderr. That traceback reaches the journal of the service and
    the output of the harness. A client that hangs up mid-request ends the
    same way.
15. The stale-base guard of issue #100 runs as a fetch in the sweep, before any
    spawn, and a fetch that outlasts the retries fails the event loudly instead
    of waiting for the next sweep. A silent wait would repeat the failure mode
    of the issue: a leg starts late and nobody sees why. The owner requeues the
    leg with one comment or push once the host fetches again. The refused spawn
    (exit code 12) runs through the same retry schedule, so a short outage
    costs no leg at either layer. The guard covers the nudge leg as well: a leg
    that cannot fetch cannot push either, so it ends blocked in any case. The
    early comment makes that visible at once.
16. The red gate of issue #110 counts one nudge leg per head commit, not one
    per delivery, because one CI run of one commit can report several failure
    statuses: one workflow per status. The bound is two legs per pull request
    while the gate stays red, and a green status ends the red episode, so a
    gate that turns red again after a green run gets a fresh bound. The count
    records a queued leg, not a spawned one, so the bound counts the attempts
    of the loop, and an event that fails at spawn still spends one nudge.
17. Two delivery kinds feed the red gate (issue #228). The status delivery
    came from the webhook source of the forge family:
    `api.CommitStatusPayload` with `sha`, `state`, `context`, `repository`,
    and `sender`. No delivery of this forge was readable while that rule was
    written. The webhook page read of 2026-11-09 corrected the plan: the
    forge runs Forgejo 17, its page offers no status event, and the
    workflow run events carry the gate. The owner registered the event set
    on 2026-11-09: `Failure` and `Success` under the workflow run events,
    and nothing under the action run section, which the page marks do not
    use (register issue #236, comment 4240). The rule came from the one
    delivery that the owner recorded on issue #228: the action word
    `run_completed`, the conclusion in `run.status`, the head commit in
    `run.commit_sha`, and the repository in `run.repository`. The rule
    matches the payload shape, not the event header, because the record
    holds the body only. The run object also names the pull request or the
    branch in `prettyref`, and the mapping resolves from that field first,
    with the commit of `run.commit_sha` feeding the sha bound of the red
    gate alone (issue #583, machine decision 31). The dispatcher test feeds
    the recorded delivery, so a payload shape that the forge changed fails
    the test before it fails a leg. A conclusion word other than `failure`
    and `success` starts no leg. The two words are the same as the words of
    the status delivery and of the `ci` field that the poll reads.
18. A comment on an issue picks its prompt by the state of the branch
    (issue #110). The dispatcher reads the open pull requests with one `tea`
    call per comment and starts the nudge leg when the branch of the issue
    already holds one. The entity of that leg is the pull request, not the
    issue, because the prompt of a nudge leg ends with a comment on the pull
    request, and the in-flight release listens for that comment. A `/loop`
    comment, a `/watch` comment, and the plain continuation
    of a needs-owner thread take the same path: on a branch with an
    open pull request, more work means the pull request, because the worker
    prompt cannot run there. The ready status takes the same path. The rough
    status does not: the refinement leg starts on the issue whatever the
    branch holds, because its prompt opens no pull request, so the hazard
    that the rule answers does not apply (issue 631).
19. The Go gate of a leg has two halves (issue #110): the toolchain and the
    permission. The toolchain sits in the unit PATH beside python3, because
    the leg of this issue ran without the devShell: the direnv environment of
    the worktree did not load into the spawned session, so a worktree-only
    source of `go` is not reliable. The permission is one allow rule for
    `go test -C modules/programs/cli/project ./...` in `.claude/settings.json`.
    The permission system denies a headless session every write to that file,
    so this leg could not add the rule itself. The owner adds it. Until then,
    a leg that changes the Go module writes in its closing comment that the
    command is denied, and CI stays the first run.
20. The release of an in-flight entry stops the background session of its leg
    by the recorded session id, not by a name lookup. `claude --bg` prints the
    id, the spawn envelope carries it, and the id names one session alone: a
    stopped session stays listed under its name for about an hour, so the name
    of a re-looped leg can name two sessions, and a stop that resolves the
    name can stop more sessions than the released leg (issue #208). An entry
    without an id predates the envelope change, so its name is resolved
    through `claude agents --json` and every listed background session under
    it is stopped — the rule of issue #144, which fixed the releases of
    2026-11-04: `claude stop` refuses a name, so every release of that day
    failed and every leg kept its session and its view window.
21. The stderr of every spawn goes to the journal of the dispatcher unit as
    one INFO line, capped at 500 bytes. The spawn prints the cause of a
    missing view window on stderr, and the journal is the only place a person
    reads it; before this rule the receiver captured the stderr and never
    logged it, so the cause was invisible (issue #208). The same line carries
    the session id, because the output of `claude --bg` rides the same
    stream. A cap keeps one banner-heavy claude from flooding the journal,
    and INFO is the level of the unit log: `DISPATCHER_LOG` can silence it
    like every other INFO line.
22. The spacing of the spawns (issue #225) is one attempt per sweep pass plus
    a floor of 60 seconds between the attempts, not a sleep inside the pass.
    A sleep would hold the sweep lock and a thread of the receiver for
    minutes. The deferral costs about one pass of first-response latency per
    queued leg, and that trade is what the audit asks for. The timer interval
    (one minute) and `DISPATCHER_SPAWN_SPACING` tune the drain rate together.
23. The prompt of a leg carries the entity payload (issue #311). The sweep
    fetches the entity at spawn time and renders the tea reads into the
    prompt, so a leg no longer repeats the entity read of the dispatcher in
    its first turn. The three open questions of the issue got these answers:

    - Freshness. The payload names the time of its read, and the stamp
      precedes the first read. The payload is thus never older than the named
      time. It replaces only the first entity read of a leg. A leg re-reads
      the entity with tea when it needs a newer state. The reviewer re-reads
      the pull request, its comments, its review comments, and its issue
      immediately before the verdict, so a change that arrives during a
      review reaches the verdict. The in-flight map and the supersede rule
      serialize the rest. An event that arrives during a live leg waits in
      the spool, and its leg reads the entity fresh.
    - Size. The rendered payload is capped at 96 KiB through
      DISPATCHER_PAYLOAD_LIMIT. The kernel caps one argument at 128 KiB, and
      the static text of the prompt sits in the same argument, so the cap
      leaves the headroom. A payload past the cap is cut whole. A truncated
      thread could hide a comment from a leg, so the leg reads the entity
      itself instead. The prompt then falls back to the read commands, with
      one sentence that names the cut. A fetch that fails, or an answer that
      holds no JSON, takes the same fallback, and the leg runs (acceptance
      criterion 2 of the issue).
    - Scope. A worker leg carries its issue with its comments. A nudge or
      reviewer leg carries the pull request, its comments, and its review
      comments. It also carries the linked issue with its comments when the
      number resolves. The event carries the number, or the closing keyword
      of the pull request body names it. When the number does not resolve,
      the prompt says so, and the issue read stays with the leg. The re-read
      of a reviewer before its verdict stays a read of the leg in every
      case.
24. The readiness gate is mechanical (issue #356, L2). It checks the presence
    and the form of each answer line, never the content of an answer: the
    quality of an answer belongs to the owner, and the not-applicable audit
    of campaign A reads the abuse of the form. The gate reads the body of
    the issue alone, because comments are the stream and the body is the
    brief, and the amendment flow versions the body. A failed read fails
    open, because the receiver fails open on every tea read and a park on a
    broken read would eat the trigger with no comment able to leave. The
    park comment names the classes and the blocked step. The issue template
    seeds the answer lines of the web form, and the filing rule of the
    factory skill seeds them on the tea path. The gate thus parses the
    shape that both paths seed.
25. The two open items of stage 6 of issue #166, seated by the produced
    project rule of issue #356, L7:

    - The receiver repository filter is seated through configuration, with
      no code change. DISPATCHER_REPO names the one repository that one
      dispatcher instance serves, `jracon/genixis` by default, and the
      receiver ignores every delivery of another repository. A produced
      project gets its own dispatcher instance: its own units, its own state
      directory, and its own webhook. One queue holds one repository,
      because the in-flight map, the pace, and the sweep timer of one
      instance would otherwise let a burst of one project stall the legs of
      every other.
    - The link reader accepts the `Refs` keyword beside the closing keywords.
      A feature pull request of a composition flow must not close its issue,
      and the merge policy of the factory skill permits the delegated merge
      below the protected branches, so the number must resolve anyway:
      links.json and the entity payload read it the same way, and the forge
      closes the issue only on a closing keyword. The board of the project
      binary joins closing keywords only, so a Refs pull request gets its
      own board row instead of the row of its issue.
26. The windowed route of allowlist work (issue #470, option C of the owner)
    rides its own command, `/watch`, since the split of issue #525. The
    original form rode the loop command as the reserved word `window` behind
    the command; the owner ruled the vocabulary of the loop to individual
    commands that take no word arguments, and the register record
    `docs/adr/windowed-watch-command.md` carries the ruling. The command
    costs no new trigger
    surface: the webhook path and the poll path already read the comment
    body, and a label would mark the issue instead of the one start. The
    windowed spawn keeps the headless markers, so the envelope, the session
    id, and the stop-by-id of a release stay, and the forge hook keeps its
    ask-to-deny rule for the session. The watched prompts are the asks of the
    harness, above all the consent prompt of a settings-file edit. The forge
    work of a leg needs no ask. The mode knob is
    `DISPATCHER_WINDOWED_PERMISSION_MODE`. The units set nothing: the code
    default `default` is the deployment value, the same rule as the dontAsk
    knob. The park rule of a windowed leg (issue #505) rides the same prompt.
    The leg asks its park question in the session and posts no park comment
    while it waits. A session that ends with no answer falls back to the park
    comment. The plain prompts, the park discipline of a plain leg, and the
    readiness gate change nothing. No status edge carries the windowed
    variant: a label names no permission mode, so the windowed start stays
    the watch command alone (issue 631).
27. The wake command of issue #525 rides the final comment of a released leg,
    and the released entry carries the routing: a command with an argument
    was the alternative, and it lost because the entity thread already names
    the target — the verdict continuation through the pull request of the
    verdict, the composition handoff through the `Refs` keyword of the pull
    request body — so the signal carries no payload and a creative leg
    cannot name an arbitrary target. The bound keys on the entity pair, not
    on the entity, so a forward chain of fresh pairs runs while a closed
    cycle stops at its second revisit: chains are the wanted shape, cycles
    are the storm shape (issue #267). The `needs-owner` label is the only
    label the dispatcher writes, and its write is one `tea issues edit` per
    trip and one per reset. The reset write runs only when the entity holds
    the label (issue #582): before, every human comment wrote one removal,
    and most of those writes found no label, so one forge round trip per
    comment changed nothing. The payload of an `issue_comment` delivery and
    the entry of the poll listing carry the state, so the reset of a comment
    reads nothing new. The closure of a pull request reads the state with
    one `tea` call, because the receiver reads no label field of a
    `pull_request` delivery. The removal of each waker of a cleared pair
    stays unconditional: the wakegate state cannot see a label that a
    red-gate trip set on a waker, and a pair names an entity only after a
    wake spent it, so no comment of an unpaired entity writes a waker
    removal. A label write that fails logs and leaves the comment as the
    record, because the loop must not stop on a visibility mark. The label
    write on a pull request index rides the shared index space of issues
    and pull requests; a forge that refuses it keeps the comment alone, and
    the bound still resets on the human act. The `needs-owner` label sits
    outside the exclusive status scope of issue 631, so a status edge on a
    stopped thread keeps the mark, and a label edge writes no removal of it
    and touches no wake state.
28. The human surface of the loop is commands only (issue #525, the ruling
    of the owner in the windowed session): plain prose starts nothing, and
    the one exception is the `needs-owner` label, because a thread that the
    loop stopped waits for exactly the prose of a person, and the owner
    ruled the human surface to stay a conversation there. The `gate` label
    retired with the same ruling: its standing any-comment authorization
    duplicated `/loop`, and the poll that discovered issues through it read
    a set that no open issue held at the time of the ruling, so the poll now
    reads all open issues and the commands carry every start. The red-gate
    trip sets the same `needs-owner` mark as the wake trip, because a plain
    answer on a red-stopped pull request must continue that thread too. The
    human surface of the loop gains the human-set status edges beside the
    commands (issue 631), and the register record
    `docs/adr/status-label-edges.md` carries that ruling beside
    `docs/adr/commands-only-triggers.md`.
29. The continuation legs of a branch resume the recorded session of that
    branch (issue #524). The owner ruled the same-id resume: the in-flight
    map and the stop on release serialize the legs of one branch, so the
    write hazard of one shared transcript shrinks to the releases that name
    a dead session and the two-hour backstop alone, and `--fork-session`
    would trade one transcript per branch for a
    fresh id per leg. The record is `sessions.json`, loop mechanics state
    in the family of `inflight.json` and `redgate.json`, not a second
    record of work, so the D13 ruling of issue #350 keeps its meaning; the
    register record of the stance is the owner's to take. Three guards rule
    the resume. A worker or nudge spawn alone takes the flag, because a
    reviewer's value is the independent read. A windowed spawn takes it
    never, because a resumed session keeps its launch flags, so the waiting
    mode of a windowed launch may never reach a session that a plain leg
    started under dontAsk — the same fact binds the other way, because a
    plain leg must not resume a session that a windowed leg started under a
    waiting mode, so the record marks a windowed leg and the next plain leg
    starts fresh. A record whose transcript is gone resumes nothing, so the
    leg starts fresh with the full brief. The brief of a resumed leg names
    where the delta since the prior leg sits and says that the permission
    rules may have changed: the session keeps its denial history, so it may
    skip a command that a fresh leg would retry — the permission-half kin
    of machine decision 19, which seated a permission fact of the harness
    the same way. The harness build on the host must be 2.1.257 or newer
    for the same-id resume, and the work of the issue verified the build
    before it relied on the flag. The `prompt` entry point prints the fresh
    brief of a hand spawn: a hand spawner that wants a resumed leg passes
    `--resume` by hand.
30. The serving trunk of an instance (issue #571) is one knob,
    `DISPATCHER_TRUNK`, empty by default: the default branch of the repository
    serves, and the units of this repository set nothing, because their default
    branch is their trunk. A produced project can hold a second live trunk
    beside its default branch: Minecraft_Recomposed holds `1.0.0/jarmod/trunk`
    as the default branch and `1.0.0/native/trunk` beside it (read with
    `git ls-remote` on 2026-11-20). One instance serves one repository and one
    trunk, because the branch names of the loop are one per repository: a
    second instance of the same repository would collide with the first on
    every branch name, and machine decision 25 bars a second instance of one
    repository. The trunk rules three points of the legs: the worker spawn
    starts at the trunk (`--verified-trunk`, rule 3 and machine decision 1, an
    instance with an empty knob naming the default branch, issue #637), the
    worker prompt names the trunk as the base of the pull request (`tea pulls
    create --base <trunk>`), and the worker and nudge prompts name
    `origin/<trunk>` as the branch that the catch-up merge pulls. The readiness
    gate, the red gate, and the wake rule read no trunk, and an instance with
    an empty knob keeps the single-trunk shape of every prompt.
31. The gate mapping of issue #583 trusts the name of the delivery over its
    commit. The workflow run delivery names its pull request or its branch in
    `run.prettyref`, and the mapping resolves through the listing of the open
    pull requests alone, so one conclusion costs one `tea` call instead of one
    call per open `ai/` pull request: the cost of a gate delivery no longer
    grows with the activity of the loop itself. The list view of the pull
    requests carries no head sha, so the named form cannot also check that
    `run.commit_sha` is the head of the named pull request without paying the
    per-pull read that the change removes. The consequence is accepted: a
    stale conclusion of an older commit of the named pull request reaches the
    red gate and can queue one bounded nudge leg, where the sha scan ignored
    it. The bound of machine decision 16 limits the extra legs, and the
    status delivery, whose payload of the forge family names no branch, keeps
    the scan. The recorded delivery of issue #228 stays the fixture of the
    harness, and its check counts the tea calls of the pass: a forge that
    drops `prettyref` falls back to the scan, and the per-pull read of the
    fallback fails the count.
32. The sandbox tier of issue 607 places each spawn in a transient forking
    user service (`systemd-run --user --service-type=forking --collect`) with
    the properties of the spec file that the tier module writes
    (modules/services/sandbox-tier.nix, security spine under the record
    docs/adr/spine-work-by-agents.md). The forking type makes the unit
    outlive the spawn: the initial process exits after the envelope, and the
    supervisor of the leg and its sessions stay in the cgroup. The spawn
    sets `ExitType=cgroup` beside the service type (dispatcher.py,
    spawn_leg): the unit runs while one process of its cgroup stays, and the
    unit ends when the last process leaves (systemd.service(5), ExitType=).
    The default ExitType=main ends the unit when the process that the
    manager tracks as the main process exits, and Type=forking gives the
    manager no reliable rule for that process over a cgroup that holds the
    supervisor and its sessions (systemd.service(5) of systemd 262,
    GuessMainPID=). The run of issue 634 hit that shape: the exit of the
    session process ended the unit, the kill phase of that stop killed the
    remaining processes of the cgroup, and the harness restart of the
    session found no supervisor inside the unit and started the session
    process outside it, outside every bound of the tier. With the cgroup
    exit type the supervisor survives the exit of a session process, and the
    session process that the harness restart starts runs as a process of
    the supervisor, inside the cgroup of the unit. The owner run that the
    test steps of issue 634 name verifies the placement in a restarted
    session process of a leg on services. The socket
    placement of the supervisor rides one more property that the spawn
    passes beside the spec: the unit binds the socket directory of the leg
    state over the hardcoded daemon root of the harness, and the dispatcher
    links the same directory into the real root, so the attach of the view
    window and the claude calls of the dispatcher reach the supervisor
    while the socket stays in the leg state and the rest of /tmp stays
    private (issue 633). The envelope and
    the exit code reach the dispatcher through files of the leg state
    (`StandardOutput=append:`), because `--pipe` on a forking service waits
    for the whole unit and the envelope carries the true exit code in
    `meta.exit_code` for exactly that consumer shape. The unit sets
    `ProtectHome=tmpfs` rather than `yes`, because systemd documents tmpfs as
    the mode that admits bound subpaths and `yes` as the mode that admits
    none (systemd.exec(5)); the bound carve-outs — the project root, the
    caches, the socket directory of the tmux server of the owner, the socket
    of the nix daemon, the plan and token directory, the tea login, and the
    read-only harness tree of `~/.claude` — are the whole visible home of a
    leg. The runtime directory of dev as a whole stays out of the bounds on
    purpose (the review of pull request 615): it holds the private socket of
    the systemd user manager beside the tmux socket, and a leg that reaches
    that socket starts further transient user units that carry none of the
    tier properties, so every bound of the tier would be escapable from
    inside the leg; the tmux socket directory alone is bound, with the minus
    prefix, so a leg that starts before any tmux server runs opens no view
    window and works on. The agent unit of each leg carries its own subset
    of the same properties — the read-only tree, the hidden homes beside the
    leg state of its socket, the empty capability set, the service syscall
    filter, and no address at all — because the agent holds the push key
    alone and needs nothing beyond its socket. The git transport
    of a leg runs without any file of `~/.ssh`: the dispatcher starts one
    ssh agent per spawn in its own transient unit, loads the push key into
    it, and points `SSH_AUTH_SOCK` at it, so the leg can sign but never read
    the key; `GIT_SSH_COMMAND` pins `-F /dev/null`, the user `git`, the port
    of the forge container, `BatchMode`, and the committed host key pin
    through `HostKeyAlias` under the bracketed host:port token of the
    committed line, because the alias replaces the lookup name alone and
    carries no port on its own (issue 644). The connect target stays the
    name of the forge ssh host: the ssh port of the forge is the publish of
    its container, a publish of Podman is a DNAT rule that rewrites the
    destination of every connect to the container address, and the egress
    filter of a leg unit reads the destination after that rewrite, so the
    name route answers once the allow list names the container address
    (issue 658, the owner probe of 2026-11-25). One `GIT_CONFIG_*` entry
    rewrites the remote URL onto the tailnet name of this host, so the ssh
    URL forms of the forge name carry the same transport
    (docs/adr/forge-naming-chain.md). The egress bound — deny any address,
    allow the loopback, the tailnet range, and the container address of the
    forge — keeps
    DNS working through
    either resolver of the host and leaves ssh direct, and every http tool
    of a leg reaches its allowlisted destination through the squid of the
    tier module alone. The entry for the forge names the container address
    and no address of the host: a publish of Podman is a DNAT rule that
    rewrites the destination of a connect to the container address, the
    egress filter of a leg unit reads the destination after that rewrite,
    and the owner probe of 2026-11-25 proved that an allow entry for the
    LAN address of the publish passes nothing (a root-level unit with that
    one entry still timed out, issue 658). The container claims the address
    with a static assignment (lib/oci-containers.nix,
    forgeContainerAddress). A spawn whose spec is absent or unreadable runs the
    plain scope of the code before the tier, so the loop degrades to the
    unbounded state instead of stopping, and the probe harness quotes that
    state; the after run on the switched host is the oracle of the tier
    (Readiness B of issue 607).
33. The leg units of the sandbox tier move from the transient user services
    of machine decision 32 to instances of the two root-authored templates
    `leg-unit@.service` and `leg-agent@.service` on the system manager
    (modules/services/sandbox-tier.nix), and the spawn and stop calls of
    the receiver ride a polkit delegation scoped to those two template
    names and to the start and stop verbs (the ruling of the owner on
    issue 607, 2026-11-24: the system manager with delegation). The move
    answers the platform fact that the user manager skips the IP firewall
    for non-root: under it the raw-socket controls of the probe harness
    quoted the open state, and no config closed the gap. The delegation
    cannot ride the transient-unit property path of `systemd-run`: the
    StartTransientUnit call of systemd 262 passes the unit name and verb
    as polkit details (bus_verify_manage_units_async_impl,
    src/core/dbus-util.c), but the properties of the transient unit ride
    the same authorized call, so a name-scoped grant would still let the
    caller set `User=root` on a leg-named unit and escape the tier from
    inside a leg. StartUnit carries no properties, so the instances run
    exactly the properties the templates carry, and the per-spawn argv and
    env ride the request file of the leg state that the ExecStart executor
    `leg-run.py` reads and execs as the user the template names. The
    instance name is the branch slug alone, because `%i` is the whole
    instance string and the executor must derive the state directory from
    it, and one branch holds one leg at a time (claim_slot); the spawn
    stops its two instances before it starts them, so a leftover of a
    crashed leg cannot answer the start of the new spawn with its old
    envelope. The knob of the tier moves from the spec file to the
    DISPATCHER_TIER environment of the dispatcher units (dispatcher.nix),
    the spec file `/etc/genixis/sandbox-tier.json` and its loader leave the
    tree, and the leg-units check of lib/checks.nix guards the evaluated
    text of the two templates and of the polkit rules in their place
    (docs/ci.md, item 30). SetUnitProperties rides the same polkit action
    with the verb set-property, so the delegation denies it: the verb gate
    is load-bearing, and the check holds a fixture for it.
34. The status edges of issue 631 carry three knobs, `DISPATCHER_ROUGH_LABEL`,
    `DISPATCHER_READY_LABEL`, and `DISPATCHER_REPORT_LABEL`, with the names of
    the reference set as the defaults, and the units set nothing: the code
    default is the deployment value. The edge state lives in one file,
    `labels.json`, that the webhook path and the poll path share, so one
    label change spends one edge whatever the path that sees it. The webhook
    path trusts the first label delivery of an issue, because the forge fired
    the delivery for a change, and diffs the later deliveries against the
    recorded state; the poll path takes the first sighting of an issue as
    its baseline, the same rule as the comments. The state of a closed issue
    records nothing, so a re-opened issue takes the baseline of the poll.
    The webhook rule reads the label actions of the issues shape
    (`label_updated`, `label_cleared`) whatever the event header names the
    delivery, and no delivery of this forge was readable while the rule was
    written, so the rule keys on the payload shape, the pattern of machine
    decision 17. A label change on a pull
    request routes nothing: the shape of its delivery carries no issue
    object, and the leg that an edge names works an issue. The refinement
    spawn copies the
    worker spawn: the verified trunk, the plan, the resume, and the tier
    ride the same code path, the prompt is the only delta, and the leg is
    never windowed, because a label names no permission mode. The lost
    alternatives: a per-path edge state, because the webhook and the poll
    would start the same leg twice when both run; a changed-label field of
    the payload as the edge source, because no recorded delivery of this
    forge names one, and the diff against the recorded state answers without
    it.
35. The ask status `status/needs-input` joins the family as its fifth member
    (machine decision 34, the refinement that the comment of the owner on
    pull request 669 asked for), with the knob `DISPATCHER_INPUT_LABEL` and
    the same default rule as the other three: the units set nothing. It
    triggers nothing on both paths as a label change: the answer of the person
    is prose on the thread, and machine decision 36 rules the resume of that
    prose. The writers are the refinement leg, which writes
    it when its report asks at least one question, and the readiness park,
    which sets it beside the park comment, so the board names each wait for
    a human answer. The ask status is no edge label, so a write of it by the
    agent login starts nothing on the webhook path and the poll path alike.
    The re-set of a status is one add, because the exclusivity of the scope
    replaces the status that the issue holds; when the forge holds two
    status labels, the re-set is a removal and then the add, so the owner
    verifies the replacement on a test issue before the protocol runs. The
    lost alternative: a status label for every stage that a leg runs
    through, because a status names a wait where a person acts, and the
    motion of a leg between two waits is already visible in the session, the
    branch, and the pull request.
36. The ask status carries its own resume (the comment of the owner on pull
    request 669 of 2026-11-25 15:53 asked for an automatic response instead of
    a command set): a plain comment of a person on an open issue that holds
    the ask status starts the refinement continuation on both paths, the same
    shape as the needs-owner rule, so no command and no re-set is needed. The
    continuation folds the answers of the thread into the brief, then either
    asks its next question and writes the ask status again, or reports the
    brief final and clears the ask status with
    `tea issues edit <n> --remove-labels status/needs-input`, which the hook
    allows because the name sits outside the key; the human-only names stay
    denied, so a leg clears no status that a person set. An issue that holds
    both the needs-owner mark and the ask status routes a plain comment
    through the needs-owner rule, because a stopped thread resumes through
    the bound reset of that rule. The start of the next stage stays with the
    person: the ready set runs the gate and the worker, and the
    agent-authored advance of a label waits for stage 2 of the issue. The
    lost alternatives: an answer command on the loop, because it would cost
    one human comment per answer, the cost that the issue names; the advance
    of the ready label by the continuation inside this stage, because the
    human-approved action list of stage 2 rules that transition.
37. The stall release of issue #665 reads the transcript of the session as
    the progress signal, not the state word alone. The harness reports the
    word `working` for a session that works and for a session that hangs at
    one model call alike, so the word alone cannot bound the block. The
    transcript is the file the harness appends to as the session works, the
    dispatcher already derives its path for the resume (issue #524), and the
    mtime of the transcript is the last progress the harness wrote, so the
    grace measures the silence of that file. The grace is 30 minutes
    (`DISPATCHER_STALL_GRACE`), below the two-hour TTL, and the units set
    nothing: the code default is the deployment value. The grace judges a
    plain entry alone: a windowed entry waits at its prompts or at its park
    question with no transcript write, and that wait is no hang, so the TTL
    stays its backstop, the same asymmetry as the dead-session rule. A
    transcript the read cannot find, a branch with no session record, and an
    entry that names no entity judge nothing and hold, because a failed read
    must not release a live leg. One accepted risk rides the signal: a single
    step of a plain leg that writes nothing to the transcript past the grace,
    for example one long gate command, trips the release the same way a hung
    call does, and the replacement leg of the queued event resumes the
    recorded session, so the work recovers and the comment names the cause.
    The release stops the session, comments
    once on the entity, and wakes nothing. The comment names the deliveries
    that arrived while the block held and were superseded, because the
    supersede feedback belongs to the block and not to every command; a
    comment on every superseded `/loop` was the alternative, and it lost as
    noise in the normal case, where the pending event runs when the leg
    ends. The self-trigger rule skips the report by its first words
    (`dispatcher: the leg session `): the report rides the login of the
    agent, and the same pass spawns the replacement leg of the entity,
    whose entry a release by the report would stop together with its
    session. The record of a superseded delivery names the pending delivery
    in its `superseded_by` field, and the journal names both deliveries, so
    the trace shows outside the state directory whatever path the owner
    reads.
38. The dead-session release of issue #605 parks its freed entry for the
    wake rule instead of dropping it (issue #612). The final comment of a
    leg and the end of its session are two events, and a sweep pass inside
    the delivery window of the comment released the entry first, so the
    comment freed nothing and its wake was lost. The park is a record of
    `wakehold.json`, loop mechanics state in the family of `wakegate.json`,
    and the read of `release_entity` folds the parked pairs in when the
    in-flight map holds no live entry of the entity. Re-deriving the target
    from the entity of the comment alone was the alternative, and it lost
    because a comment that frees no entry must wake nothing, the standing
    rule that keeps a stray `/wake` of a confused leg quiet: only a comment
    that matches a released entry, live or parked, carries the routing. The
    record answers the first comment of the agent login on the entity,
    whatever that comment frees, so a comment that frees a live entry spends
    the record too and no second wake follows. The window is ten minutes
    (`DISPATCHER_WAKE_HOLD`): the webhook of the forge delivers the comment
    seconds after the session ends, the poll fallback reads it on its
    two-minute timer, and the units set nothing, the code default is the
    deployment value, the same rule as the stall grace. A record older than
    the window answers nothing, so a late stray comment wakes no leg, and
    the read prunes the expired records of every entity. The record rides
    the dead-session release alone: the stall release of issue #665 stops a
    session that still works, and the final comment of a leg follows the end
    of its turn, so no comment of that leg can sit in delivery when a stall
    release runs, and a leg past the two-hour TTL posted its final comment
    long before the release or posted none.
39. A released leg session whose stop failed stays on record (issue #696).
    The stop names one session by its recorded id, and a stop that answers
    nonzero leaves the session live: it can finish its turn at the timeout of
    its hung call and post its final comment, and the self-trigger rule reads
    that comment as the declared end of the successor legs of its entity, so
    their sessions stop mid-turn. Blocking the release on the record was the
    first alternative, and it lost: a comment of the agent login on an entity
    with a recorded session is indistinguishable from the genuine final
    comment of the leg that holds the entry, and a blocked release would
    strand the successor to the two-hour TTL and lose the wake of its final
    comment. A retry of the stop was the second alternative, and it lost on a
    budget the owner did not set: the issue asks for the record first. The
    release keeps its shape, and the entity names the exception: the failed
    stop posts one comment that names the session, the branch, and the
    entity, and every comment of the agent login that releases in-flight
    entries of the entity inside the window posts one comment that names the
    record, in the words of the mark, so no leg of the loop reads it as the
    declared end of a leg. The window equals the in-flight TTL
    (`DISPATCHER_STOPFAIL_HOLD`, default 2 hours): the TTL is the standing
    bound of the loop for a leg past its end. The read skips the record of a
    session that sits among the freed entries themselves, because the release
    that wrote the record freed that session, and the exception names a
    successor of it. One accepted risk rides the window: a genuine final
    comment of a successor inside the window names an exception that did not
    happen, one comment of noise beside the record the owner reads.
40. The self-trigger rule gains its ruled relaxation (issue 631, stage 2),
    and the human-approved action list of the owner carries it: the
    refinement final starts the research leg, the dispatcher writes the
    ready label, the research report starts its adversarial review
    agent-chained, and the mid-run park of a worker leg writes the ask
    status, the four answers of the owner in the windowed run of 2026-11-25
    on the issue. The edge of the final refinement is the cleared ask
    status: the continuation writes the clear when its report asks no
    question, and the diff of the label state against labels.json names the
    clear beside the edges, so both trigger surfaces reach it through one
    shared state. The diff that shows the clear together with a new edge
    belongs to a re-set of a person and routes its edge alone. The clear of
    the park writes nothing: the park sets the ask, and the ruled clear
    names the final report of a continuation. The bound is the wake bound
    as the template (`breedgate.json`, `DISPATCHER_BREED_LIMIT`, default 2)
    and counts the fired transition, not the legs it queues: one chain of
    an issue spends one count on the final refinement and one on the review
    of its research record, so the default admits exactly one chain per
    human act. The reset rides the wake reset: a human comment, the closure
    of the pull request, and a person-set label edge clear the bound, the
    design default of the stage park that the owner let stand, and the same
    act closes the open point of pull request 669 whether an edge resets
    the wake bound. The research mark `/research` names the record comment
    of the research leg and the verdict comment of its review: the marked
    comment frees the research entries of its entity alone, so the parallel
    worker keeps its slot and its session, and the review start keys on the
    freed entry of the research kind, the eligibility rule of the wake. The
    lost alternatives: the wake command as the carrier of the review start,
    because a worker handoff and a research record would share one word and
    the misroute would lose the handoff; the research leg on the worker
    branch, because the in-flight map would serialize the record behind the
    implementation and the owner ruled no hard gate; the ask comment of the
    continuation as the edge, because the diff of one shared label state
    reaches both trigger surfaces and a comment shape reaches the webhook
    path alone; a per-leg count of the bound, because one transition queues
    the research leg and the worker leg together and a chain of two
    transitions would trip a per-leg bound of two mid-chain. One accepted
    deviation rides the poll path: the poll reads no author of a change, so
    a person that clears the ask status by hand, with no add, fires the
    chain on the poll path alone; the webhook path sees the sender and
    ignores the change, and the board protocol moves a status by an add, so
    the hand clear with no add is off protocol. The event name of a poll
    label pass carries the time of the pass, so a second edge of the same
    issue inside the prune window of the processed records still queues its
    leg: the stable name of the first stage let the second re-set of an
    open issue inside fourteen days land on a spent record.
