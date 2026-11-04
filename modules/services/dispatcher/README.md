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
| `dispatcher-test.py` | The stub harness of the program: stub `project`, `tea`, and `git` binaries in a temporary state directory. The CI of a pull request runs it. |
| `dispatcher.nix` | The secret declaration, the linger of `dev`, and the user services. Loads only on the `services` host. |
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
   entry. An entry older than two hours counts as a crashed leg. An event that finds
   its branch busy stays in `events/`, and the next sweep retries it, so an event
   that arrives during a live leg runs when the leg ends. A delivery for a branch
   that already has a pending event is superseded: it is recorded and never spawns,
   because one pending event per branch is enough, and a leg reads its entity fresh.
3. The spawn runs `project spawn <project> <branch> --plan zai --headless
   --permission-mode acceptEdits <prompt>`. The prompts name the `factory` skill.
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
   through `project`, `git` (in `main/` of the project clone), and `tea comments add`.
4. The receiver has no authentication beyond the webhook signature. The bind address
   makes it reachable only from the Podman bridge of the host.
5. A leg that hits a permission prompt waits forever, because a headless session has
   no person. The prompts tell the legs to comment and stop instead. The forge hook
   denies a forge command that it would ask about, so a leg reports instead of
   waiting on those.

## Machine decisions

The phase text leaves these open. The brief of the pull request repeats them.

1. The worker branch spawns without `--from` (the dispatcher runs from the home of
   `dev`, so the branch starts at the default branch, and no `projectBase` is written).
2. The reviewer branch is prepared by the dispatcher with plain git, not with
   `--from`, for the reason in dispatcher rule 5.
3. The final comment of a leg releases its in-flight entry, because the prompts
   make that comment the declared end of a leg. An agent comment that arrives
   before the end releases the entry early, and a waiting event may then start a
   second leg on a branch whose first leg still runs. The two-hour limit stays the
   backstop for a leg that crashed without a comment. There is no reliable way to
   read the liveness of a `claude --bg` session from a script.
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
