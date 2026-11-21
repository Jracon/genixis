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
| `dispatcher.py` | One program with four entry points: `serve` (the receiver), `run` (one spool pass), `poll` (the tea fallback), `prompt` (print the brief of one leg, and start no leg). |
| `dispatcher-test.py` | The stub harness of the program: stub `project`, `tea`, `git`, `systemd-run`, and `claude` binaries in a temporary state directory. The CI of a pull request runs it. |
| `sandbox-probe.py` | The probe harness of the sandbox tier of issue 555: one probe per control, run live on `services` inside a session. The CI of a pull request runs the static checks of the file and no live probe. |
| `dispatcher.nix` | The secret declaration, the linger of `dev`, and the user services with the gate environment of a leg. Loads only on the `services` host. |
| `webhook.age` | The shared secret of the webhook. The owner creates it with `agenix -e`. The module stays off until the file exists. |

## State

All state lives in `~/.local/state/dispatcher` of `dev`. Standing principle 6 of
issue #74 adds it to the backup set.

| File | Content |
| --- | --- |
| `events/` | Accepted deliveries that wait for a spawn. One JSON file per delivery, named after the delivery ID. |
| `processed/` | Deliveries that a spawn consumed or that a pending event superseded. Pruned after 14 days. The file name is the delivery record. |
| `failed/` | Deliveries whose leg failed after every retry. |
| `inflight.json` | The in-flight map: branch to session name, session id, entity, and start time. |
| `links.json` | The pull request to issue links, read from the closing keyword or the `Refs` keyword of each pull request body. |
| `sessions.json` | The session record of the branches: branch to the latest transcript UUID of its leg, the worktree it runs in, and whether a windowed leg holds it. The record survives the release of the in-flight entry, so a later worker or nudge leg of the branch resumes the session (issue #524). |
| `poll-cursor.json` | The cursor of the poll fallback: the newest comment id of each issue and of each open `ai/` pull request, the pull requests it already queued, and, per pull request, the last CI status with its head commit that it saw. |
| `redgate.json` | The bound of the red gate: per pull request, how many nudge legs a red gate started, which head commit got the last one, and whether the dispatcher already told the owner. |
| `wakegate.json` | The bound of the wake: per entity pair, how many agent wakes the pair queued, and whether the dispatcher already told the owner. |
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
| `issue_comment` | The sender is the agent login `claude-bot`. | The in-flight entries of the entity are released, and the sessions of their legs stop. A comment that releases an entry may begin with `/wake` (see The wake rule and its bound); every other agent comment starts nothing. This is the self-trigger rule, narrowed by issue #525. |
| `issue_comment` | The issue is closed. | Ignored. |
| `issue_comment` | An open issue, and a comment of a person whose first word is `/loop` or `/watch`. The prose of the answer may sit on the same line, on later lines, or nowhere. The command `/watch` starts the windowed variant (see The windowed route of allowlist work). The branch of the issue holds no open pull request. The readiness gate passes. | Worker leg on `ai/issue-N`. A class that the gate finds unanswered parks the issue, and no leg starts. |
| `issue_comment` | The same, and the branch of the issue holds an open pull request. | Nudge leg on that pull request. The worker prompt would tell the leg to open a second pull request, and the forge refuses that. |
| `issue_comment` | An open issue that holds the `needs-owner` label, and a plain comment of a person: the loop stopped the thread, and the prose continues it (issue #525). | Worker leg, or nudge leg by the branch state, through the same branch-state rule as a command comment. The same comment resets the wake bound and removes the label. |
| `issue_comment` | A pull request whose head branch starts with `ai/`, and a comment of a person whose first word is `/loop` or `/watch`. The command `/watch` starts the windowed variant (see The windowed route of allowlist work). | Nudge leg on the head branch: a worker leg that continues the work of that pull request. The head comes from one `tea pulls` read. The variant of the comment starts the nudge leg in the windowed shape. |
| `issue_comment` | A pull request whose head branch starts with `ai/`, that holds the `needs-owner` label, and a plain comment of a person. | Nudge leg on the head branch, with a cause that names the stop. The same comment resets the wake bound and removes the label. |
| `issue_comment` | A plain comment of a person on any other entity. | Ignored. Plain prose starts nothing (issue #525); the commands and the `needs-owner` label carry every start. |
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
   answered. A new `/loop` comment on the issue requeues the leg, so the gate runs
   again after the owner edits the body.
3. A read that fails fails open, like every `tea` read of the receiver. The gate logs a
   warning, the leg starts, and the gate runs again on the next trigger. A payload
   fetch that fails too sends the leg to read the issue itself.
4. The park comment comes from the agent login, so the self-trigger rule treats it as a
   release of the entity, never as a trigger. The wake rule agrees: a park comment
   releases no in-flight entry, so it wakes nothing.

The gate writes no state of its own (decision D13): the park is a comment, the answers
are the body of the issue, and no second record exists. Campaign A of issue #350 reads
the not-applicable lines for abuse.

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
continues, or stops the session by hand. The TTL keeps its role as the backstop of a
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
   background-session machinery of a leg). An entry older than two hours counts as
   a crashed leg. An event that finds its branch busy stays in `events/`, and the
   next sweep retries it, so an event that arrives during a live leg runs when the
   leg ends. A delivery for a branch that already has a pending event is
   superseded: it is recorded and never spawns, because one pending event per
   branch is enough, and a leg reads its entity fresh.
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
   the full brief. A worker event of an instance whose serving trunk differs
   from the default branch adds `--from <serving trunk>` (`DISPATCHER_TRUNK`),
   so the branch starts at the tip of the trunk (issue #571). A nudge branch
   exists already, and rule 6 prepares the reviewer branch, so neither names a
   base. Every other part of the command stays the same. The prompts
   name the `factory` skill. The scope keeps the background-session machinery of
   the leg out of the cgroup of the receiver unit (issue #93).
4. Before every spawn, the sweep fetches `origin` in `main/` of the project clone
   (`refresh_clone`). The fetch follows the retry schedule of the spawn. A fetch that
   fails after every retry fails the event and comments on the entity: no leg starts
   on a base that the clone cannot verify against the origin of the serving trunk
   (issue #100). The fetch also gives the reviewer branch its fresh tip. The
   spawn itself refuses the same case with exit code 12, so the guard has two
   layers.
5. The envelope of the phase 3 binary decides the outcome. Exit codes 11 and 12 are
   retried twice, after 30 and 120 seconds. Exit code 7 comments on the entity and
   names `jracon`: this needs the owner. Exit code 2 comments on the entity: it names
   a defect in the dispatcher. Every other failure comments on the entity and stops.
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
2. No unit sets a sandbox option. Every sandbox option in a user unit implies
   `PrivateUsers` (systemd 254), the user namespace makes root-owned files read
   as `nobody`, and ssh then refuses the store symlink `~/.ssh/config` of dev,
   so every fetch and push of every leg fails. The run of issue 93 proved it:
   the fetch of the spawn failed, the branch fell back to a stale local main,
   and the leg worked on a month-old tree. The isolation of `/etc/nixos` waits
   for the sandbox tier of phase 5 of issue 74, which must place the isolation
   where it does not break ssh. An impure flake check passes inside a leg even
   without that isolation. The ZFS pool supplies a default `hostId`, so the
   evaluation of `nixosConfigurations.media` needs no `hostId` from the
   machine-local configuration (docs/containers.md holds the record). A leg
   gates itself with the local run of that check before the push. The CI gate
   of the pull request stays the authoritative run of the merge.

## The sandbox probe harness

The sandbox tier of issue 555 bounds each spawned session with a transient systemd unit and an allowlisting
forward proxy on `services`. The tier is security spine: an agent writes the unit and the proxy config, and
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
5. The forge probe reads the session settings for the hook, and feeds one push to the default branch, one
   compound command, and one entity edit to `forge-hook.py` of the same tree, with the markers of a spawned
   headless session set. No case reaches the network.

A control holds when the action fails. Before the tier lands, the four sandbox controls quote the open
state and the run exits 1. After the tier lands, every control holds and the run exits 0. The forge control
holds before and after, because the hook answers above every local tier. The verdict of Trust criterion 11
of docs/agent-context.md waits for a run in which every control holds.

The harness runs live on `services` alone, because the runner of the gate is not the sandbox: the pull
request gate runs the static checks of the file and no live probe (lib/checks.nix). The direct command needs
one allow rule in `.claude/settings.json`. The settings-file gate keeps the rule with the owner (issue 470),
so the rule lands with the tier. Until then, a leg runs the harness through the nested print-mode session
that the AGENTS.md of the repository names, and the owner runs it by hand.

## The background-session machinery of a leg

A `claude --bg` run starts no session process of its own. The first run of the
user starts one supervisor daemon, and every later run connects to it (verified
live, issue #93). The daemon and its pool of `bg-spare` processes are children
of that first run, so they land in the cgroup of the unit that ran it. With the
receiver as that unit, the machinery stayed after each leg and the unit memory
grew with every leg: it peaked at 768 MB. Nothing reaps the daemon. Only
`claude daemon stop`, an update, or a kill from outside ends it.

Two mechanisms hold the machinery bounded (issue #93):

1. Each spawn runs behind `systemd-run --user --scope --collect --quiet
   --expand-environment=no`, so the daemon and the spares sit in transient
   scopes beside the receiver unit, never inside its cgroup. The scope mode
   runs the spawn as a direct child with the environment of the caller, and
   it gives the exit code of the spawn back, so the envelope and the exit
   code table still work. The scope of the first leg after a daemon start
   holds the daemon until the daemon stops. The scope of every later spawn
   ends with the spawn. The receiver unit returns to its baseline task count
   and memory when no spawn runs.
2. Every release of an in-flight entry stops the session of its leg: the
   comment of the agent login on the entity, the closed pull request, and
   the two-hour TTL of a crashed leg. The spawn envelope records the session
   id that `claude --bg` printed, and the release stops that id, so the stop
   names one session alone: a stopped session stays listed under its name
   for about an hour, so the name of a re-looped leg can name two sessions
   and a stop by name can hit the wrong one (issue #208). An entry that
   predates the id falls back to the name lookup of issue #144: `claude
   stop` accepts no name, so the release reads `claude agents --json` and
   stops every listed background session under the recorded name. The
   conversation stays, so the owner can resume it — and the loop does: the
   session record of the branch (`sessions.json`, issue #524) survives the
   release, and the next worker or nudge leg of the branch resumes the
   transcript through the UUID of the latest envelope. A stop of a resumed
   leg names the id of the latest envelope, whatever id the harness printed
   for the resume. A session that ended
   stops by itself only after about one hour, and a name that no listed
   session holds needs no stop. The stop also ends the view window of the
   leg (see The view window of a leg).

The dispatcher never stops the supervisor daemon. The legs of other projects
on this host share it, so a stop would end sessions that the dispatcher does
not own.

One step after the change that introduced the scopes: stop the daemon that
predates it, or it keeps every leg inside the receiver unit. As `dev`, when no
leg runs: `claude daemon stop`. The next leg starts a fresh daemon inside its
scope.

## The view window of a leg

Each spawn opens one view window for its leg, in the tmux session named after
the project on this host (issue #116). The window is named after the branch,
and its pane runs `claude attach` on the background session of the leg, so the
owner watches the leg work. A windowed leg also takes its answers there: the
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
worker legs from new command comments. A plain comment on an issue that holds the
`needs-owner` label continues that thread, the same rule as the webhook path. It also
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
with `/wake` wakes through the same rule as the webhook (issue #525). The poll
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
   same command, the value of the `DISPATCHER_TRUNK` knob of its instance.
   Stay near the session and answer its prompts.
4. Start a reviewer leg: point `ai/review-N` at `origin/ai/issue-N`, set its upstream,
   then spawn it the same way.
5. Watch the sessions: `claude agents`, `claude attach <id>`, `claude logs`,
   `claude stop`. Each headless leg has one view window in the
   tmux session of the project, named after the branch (see The view window of
   a leg). `project open dev@services:genixis` shows that session, and its
   status bar lists the window of each leg.
6. See the state of the loop: `cat ~/.local/state/dispatcher/inflight.json` and
   `project list genixis`.

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
   with the recorded id of a released session. The `claude agents --json` read of
   the name fallback only reads the session listing.
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

1. The worker branch of an instance that serves the default branch spawns without
   `--from`: the dispatcher runs from the home of `dev`, so the branch starts at
   the default branch, and no `projectBase` is written. An instance whose serving
   trunk differs passes `--from <serving trunk>` (issue #571). The tool then
   records the trunk as the `projectBase` of the branch, and that record is
   correct: the pull request of the leg opens against the same trunk, and the ask
   rule of the forge hook for a push to a `projectBase` branch touches a branch
   that no leg pushes. Preparing the worker branch with plain git, the pattern
   of rule 6, lost: it copies a base
   path that the tool already owns, and a trunk name that no ref holds would need
   its own failure handling, while `--from` answers through the exit-code table
   of the tool.
2. The reviewer branch is prepared by the dispatcher with plain git, not with
   `--from`, for the reason in dispatcher rule 6.
3. The final comment of a leg releases its in-flight entry, because the prompts
   make that comment the declared end of a leg. The release also stops the
   background session of the leg, so an agent comment that arrives before the end
   can no longer let a second leg run on a branch whose first leg still lives.
   The two-hour limit stays the backstop for a leg that crashed without a
   comment. There is no reliable way to read the liveness of a `claude --bg`
   session from a script.
4. Both legs run under the plan `zai`. A second plan for the reviewer, when one
   exists, is one environment change in the unit (`DISPATCHER_REVIEWER_PLAN`).
5. The `/loop` and `/watch` command prefixes are fixed. A command comment of a
   person starts a leg on an open issue; a plain comment starts nothing, on an
   issue and on a pull request, unless the `needs-owner` label marks the thread
   as one the loop stopped (issue #525). The retired `gate` label triggered a
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
    comment, a `/watch` comment, a woken handoff, and the plain continuation
    of a needs-owner thread take the same path: on a branch with an
    open pull request, more work means the pull request, because the worker
    prompt cannot run there.
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
    readiness gate change nothing.
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
    the bound still resets on the human act.
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
    register record `docs/adr/commands-only-triggers.md` carries the ruling.
29. The continuation legs of a branch resume the recorded session of that
    branch (issue #524). The owner ruled the same-id resume: the in-flight
    map and the stop on release serialize the legs of one branch, so the
    write hazard of one shared transcript shrinks to the two-hour backstop
    alone, and `--fork-session` would trade one transcript per branch for a
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
    starts at the trunk (`--from`, rule 3 and machine decision 1), the worker
    prompt names the trunk as the base of the pull request (`tea pulls create
    --base <trunk>`), and the worker and nudge prompts name `origin/<trunk>` as
    the branch that the catch-up merge pulls. The readiness gate, the red gate,
    and the wake rule read no trunk, and an instance with an empty knob keeps
    the single-trunk shape of every prompt.
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
