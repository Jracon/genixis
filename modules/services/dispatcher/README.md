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
| `dispatcher.py` | One program with three entry points: `serve` (the receiver), `run` (one spool pass), `poll` (the tea fallback). |
| `dispatcher-test.py` | The stub harness of the program: stub `project`, `tea`, `git`, `systemd-run`, and `claude` binaries in a temporary state directory. The CI of a pull request runs it. |
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
| `inflight.json` | The in-flight map: branch to session, entity, and start time. |
| `links.json` | The pull request to issue links, read from the closing keyword of each pull request body. |
| `poll-cursor.json` | The cursor of the poll fallback: the newest comment id of each gated issue, and the pull requests it already queued. |
| `sweep.lock` | The lock that keeps one sweep at a time. |

## Event rules

The receiver verifies the HMAC-SHA256 signature of each delivery against the secret,
then applies these rules. Every rejected or ignored event still answers 200, so the
forge does not retry it. Only a delivery with a wrong signature gets 403.

| Event | Rule | Result |
| --- | --- | --- |
| `ping` | Always. | Ignored. |
| any | `repository.full_name` is not `jracon/genixis`. | Ignored. |
| `issue_comment` | The sender is the agent login `claude-bot`. | Ignored. This is the self-trigger rule. |
| `issue_comment` | The issue is closed. | Ignored. |
| `issue_comment` | An open issue with the gate label, or a comment that starts with `/loop`. | Worker leg on `ai/issue-N`. |
| `issue_comment` | A human comment on a pull request whose head branch starts with `ai/`. | Nudge leg on the head branch: a worker leg that continues the work of that pull request. The head comes from one `tea pulls` read. |
| `pull_request` | `opened` or `synchronized`, head branch starts with `ai/`. | Reviewer leg on `ai/review-N`. |
| `pull_request` | `closed`, head branch starts with `ai/`. | The in-flight entries of both legs of the pull request are released. No spawn. |
| `pull_request` | Any other action or head branch. | Ignored. |

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
   --permission-mode dontAsk <prompt>`. The prompts name the `factory` skill. The
   scope keeps the background-session machinery of the leg out of the cgroup of
   the receiver unit (issue #93).
4. The envelope of the phase 3 binary decides the outcome. Exit codes 11 and 12 are
   retried twice, after 30 and 120 seconds. Exit code 7 comments on the entity and
   names `jracon`: this needs the owner. Exit code 2 comments on the entity: it names
   a defect in the dispatcher. Every other failure comments on the entity and stops.
5. The reviewer branch is not created with `--from`. A `--from` spawn would record the
   worker branch as a `projectBase`, and the forge hook then answers `ask` for every
   later push of the worker, which a headless leg cannot answer. Instead, the
   dispatcher points the reviewer branch at the tip of the worker branch with plain
   git in `main/` and sets its upstream, so the reviewer starts with
   `git pull --ff-only`.

## The environment of a leg

A spawned leg inherits the environment of the dispatcher unit, so the unit is
the only place that can give the leg the machine gate (issue #96):

1. The unit PATH starts with the store path of python3. The two allowlisted
   harness commands of the repository run inside a leg.
2. No unit sets a sandbox option. Every sandbox option in a user unit implies
   `PrivateUsers` (systemd 254), the user namespace makes root-owned files read
   as `nobody`, and ssh then refuses the store symlink `~/.ssh/config` of dev,
   so every fetch and push of every leg fails. The run of issue 93 proved it:
   the fetch of the spawn failed, the branch fell back to a stale local main,
   and the leg worked on a month-old tree. The isolation of `/etc/nixos` waits
   for the sandbox tier of phase 5 of issue 74, which must place the isolation
   where it does not break ssh. Until then, an impure flake check inside a leg
   fails on the host configuration of `services`; the CI gate of a pull request
   is the authoritative run.

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
2. Every release of an in-flight entry stops the session of its leg with
   `claude stop <name>`: the comment of the agent login on the entity, the
   closed pull request, and the two-hour TTL of a crashed leg. The
   conversation stays, so the owner can resume it. A session that ended stops
   by itself only after about one hour.

The dispatcher never stops the supervisor daemon. The legs of other projects
on this host share it, so a stop would end sessions that the dispatcher does
not own.

One step after the change that introduced the scopes: stop the daemon that
predates it, or it keeps every leg inside the receiver unit. As `dev`, when no
leg runs: `claude daemon stop`. The next leg starts a fresh daemon inside its
scope.

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

The fallback polls the gated issues with `tea` every two minutes and queues the same
worker legs from new human comments. It also queues one reviewer leg for each new
open pull request on an `ai/` branch. The first poll records the baseline and queues
nothing, so the fallback never replays the comment history of the repository: a
comment that arrived before the first poll needs one new comment or the webhook. An
agent comment that the poll reads releases the worker slot of that issue. The slots
of pull request legs free only through the webhook or the two-hour limit, because
the poll reads no pull request comments. The fallback does not re-review after a
push to the same pull request: that part needs the webhook. The cursor file makes
each poll idempotent.

## The owner can run every step by hand

Standing principle 8 of issue #74. Each step of the loop, as the owner or as `dev`:

1. Read the entity: `tea issues N --comments`, `tea pulls N`, `tea comments list N`.
2. Start a worker leg: `project spawn genixis ai/issue-N --plan zai --headless
   --permission-mode acceptEdits "<prompt from dispatcher.py>"`.
3. Start a reviewer leg: point `ai/review-N` at `origin/ai/issue-N`, set its upstream,
   then spawn it the same way.
4. Watch the sessions: `claude agents`, `claude attach "genixis: ai/issue-N"`,
   `claude logs`, `claude stop`.
5. See the state of the loop: `cat ~/.local/state/dispatcher/inflight.json` and
   `project list genixis`.

## Security notes

1. This directory is security spine under standing principle 7 of issue #74. Review
   `dispatcher.py` and `dispatcher.nix` line by line.
2. The secret file is `0400`, owned by `dev`, group `users`. The receiver reads it
   once per delivery, so a rotation needs no restart.
3. The dispatcher writes only inside its state directory. It starts processes only
   through `project` (inside a transient user scope), `git` (in `main/` of the
   project clone), `tea comments add`, and `claude stop` for a released session.
4. The receiver has no authentication beyond the webhook signature. It is reachable
   only from the Podman bridge of the host: the module opens the port on the bridge
   interface alone, and no other network reaches it.
5. The receiver answers one thread per delivery. It closes a connection that sends
   no data within `DISPATCHER_READ_TIMEOUT` seconds, so a stalled client cannot pin
   the threads of the receiver (issue #91).
6. Legs run under the dontAsk permission mode: a command that no rule allows is
   denied at once, and the leg comments on its entity that it is blocked, then
   stops. The forge hook denies a forge command that it would ask about. The mode
   is interim: when the sandbox probes of phase 5 of issue 74 pass, the mode
   becomes bypassPermissions, and the sandbox, the proxy, and the hook become the
   boundary.

## Machine decisions

The phase text leaves these open. The brief of the pull request repeats them.

1. The worker branch spawns without `--from` (the dispatcher runs from the home of
   `dev`, so the branch starts at the default branch, and no `projectBase` is written).
2. The reviewer branch is prepared by the dispatcher with plain git, not with
   `--from`, for the reason in dispatcher rule 5.
3. The final comment of a leg releases its in-flight entry, because the prompts
   make that comment the declared end of a leg. The release also stops the
   background session of the leg, so an agent comment that arrives before the end
   can no longer let a second leg run on a branch whose first leg still lives.
   The two-hour limit stays the backstop for a leg that crashed without a
   comment. There is no reliable way to read the liveness of a `claude --bg`
   session from a script.
4. Both legs run under the plan `zai`. A second plan for the reviewer, when one
   exists, is one environment change in the unit (`DISPATCHER_REVIEWER_PLAN`).
5. The `/loop` command prefix is fixed. It works on an open issue without the gate
   label, but only from a human comment.
6. A human comment on a pull request starts a nudge leg: a worker leg on the head
   branch of that pull request. Its prompt tells it to work the findings of the
   pull request and to open no second pull request.
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
