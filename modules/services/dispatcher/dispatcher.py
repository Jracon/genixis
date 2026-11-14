#!/usr/bin/env python3
"""The dispatcher of the factory loop (issue #74, phase 4; issue #83).

One program, three entry points:

    dispatcher.py serve   the webhook receiver of the dev user on services
    dispatcher.py run     one pass over the event spool (spawn legs)
    dispatcher.py poll    the tea fallback: read gated issues, then run

The receiver only verifies, filters, and enqueues an event file. The run
pass turns each event into one leg through the same CLI that the owner
could type: project spawn --headless. The phase 3 binary answers with one
JSON envelope and an exit code; this program parses both.

Security note: this file is part of the security spine of the repository
(standing principle 7 of issue #74). It runs as the dev user on services
and holds no secret except the path of the webhook token file. It writes
only inside its state directory and only through `project`, `git`, and
`tea comments add`.
"""

from __future__ import annotations

import fcntl
import hashlib
import hmac
import json
import logging
import os
import re
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

log = logging.getLogger("dispatcher")

# the receiver is threaded, so the state files of one process share this
# lock; sweeps of other processes share the file lock of SweepLock instead
state_lock = threading.Lock()

AGENT_LOGIN = os.environ.get("DISPATCHER_AGENT_LOGIN", "claude-bot")
REPO = os.environ.get("DISPATCHER_REPO", "jracon/genixis")
GATE_LABEL = os.environ.get("DISPATCHER_GATE_LABEL", "gate")
COMMAND_PREFIX = os.environ.get("DISPATCHER_COMMAND_PREFIX", "/loop")
AI_PREFIX = "ai/"
WORKER_BRANCH = "ai/issue-{n}"
REVIEWER_BRANCH = "ai/review-{n}"

PROJECT_DIR = os.environ.get("DISPATCHER_PROJECT", "genixis")
WORKER_PLAN = os.environ.get("DISPATCHER_WORKER_PLAN", "zai")
REVIEWER_PLAN = os.environ.get("DISPATCHER_REVIEWER_PLAN", "zai")
# dontAsk turns a command that no rule allows into a denial the leg sees, so
# it comments that it is blocked and stops. acceptEdits would hang the leg at
# a prompt no person answers. bypassPermissions follows only when the sandbox
# probes of phase 5 of issue 74 pass (see the machine decisions of the README).
PERMISSION_MODE = os.environ.get("DISPATCHER_PERMISSION_MODE", "dontAsk")

TEA = os.environ.get("DISPATCHER_TEA", "tea")
PROJECT_BIN = os.environ.get("DISPATCHER_PROJECT_BIN", "project")
GIT = os.environ.get("DISPATCHER_GIT", "git")
CLAUDE = os.environ.get("DISPATCHER_CLAUDE", "claude")
# each spawn runs inside a transient scope of the user manager, so the
# background-session machinery that the spawn starts (the shared claude
# daemon and its bg-spare pool, issue #93) lands beside the receiver unit
# instead of inside its cgroup. --scope runs the command as a direct child
# that inherits this environment and whose exit code comes back (both per
# the systemd-run man page), --collect removes the scope when it ends,
# --quiet keeps the unit banner off stderr, and --expand-environment=no
# leaves the prompt bytes alone: with --scope, systemd-run itself expands
# ${VARIABLE} in the arguments, and a prompt must never depend on that
SYSTEMD_RUN = os.environ.get("DISPATCHER_SYSTEMD_RUN", "systemd-run")
SCOPE_PREFIX = [
    SYSTEMD_RUN,
    "--user",
    "--scope",
    "--collect",
    "--quiet",
    "--expand-environment=no",
]

BIND = os.environ.get("DISPATCHER_BIND", "10.88.0.1")
PORT = int(os.environ.get("DISPATCHER_PORT", "8741"))
SECRET_FILE = os.environ.get("DISPATCHER_WEBHOOK_SECRET_FILE", "")
# the socket timeout of one receiver connection. A real delivery sends its
# whole body at once and stays far below the default. A client that sends
# no data for this long loses its thread, so a stalled connection cannot
# pin the threads of the receiver.
READ_TIMEOUT = float(os.environ.get("DISPATCHER_READ_TIMEOUT", "10"))
# the total time one request may hold its thread, from the accepted
# connection to the written reply. The socket timeout above bounds each
# read alone: a client that sends one byte at a time keeps every read
# under it and still holds the thread (issue #97). This deadline cuts
# such a connection whatever its sending pattern. The work after the
# reply, the spawn and its retries, sits outside the deadline and inside
# the spawn timeout.
REQUEST_TIMEOUT = float(os.environ.get("DISPATCHER_REQUEST_TIMEOUT", "30"))
STATE_DIR = Path(
    os.environ.get("DISPATCHER_STATE_DIR", os.path.expanduser("~/.local/state/dispatcher"))
)

# a leg that started longer ago than this is treated as crashed, so a new
# event may start a fresh leg on the same branch (recovery after a crash)
INFLIGHT_TTL = int(os.environ.get("DISPATCHER_INFLIGHT_TTL", str(2 * 3600)))
# a red gate starts a nudge leg with a bound (issue #110): at most this many
# red-gate nudge legs per pull request while the gate stays red. The next red
# gate after the bound comments on the pull request and names the owner, and
# no further leg starts on its own. The bound stops a loop of push and fail.
REDGATE_LIMIT = int(os.environ.get("DISPATCHER_REDGATE_LIMIT", "2"))
# the conclusion words of a gate delivery. A status delivery of the forge
# family (api.CommitStatusPayload: sha, state, context, repository, sender)
# carries them in state, with the words pending, success, error, failure. A
# workflow run delivery of this forge carries them in run.status, with the
# words blocked, cancelled, failure, running, skipped, success, waiting
RED_STATE = "failure"
GREEN_STATE = "success"
# the action word of the workflow run delivery of this forge: the run ended,
# so run.status holds the conclusion of the run
RUN_COMPLETED = "run_completed"
# exit codes of the vendored table that tell the caller to retry
RETRY_CODES = {11, 12}
RETRY_DELAYS = [
    int(part)
    for part in os.environ.get("DISPATCHER_RETRY_DELAYS", "30,120").split(",")
    if part.strip()
]
SPAWN_TIMEOUT = int(os.environ.get("DISPATCHER_SPAWN_TIMEOUT", str(300)))
# the rendered entity payload of a prompt (issue #311). The prompt passes as
# one argument to project spawn, and the kernel caps one argument at 128 KiB,
# so the cap leaves the static text of the prompt its headroom. A payload
# past the cap is cut whole: a truncated thread could hide a comment from a
# leg that believes it read everything, so the leg reads the entity itself
# instead (see entity_payload)
PAYLOAD_LIMIT = int(os.environ.get("DISPATCHER_PAYLOAD_LIMIT", str(96 * 1024)))
# one sweep pass starts at most one leg, and no pass starts a leg within this
# many seconds of the last start (issue #225): a burst of deliveries must not
# start a burst of legs. The sweep timer (one minute) drains queued events one
# leg per pass. The pace records an attempt, also one that fails at the fetch
# or the spawn, so the floor stays honest about how often the loop tried.
SPAWN_SPACING = float(os.environ.get("DISPATCHER_SPAWN_SPACING", "60"))
# the fetch of the clone before each spawn (issue #100) has its own limit:
# it runs before the spawn, so the two together must stay inside the
# patience of one sweep
FETCH_TIMEOUT = int(os.environ.get("DISPATCHER_FETCH_TIMEOUT", str(120)))
PROCESSED_RETENTION_DAYS = 14
BODY_LIMIT = 1 << 20

# the link keyword of the factory loop (issue #356, L7): a closing keyword
# names the issue that a pull request solves, and Refs names the issue of a
# composition flow, whose pull request must not close it (the merge policy of
# the factory skill). The link reader accepts both, because links.json and
# the entity payload resolve the linked issue either way
LINK_KEYWORD = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd]?)?|resolve[sd]?|refs?)\s+#(\d+)", re.IGNORECASE
)

# the readiness gate (issue #356, L2): a worker leg starts only on an issue
# whose brief answers each ambiguity class of the readiness protocol of the
# factory skill, or marks the class not applicable with its answerer named.
# The answers live in the body of the issue, one plain line per class:
#     Readiness A: <answer>
#     Readiness C: not applicable by <login>
# A not-applicable that names no answerer counts as unanswered, because the
# record must hold who dismissed the class (issue #356, L12)
READINESS_LINE = re.compile(
    r"^\s*readiness\s+([a-f])\s*:\s*(\S.*?)\s*$", re.IGNORECASE | re.MULTILINE
)
NOT_APPLICABLE = re.compile(r"^not[\s-]+applicable\b", re.IGNORECASE)
ANSWERER = re.compile(r"\bby\s+(\S+)", re.IGNORECASE)
READINESS_CLASSES = {
    "a": "reference and product",
    "b": "oracle",
    "c": "basis",
    "d": "materials",
    "e": "build rules",
    "f": "loop contract",
}


def state_path(*parts: str) -> Path:
    return STATE_DIR.joinpath(*parts)


def init_state() -> None:
    for name in ("events", "processed", "failed"):
        state_path(name).mkdir(parents=True, exist_ok=True)


def load_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def store_json(path: Path, payload) -> None:
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def read_secret() -> bytes:
    with open(SECRET_FILE, encoding="utf-8") as handle:
        return handle.read().strip().encode()


def label_names(labels) -> list[str]:
    """Accept both label forms a payload can carry: a name, or an object."""
    names = []
    for label in labels or []:
        if isinstance(label, str):
            names.append(label)
        elif isinstance(label, dict) and "name" in label:
            names.append(label["name"])
    return names


def ref_name(ref) -> str:
    """Accept both ref forms a payload can carry: a name, or an object."""
    if isinstance(ref, str):
        return ref
    if isinstance(ref, dict):
        return ref.get("ref", "")
    return ""


def linked_issue(body: str):
    """Return the issue number that a link keyword names, or None. A link
    keyword is a closing keyword or the Refs keyword of a composition flow
    (issue #356, L7): the number feeds links.json and the entity payload
    either way, and the forge closes the issue only on a closing keyword."""
    if not body:
        return None
    match = LINK_KEYWORD.search(body)
    return int(match.group(1)) if match else None


def as_int(value):
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- events


def enqueue(
    delivery: str, kind: str, entity: int, branch: str, issue, reason: str,
    head: str = "", cause: str = "",
) -> bool:
    """Write one event file, named after the delivery ID. The file is the
    delivery record: while it sits in events/, processed/, or failed/, the
    same delivery is skipped. A delivery for a branch that already has a
    pending event is recorded as superseded and spawns nothing: one pending
    event per branch is enough, because a leg reads its entity fresh. The
    cause is the opening sentence of the prompt of a nudge leg: it says what
    started the leg."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", delivery)
    state_path("events").mkdir(parents=True, exist_ok=True)
    for done in ("events", "processed", "failed"):
        if state_path(done, name + ".json").exists():
            log.info("delivery %s already known (%s), skip", delivery, done)
            return False
    event = {
        "branch": branch,
        "cause": cause,
        "delivery": delivery,
        "entity": entity,
        "head_branch": head,
        "issue": issue,
        "kind": kind,
        "reason": reason,
        "received": int(time.time()),
    }
    with state_lock:
        for pending in state_path("events").glob("*.json"):
            if load_json(pending, {}).get("branch") == branch:
                event["superseded"] = True
                store_json(state_path("processed", name + ".json"), event)
                log.info(
                    "branch %s already has a pending event, delivery %s superseded",
                    branch, delivery,
                )
                return False
        store_json(state_path("events", name + ".json"), event)
    log.info("queued %s leg for entity %s branch %s (%s)", kind, entity, branch, reason)
    return True


def handle_payload(event_type: str, payload: dict, delivery: str) -> None:
    """Turn one forge event into zero or one queued event. The self-trigger
    rule lives here: a comment of the agent login never spawns a leg, but
    it releases the in-flight entries of its entity, because the prompts
    make the final comment the declared end of a leg."""
    # the workflow run delivery carries its repository inside the run
    # object, and nothing at the top level besides the action word (the
    # recorded delivery of issue #228)
    run = payload.get("run") if isinstance(payload.get("run"), dict) else {}
    repository = payload.get("repository") or run.get("repository") or {}
    if repository.get("full_name") != REPO:
        log.info("event of repository %s, ignore", repository.get("full_name"))
        return
    sender = ((payload.get("sender") or {}).get("login") or "").lower()

    if event_type == "issue_comment":
        issue = payload.get("issue") or {}
        number = as_int(issue.get("number"))
        if sender == AGENT_LOGIN:
            if number is not None:
                release_entity(number)
            return
        if number is None or issue.get("state") != "open":
            return
        comment = (payload.get("comment") or {}).get("body") or ""
        first_word = comment.strip().split(" ", 1)[0].strip().lower()
        if issue.get("pull_request") is not None:
            # a human comment on a pull request: continue the work on the
            # branch of that pull request, as a nudge leg
            head = pr_head(number)
            if head.startswith(AI_PREFIX):
                enqueue(
                    delivery, "nudge", number, head, None,
                    "human comment on the pull request", head,
                )
            return
        if GATE_LABEL in label_names(issue.get("labels")) or first_word == COMMAND_PREFIX.lower():
            queue_gated_issue(delivery, number)
        return

    if event_type == "pull_request":
        number = as_int(payload.get("number"))
        pull = payload.get("pull_request") or {}
        head = ref_name(pull.get("head"))
        if number is None or not head.startswith(AI_PREFIX):
            return
        if payload.get("action") == "closed":
            release_inflight(head)
            release_inflight(REVIEWER_BRANCH.format(n=number))
            gate_green(number)
            return
        if payload.get("action") not in ("opened", "synchronized"):
            return
        link = linked_issue(pull.get("body") or "")
        record_link(number, link)
        enqueue(
            delivery, "reviewer", number, REVIEWER_BRANCH.format(n=number), link,
            "pull request " + str(payload.get("action")), head,
        )
        return

    if event_type == "status":
        # a status delivery of the forge family: state and sha
        gate_delivery(
            str(payload.get("state") or "").lower(),
            str(payload.get("sha") or ""),
            delivery,
        )
        return

    if payload.get("action") == RUN_COMPLETED and run:
        # a workflow run delivery of this forge, which offers no status
        # event on its webhook page (Forgejo 17): run.status holds the
        # conclusion and run.commit_sha holds the head commit. The rule
        # keys on the payload shape, not on the event header, because the
        # recorded delivery of issue #228 holds the body only.
        gate_delivery(
            str(run.get("status") or "").lower(),
            str(run.get("commit_sha") or ""),
            delivery,
        )
        return


def pr_head(number: int) -> str:
    """Read the head branch of a pull request with tea. Used only for a
    human comment on a pull request, where the payload carries no head."""
    try:
        out = subprocess.run(
            [TEA, "pulls", str(number), "--output", "json", "--repo", REPO],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        return ref_name(json.loads(out).get("head"))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s: %s", number, err)
        return ""


def pull_head_sha(number: int) -> str:
    """Read the head commit of a pull request with tea. The list view of the
    pull requests carries no head sha, so this one read per pull request is
    the only way to map a commit status to its pull request."""
    try:
        out = subprocess.run(
            [TEA, "pulls", str(number), "--output", "json", "--repo", REPO],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        return str(json.loads(out).get("headSha") or "")
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s: %s", number, err)
        return ""


def open_pulls() -> list:
    """The open pull requests of the repository, as (number, head) pairs."""
    try:
        out = subprocess.run(
            [TEA, "pulls", "list", "--state", "open", "--fields", "index,head",
             "--output", "json", "--repo", REPO],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        pairs = []
        for pull in json.loads(out):
            number = as_int(pull.get("index"))
            head = ref_name(pull.get("head"))
            if number is not None:
                pairs.append((number, head))
        return pairs
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not list the open pull requests: %s", err)
        return []


def open_ai_pull_by_sha(sha: str):
    """The open ai/ pull request whose head commit is sha, as (number, head),
    or (None, ""). Statuses of other branches, of main, and of an older
    commit of a branch match nothing here."""
    for number, head in open_pulls():
        if not head.startswith(AI_PREFIX):
            continue
        if pull_head_sha(number) == sha:
            return number, head
    return None, ""


def open_ai_pull_on_branch(branch: str):
    """The open pull request whose head branch is branch, as (number, head),
    or (None, "")."""
    for number, head in open_pulls():
        if head == branch:
            return number, head
    return None, ""


def issue_body(number: int):
    """The body of an issue, read with tea, or None when the read fails. The
    readiness gate needs the body before a worker leg starts. A failed read
    fails open, like every tea read of the receiver: the gate then runs on
    the next trigger, and a payload fetch that fails too sends the leg to
    read the issue itself."""
    try:
        return str(tea_read("issues", str(number)).get("body") or "")
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read issue %s for the readiness gate: %s", number, err)
        return None


def readiness_report(body: str) -> tuple[list[str], list[str]]:
    """The unanswered classes of a brief, as (missing, anonymous). A class
    counts as answered when one line of the body names it with a non-empty
    answer. The first line of a class counts. A not-applicable that names no
    answerer counts as anonymous, because the record must hold who dismissed
    the class (issue #356, L12)."""
    answered = {}
    for letter, value in READINESS_LINE.findall(body or ""):
        answered.setdefault(letter.lower(), value)
    missing = []
    anonymous = []
    for letter in sorted(READINESS_CLASSES):
        value = answered.get(letter)
        if value is None:
            missing.append(letter)
        elif NOT_APPLICABLE.match(value) and not ANSWERER.search(value):
            anonymous.append(letter)
    return missing, anonymous


def park_readiness(number: int, missing: list[str], anonymous: list[str]) -> None:
    """Park an issue whose brief is not ready (issue #356, L2, decision D10
    of issue #350): one comment on the issue names each unanswered class,
    asks one question, and names the blocked step. No leg starts. The park
    comment is the answer of the loop, and the body of the issue stays the
    record: the gate writes no state of its own (decision D13)."""
    findings = [
        f"{letter.upper()} ({READINESS_CLASSES[letter]}): no Readiness line in the body of this issue"
        for letter in missing
    ] + [
        f"{letter.upper()} ({READINESS_CLASSES[letter]}): the not-applicable names no answerer"
        for letter in anonymous
    ]
    body = (
        f"dispatcher: the worker leg on branch ai/issue-{number} did not start, because this issue is "
        f"parked: its brief is not ready. The readiness gate found these classes unanswered: "
        + "; ".join(findings)
        + ". Question: give each class named above one answer, or one not-applicable line that names "
        "who answered it. Write each answer as one line in the body of this issue: the word Readiness, "
        "the class letter, a colon, and the answer. The blocked step: the worker leg on this issue "
        "starts when every class A to F holds an answer or a named not-applicable. A new comment on "
        "this issue requeues the leg."
    )
    log.error("issue %s parked, unanswered classes: %s", number, " ".join(findings))
    try:
        subprocess.run(
            [TEA, "comments", "add", str(number), body, "--repo", REPO],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not park issue %s: %s", number, err)


def readiness_gate(number: int) -> bool:
    """Verify the readiness of an issue before its worker event is queued
    (issue #356, L2, D10). True starts the leg. False parks the issue, and
    the caller queues no event. A read that fails fails open: the leg
    starts, and the gate runs again on the next trigger."""
    body = issue_body(number)
    if body is None:
        return True
    missing, anonymous = readiness_report(body)
    if not missing and not anonymous:
        return True
    park_readiness(number, missing, anonymous)
    return False


def queue_gated_issue(delivery: str, number: int) -> None:
    """Queue the leg for one human comment on a gated issue, by the state of
    the branch (issue #110). The worker prompt tells the leg to open a pull
    request, so it serves a branch that holds none. The readiness gate runs
    first: an issue whose brief answers no class, or holds a not-applicable
    without its answerer, is parked and queues nothing. When the branch
    already holds an open pull request, the nudge leg continues that pull
    request: the forge refuses a second pull request on one branch, so a
    worker leg would stop at that refusal."""
    branch = WORKER_BRANCH.format(n=number)
    linked, head = open_ai_pull_on_branch(branch)
    if linked is None:
        if not readiness_gate(number):
            return
        enqueue(delivery, "worker", number, branch, None, "gated issue comment")
        return
    cause = (
        f"A person asked for more work in a comment on issue {number}, "
        f"and the branch of that issue already holds pull request {linked}."
    )
    enqueue(
        delivery, "nudge", linked, branch, None,
        "gated issue comment on a branch with an open pull request",
        head, cause,
    )


# --------------------------------------------------------------- spool


class SweepLock:
    """One sweep at a time: the receiver, the timer, and the poller all
    share this lock. A second sweep exits at once, because the first one
    takes every event file with it."""

    def __init__(self) -> None:
        self.handle = None

    def __enter__(self):
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.handle = open(state_path("sweep.lock"), "w")
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.handle.close()
            self.handle = None
        return self.handle is not None

    def __exit__(self, *exc) -> None:
        if self.handle is not None:
            fcntl.flock(self.handle, fcntl.LOCK_UN)
            self.handle.close()


def pace_ok() -> bool:
    """True when a leg may start now: no leg started inside the spacing. The
    events stay in events/, and the next pass of the sweep timer takes them,
    so a burst of deliveries starts its legs one pass at a time (issue #225)."""
    last = float(load_json(state_path("pace.json"), {}).get("last") or 0)
    return time.time() - last >= SPAWN_SPACING


def pace_spawn() -> None:
    with state_lock:
        store_json(state_path("pace.json"), {"last": time.time()})


def sweep() -> None:
    init_state()
    with SweepLock() as locked:
        if not locked:
            log.info("another sweep runs, exit")
            return
        if not pace_ok():
            # the events stay queued: the sweep timer takes them when the
            # spacing passes, one leg per sweep (issue #225)
            log.info("a leg started inside the spacing, keep the events")
            return
        for path in sorted(state_path("events").glob("*.json")):
            attempted = False
            try:
                attempted = process_event(load_json(path, {}), path)
            except Exception:  # noqa: BLE001 - one bad event stops no other
                log.exception("event %s failed", path.name)
                move_event(path, "failed")
                attempted = True
            if attempted:
                # one spawn attempt per pass (issue #225): the next pass of
                # the sweep timer takes the next event, so the starts space out
                break
        prune_processed()


def move_event(path: Path, target: str) -> None:
    os.replace(path, state_path(target, path.name))


def prune_processed() -> None:
    cutoff = time.time() - PROCESSED_RETENTION_DAYS * 86400
    for path in state_path("processed").glob("*.json"):
        try:
            if path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            pass


def process_event(event: dict, path: Path) -> bool:
    """Turn one queued event into at most one spawn attempt. Return True when
    this pass spent its attempt on the event, also an attempt that failed, and
    False when the event stays queued for a later pass."""
    kind = event.get("kind")
    entity = as_int(event.get("entity")) or 0
    branch = str(event.get("branch") or "")
    if kind not in ("worker", "nudge", "reviewer") or not branch:
        log.warning("event %s has no usable shape, drop", path.name)
        move_event(path, "failed")
        return True
    if not claim_slot(branch):
        # the event stays in events/: the next sweep retries it, so a nudge
        # that arrives during a live leg runs when the leg ends, not never
        log.info("branch %s is in flight, keep the event for a later sweep", branch)
        return False
    # the pass commits to this event here: record the pace before the fetch
    # and the spawn, so a failure spends the floor like a start does
    pace_spawn()
    # no fetch, no spawn: a leg never starts on a base that the clone cannot
    # show current against origin main (issue #100)
    if not refresh_clone():
        move_event(path, "failed")
        report_stale_base(kind, entity, branch)
        return True
    if kind == "reviewer":
        prepare_review_branch(branch, str(event.get("head_branch") or ""))
    code, envelope = spawn_leg(kind, entity, branch, event.get("issue"), event.get("cause"))
    if code == 0:
        data = (envelope or {}).get("data") or {}
        take_slot(branch, str(data.get("session") or ""), str(data.get("session_id") or ""), entity)
        move_event(path, "processed")
        return True
    move_event(path, "failed")
    report_failure(kind, entity, branch, code, envelope)
    return True


# ------------------------------------------------------------ in-flight


def inflight() -> dict:
    return load_json(state_path("inflight.json"), {})


def claim_slot(branch: str) -> bool:
    """True when a leg may start on the branch. An entry younger than the
    TTL blocks the spawn; an older one is a crashed leg and is dropped."""
    with state_lock:
        entry = inflight().get(branch)
        if entry is None:
            return True
        if time.time() - float(entry.get("since", 0)) < INFLIGHT_TTL:
            return False
    release_inflight(branch)
    return True


def take_slot(branch: str, session: str, session_id: str, entity: int) -> None:
    with state_lock:
        state = inflight()
        state[branch] = {
            "entity": entity,
            "session": session,
            "session_id": session_id,
            "since": int(time.time()),
        }
        store_json(state_path("inflight.json"), state)


def release_inflight(branch: str) -> None:
    with state_lock:
        state = inflight()
        entry = state.pop(branch, None)
        if entry is not None:
            store_json(state_path("inflight.json"), state)
    if entry is not None:
        stop_session(entry.get("session"), entry.get("session_id"), branch)


def release_entity(entity: int) -> None:
    """Free every in-flight entry whose entity matches. A comment of the
    agent login on an entity is the declared end of its leg, so the entry
    no longer blocks the next event of that entity. The TTL stays the
    backstop for a leg that crashed without a comment."""
    with state_lock:
        state = inflight()
        free = [
            (branch, entry)
            for branch, entry in state.items()
            if as_int(entry.get("entity")) == entity
        ]
        for branch, _ in free:
            state.pop(branch)
        if free:
            store_json(state_path("inflight.json"), state)
    for branch, entry in free:
        log.info("agent comment on entity %s released branch %s", entity, branch)
        stop_session(entry.get("session"), entry.get("session_id"), branch)


def background_sessions() -> list[tuple[str, str]]:
    """The background sessions of the user, as (id, name) pairs, read with
    `claude agents --json`. The stop of a release names the recorded id of
    its session (issue #208), so this read serves only the fallback for an
    in-flight entry that predates the id: it bridges the session name that
    an old spawn envelope recorded and the stop call that ends the session
    (issue #144)."""
    try:
        result = subprocess.run(
            [CLAUDE, "agents", "--json"],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("could not list the background sessions: %s", err)
        return []
    if result.returncode != 0:
        log.info(
            "claude agents --json answered %s: %s",
            result.returncode, (result.stderr or "").strip()[:200],
        )
        return []
    try:
        listed = json.loads(result.stdout or "")
    except ValueError:
        log.warning("claude agents --json printed no json")
        return []
    if not isinstance(listed, list):
        log.warning("claude agents --json printed no list")
        return []
    pairs = []
    for entry in listed:
        if not isinstance(entry, dict) or entry.get("kind") != "background":
            continue
        session_id = str(entry.get("id") or "")
        name = str(entry.get("name") or "")
        if session_id and name:
            pairs.append((session_id, name))
    return pairs


def stop_session(session, session_id, branch: str) -> None:
    """Stop the background session of a finished leg. The spawn envelope
    recorded the id that `claude --bg` printed, and `claude stop` takes that
    id, so the release stops that one session and no other: a stopped
    session stays listed under its name for about an hour (verified live,
    issue #93), so the name of a re-looped leg can name two sessions and a
    name lookup can stop the wrong one (issue #208). An entry without an id
    predates the envelope change, so its name is resolved through
    `claude agents --json` and every listed background session under it is
    stopped (issue #144): `claude stop` accepts no name, and a release that
    failed before that rule can have left a second session under the same
    name. `claude stop` keeps the conversation, so the owner can still
    resume it. A name that no listed session holds needs no stop: that
    session ended already."""
    if session_id:
        ids = [str(session_id)]
    elif session:
        ids = [
            listed_id
            for listed_id, name in background_sessions()
            if name == str(session)
        ]
        if not ids:
            log.info(
                "no background session named %s for branch %s, nothing to stop",
                session, branch,
            )
            return
    else:
        return
    for listed_id in ids:
        stop_by_id(listed_id, branch)


def stop_by_id(session_id: str, branch: str) -> None:
    try:
        result = subprocess.run(
            [CLAUDE, "stop", session_id],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("could not stop the session of branch %s: %s", branch, err)
        return
    if result.returncode != 0:
        log.info(
            "claude stop of session %s (branch %s) answered %s: %s",
            session_id, branch, result.returncode,
            (result.stderr or "").strip()[:200],
        )


def record_link(pr: int, issue) -> None:
    with state_lock:
        links = load_json(state_path("links.json"), {})
        links[str(pr)] = issue
        store_json(state_path("links.json"), links)


# ------------------------------------------------------------- red gate


def redgate() -> dict:
    return load_json(state_path("redgate.json"), {})


def gate_delivery(state: str, sha: str, delivery: str) -> None:
    """The shared rule of every gate delivery, today the status event and
    the workflow run event. A red gate on the head of an open ai/ pull
    request starts one nudge leg, with the bound of gate_red (issue #110).
    A green gate on the head ends the red episode. A conclusion of any
    other state, or a commit that no open ai/ pull request holds as its
    head, is ignored, so the daily run of main and a stale conclusion of an
    older commit spawn nothing."""
    if not sha or state not in (RED_STATE, GREEN_STATE):
        return
    number, head = open_ai_pull_by_sha(sha)
    if number is None:
        return
    if state == GREEN_STATE:
        gate_green(number)
        return
    gate_red(number, head, sha, delivery)


def gate_red(number: int, head: str, sha: str, delivery: str) -> None:
    """Queue one nudge leg for a red gate, with a bound (issue #110): at
    most REDGATE_LIMIT red-gate nudge legs per pull request while the gate
    stays red. The count keys on the head sha, so a second status of the
    same commit, for example of a second workflow, starts no second leg. A
    red gate that arrives after the bound comments on the pull request,
    names the owner, and starts no leg. A green gate or a closed pull
    request clears the entry, so the next red gate gets a fresh bound. The
    count records the queued leg, not the spawned one: an event that fails
    at spawn still spends one nudge, which keeps the bound honest about
    how often the loop tried."""
    with state_lock:
        state = redgate()
        entry = state.get(str(number)) or {}
        if entry.get("sha") == sha:
            return
        spent = int(entry.get("nudges") or 0)
        if spent >= REDGATE_LIMIT:
            if entry.get("escalated"):
                return
            entry["escalated"] = True
            state[str(number)] = entry
            store_json(state_path("redgate.json"), state)
            escalate = True
        else:
            escalate = False
    if escalate:
        report_redgate_bound(number)
        return
    cause = (
        f"The machine gate of the repository is red on the head of pull request {number}. "
        "The comments of the pull request quote the failing CI run."
    )
    if enqueue(delivery, "nudge", number, head, None,
               "red gate on the pull request head", head, cause):
        with state_lock:
            state = redgate()
            entry = state.get(str(number)) or {}
            entry["nudges"] = int(entry.get("nudges") or 0) + 1
            entry["sha"] = sha
            state[str(number)] = entry
            store_json(state_path("redgate.json"), state)


def gate_green(number: int) -> None:
    """End the red episode of a pull request: a later red gate starts a
    fresh bound."""
    with state_lock:
        state = redgate()
        if state.pop(str(number), None) is not None:
            store_json(state_path("redgate.json"), state)


def report_redgate_bound(number: int) -> None:
    body = (
        f"dispatcher: the gate of pull request {number} stayed red after "
        f"{REDGATE_LIMIT} nudge legs, so no further leg starts on its own. "
        "jracon: this needs your decision."
    )
    log.error("red gate past the bound: %s", body)
    try:
        subprocess.run(
            [TEA, "comments", "add", str(number), body, "--repo", REPO],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not comment on pull request %s: %s", number, err)


# ------------------------------------------------------------- spawning


def refresh_clone() -> bool:
    """Fetch origin in the project clone before any spawn (issue #100). A
    leg that starts while no fetch answers works on a base that may be
    older than origin main, and nothing reported it, so the sweep verifies
    the base itself: no fetch, no spawn. The fetch also gives the reviewer
    branch the fresh tip it points at. The retries follow the spawn
    schedule, so a short outage costs no leg; an outage that outlasts them
    fails the event loudly instead."""
    main = Path.home() / "projects" / PROJECT_DIR / "main"
    if not main.is_dir():
        log.error("no project clone at %s, so no base can be verified", main)
        return False
    attempts = len(RETRY_DELAYS) + 1
    for attempt in range(attempts):
        try:
            result = subprocess.run(
                [GIT, "fetch", "origin"], cwd=main, capture_output=True,
                text=True, timeout=FETCH_TIMEOUT,
            )
        except (OSError, subprocess.SubprocessError) as err:
            log.warning("fetch of the project clone failed: %s", err)
        else:
            if result.returncode == 0:
                return True
            log.warning(
                "fetch of the project clone answered %s: %s",
                result.returncode, (result.stderr or "").strip()[:200],
            )
        if attempt + 1 < attempts:
            time.sleep(RETRY_DELAYS[attempt])
    return False


def report_stale_base(kind: str, entity: int, branch: str) -> None:
    """Tell the entity that a leg did not start, because the clone could not
    reach origin. Loud instead of silent: the spawn of a stale base was the
    three-person-hour failure mode of issue #100. A new comment or push
    requeues the leg once the host fetches again."""
    body = (
        f"dispatcher: the {kind} leg on {branch} did not start. The fetch of the project "
        "clone failed after every retry, so the base of the branch could not be verified "
        "against origin main. No spawn happened. jracon: check that this host reaches the "
        "forge over ssh, then comment or push again to requeue the leg."
    )
    log.error("leg did not start: %s", body)
    try:
        subprocess.run(
            [TEA, "comments", "add", str(entity), body, "--repo", REPO],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not comment on entity %s: %s", entity, err)


def prepare_review_branch(branch: str, head: str) -> None:
    """Point the reviewer branch at the tip of the worker branch, without
    --from. A --from spawn would record the worker branch as a projectBase,
    and the forge hook then stops every later push of the worker with a
    prompt, which a headless leg cannot answer. The upstream lets the
    reviewer pull the tip itself. The refs are current here: the sweep
    fetched the clone before this call (refresh_clone)."""
    main = Path.home() / "projects" / PROJECT_DIR / "main"
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [GIT, *args], cwd=main, capture_output=True, text=True, timeout=120
        )
    remote = "refs/remotes/origin/" + (head or "")
    created = git("branch", "-f", branch, remote)
    if created.returncode != 0:
        # the branch has a worktree already: the reviewer pulls it instead
        log.info("branch %s stays where it is (%s)", branch, created.stderr.strip())
    git("branch", "--set-upstream-to=origin/" + (head or ""), branch)


def tea_read(*args: str):
    """One tea read that must answer JSON (issue #311). A failure raises,
    and the caller cuts the payload, never the leg: the prompt then sends
    the leg to its own read of the entity."""
    out = subprocess.run(
        [TEA, *args, "--output", "json", "--repo", REPO],
        capture_output=True, text=True, timeout=60, check=True,
    ).stdout
    return json.loads(out)


def entity_payload(kind: str, entity: int, issue) -> dict:
    """Fetch the entity of a leg at spawn time, after the fetch of the clone
    and before the spawn command (issue #311). A worker leg reads its issue
    with its comments. A nudge or reviewer leg reads the pull request, its
    comments, its review comments, and the linked issue with its comments
    when the number resolves: the event carries it, or the closing keyword
    of the pull request body names it. The stamp precedes the first read, so
    the payload is never older than the named time. The answer carries the
    read time, the rendered reads, the linked issue, and the cut reason:
    an empty reason fits, "unavailable" names a failed fetch, and "cap"
    names a payload past PAYLOAD_LIMIT. A cut answer carries no reads, and
    the prompt names the cut instead."""
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    reads = []
    linked = None
    try:
        if kind == "worker":
            reads.append((
                f"tea issues {entity} --comments",
                tea_read("issues", str(entity), "--comments"),
            ))
        else:
            pull = tea_read("pulls", str(entity))
            reads.append((f"tea pulls {entity}", pull))
            reads.append((
                f"tea comments list {entity}",
                tea_read("comments", "list", str(entity)),
            ))
            reads.append((
                f"tea pulls review-comments {entity}",
                tea_read("pulls", "review-comments", str(entity)),
            ))
            body = pull.get("body") if isinstance(pull, dict) else ""
            linked = as_int(issue) or linked_issue(str(body or ""))
            if linked:
                reads.append((
                    f"tea issues {linked} --comments",
                    tea_read("issues", str(linked), "--comments"),
                ))
    except Exception as err:  # noqa: BLE001 - a payload problem cuts the payload, never the leg
        log.info("payload fetch of entity %s failed: %s", entity, err)
        return {"time": stamp, "reads": "", "issue": None, "cut": "unavailable"}
    rendered = "\n".join(
        name + "\n" + json.dumps(data, sort_keys=True, ensure_ascii=False)
        for name, data in reads
    )
    if len(rendered.encode("utf-8")) > PAYLOAD_LIMIT:
        log.info("payload of entity %s passes the cap, cut it", entity)
        return {"time": stamp, "reads": "", "issue": None, "cut": "cap"}
    return {"time": stamp, "reads": rendered, "issue": linked, "cut": ""}


def payload_cut_note(payload: dict) -> str:
    """The sentence that names a cut payload (issue #311). The cut is whole,
    and the sentence says why, so the leg knows why it must read the entity
    itself."""
    if payload.get("cut") == "cap":
        reason = f"the payload passed the size cap of {PAYLOAD_LIMIT} bytes"
    else:
        reason = "the fetch at spawn time failed"
    return f"The brief carries no entity payload: {reason}. "


def payload_tail(payload: dict) -> str:
    """The payload block at the end of a prompt, with one delimiter on each
    side, so the leg knows which bytes are data (issue #311)."""
    if payload.get("cut"):
        return ""
    return (
        f"\nEntity payload, read at {payload['time']}:\n"
        f"{payload['reads']}\n"
        "End of the entity payload.\n"
    )


def worker_prompt(entity: int, branch: str, payload: dict) -> str:
    if payload.get("cut"):
        source = (
            payload_cut_note(payload)
            + f"Read the issue and every comment first, with: tea issues {entity} --comments. "
        )
    else:
        source = (
            "The brief carries the entity payload at its end, read at "
            f"{payload['time']}: the issue {entity} with its comments, the output of "
            f"tea issues {entity} --comments. That payload is the first entity read of this leg. "
            "Re-read the entity with the same command when you need a state newer than that time. "
        )
    return (
        f"You are a worker leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        f"Work issue {entity} of this repository. "
        + source
        + "Follow the factory skill, role worker. "
        "Run one plain command in each shell call: no pipe, no chain, no loop, no command "
        "substitution, no shell variable. "
        "Make one topic per commit, run nix fmt before each commit, and follow Conventional Commits. "
        f"Push the branch with: git push -u origin {branch}. "
        "Open the pull request against the default branch with tea pulls create. The body must hold "
        f"the owner brief of the factory skill, one Closes line for issue {entity}, and the test evidence. "
        "Stop after you comment on the issue with the pull request number and what you verified. "
        "When a command stops at a permission prompt, comment on the issue that you are blocked, and stop."
        + payload_tail(payload)
    )


def nudge_prompt(entity: int, branch: str, cause: str, payload: dict) -> str:
    cause = cause or f"A person asked for more work on pull request {entity}. "
    if payload.get("cut"):
        source = (
            payload_cut_note(payload)
            + f"Read the pull request with: tea pulls {entity}. "
            f"Read its comments with: tea comments list {entity}. "
            f"Read its review comments with: tea pulls review-comments {entity}. "
            "Read the issue that its body names, with its comments. "
        )
    else:
        issue_part = (
            f", and its issue {payload['issue']} with its comments"
            if payload.get("issue")
            else ""
        )
        source = (
            "The brief carries the entity payload at its end, read at "
            f"{payload['time']}: the pull request {entity}, its comments, its review "
            f"comments{issue_part}, the output of the tea commands named in each part. "
            "That payload is the first entity read of this leg. "
        )
        if not payload.get("issue"):
            source += (
                "The payload names no issue: read the issue that the body of the "
                "pull request names, with its comments. "
            )
        source += (
            "Re-read an entity with its command when you need a state newer than that time. "
        )
    return (
        f"You are a worker leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        f"{cause}"
        + source
        + "Follow the factory skill, role worker. Address the blocking findings by name. "
        "Run one plain command in each shell call: no pipe, no chain, no loop, no command "
        "substitution, no shell variable. "
        "Make one topic per commit, run nix fmt before each commit, and follow Conventional Commits. "
        f"Push the branch with: git push -u origin {branch}. "
        "A pull request for this branch already exists: do not open a second one. "
        "Stop after you comment on the pull request with what you changed and what you verified. "
        "When a command stops at a permission prompt, comment on the pull request that you are blocked, and stop."
        + payload_tail(payload)
    )


def reviewer_prompt(entity: int, branch: str, issue, payload: dict) -> str:
    if payload.get("cut"):
        issue_part = (
            f"its issue {issue}, with: tea issues {issue} --comments"
            if issue
            else "the issue that its body names"
        )
        source = (
            payload_cut_note(payload)
            + f"Read the pull request with: tea pulls {entity}. "
            f"Read its comments with: tea comments list {entity}. Read {issue_part}. "
        )
    else:
        payload_issue = (
            f", and its issue {payload['issue']} with its comments"
            if payload.get("issue")
            else ""
        )
        source = (
            "The brief carries the entity payload at its end, read at "
            f"{payload['time']}: the pull request, its comments, its review "
            f"comments{payload_issue}, the output of the tea commands named in each part. "
            "That payload is the first entity read of this leg. The reads immediately before "
            "the verdict comment are re-reads: make them with the tea commands of the entity, "
            "whatever the payload holds. "
        )
    return (
        f"You are a reviewer leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        "Run git pull --ff-only first. "
        f"Review pull request {entity}. "
        + source
        + "Follow the factory skill, role reviewer. Verify that the pull request body names its issue "
        "with a closing keyword. Challenge the brief of the worker. "
        "Run one plain command in each shell call: no pipe, no chain, no loop, no command "
        "substitution, no shell variable. "
        "Run the machine gate in this "
        "worktree: nix fmt -- --ci, then nix flake check --impure. When the diff touches the forge "
        "hook, also run: python3 modules/programs/cli/claude/forge-hook-test.py. "
        "Score the five risk signals of the skill. "
        "Read the pull request, its comments, and its issue again immediately before the verdict "
        "comment: the worker leg can write its closing comment after your first read, so name no "
        "comment as missing that the entity holds at that moment. "
        "Comment your verdict on the pull request. "
        "Stop after the verdict comment. When a command stops at a permission prompt, comment on "
        "the pull request that you are blocked, and stop."
        + payload_tail(payload)
    )


def spawn_leg(kind: str, entity: int, branch: str, issue, cause=None):
    """Run project spawn --headless and parse the phase 3 envelope. Exit
    codes 11 and 12 are retried with a delay; every other failure goes
    back to the caller, which comments on the entity. The cause opens the
    prompt of a nudge leg: it says what started the leg. The payload fetch
    (issue #311) runs once here, before the retry loop, so every retry of
    one spawn speaks of the same read."""
    payload = entity_payload(kind, entity, issue)
    if kind == "reviewer":
        prompt, plan = reviewer_prompt(entity, branch, issue, payload), REVIEWER_PLAN
    else:
        cause = str(cause or "")
        if kind == "nudge":
            prompt, plan = nudge_prompt(entity, branch, cause, payload), WORKER_PLAN
        else:
            prompt, plan = worker_prompt(entity, branch, payload), WORKER_PLAN
    command = [
        *SCOPE_PREFIX,
        PROJECT_BIN, "spawn", PROJECT_DIR, branch,
        "--plan", plan,
        "--headless",
        "--permission-mode", PERMISSION_MODE,
        prompt,
    ]
    attempts = len(RETRY_DELAYS) + 1
    for attempt in range(attempts):
        code, envelope = run_spawn(command, branch)
        if code not in RETRY_CODES:
            return code, envelope
        if attempt + 1 < attempts:
            delay = RETRY_DELAYS[attempt]
            log.warning(
                "spawn of %s answered %s (%s), retry in %ss",
                branch, code, ((envelope or {}).get("error") or {}).get("code"), delay,
            )
            time.sleep(delay)
    return code, envelope


def run_spawn(command: list[str], branch: str):
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=SPAWN_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        log.error("spawn of %s timed out", branch)
        return 1, None
    # the spawn prints every diagnostic of the leg start on stderr: the
    # session id, and the cause when the view window did not open. The
    # journal of the unit is the only place a person reads them, and the
    # view-window cause is invisible today (issue #208). One line, and the
    # first 500 bytes: the output of claude itself rides the same stream.
    stderr_line = " ".join((result.stderr or "").split())[:500]
    if stderr_line:
        log.info("spawn of %s stderr: %s", branch, stderr_line)
    envelope = None
    for line in reversed((result.stdout or "").splitlines()):
        try:
            envelope = json.loads(line)
            break
        except ValueError:
            continue
    return result.returncode, envelope


def report_failure(kind: str, entity: int, branch: str, code: int, envelope) -> None:
    detail = ""
    if isinstance(envelope, dict):
        error = envelope.get("error") or {}
        detail = f" The error code is {error.get('code', 'UNKNOWN')}: {error.get('message', '')}"
    if code == 7:
        body = (
            f"dispatcher: the {kind} leg on {branch} was refused with exit code 7 "
            f"(permission denied).{detail} jracon: this needs your decision."
        )
    elif code == 2:
        body = (
            f"dispatcher: the {kind} leg on {branch} reported exit code 2 (argument error).{detail} "
            "This points at a defect in the dispatcher. No retry happened."
        )
    else:
        body = (
            f"dispatcher: the {kind} leg on {branch} failed with exit code {code} and stopped.{detail}"
        )
    log.error("leg failed: %s", body)
    try:
        subprocess.run(
            [TEA, "comments", "add", str(entity), body, "--repo", REPO],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not comment on entity %s: %s", entity, err)


# --------------------------------------------------------------- receiver


class Receiver(BaseHTTPRequestHandler):
    server_version = "genixis-dispatcher/1"
    # StreamRequestHandler.setup() applies this to the socket. A read that
    # exceeds it raises socket.timeout, and handle_one_request() answers by
    # closing the connection, so no thread waits for a silent client.
    timeout = READ_TIMEOUT

    def handle(self) -> None:
        # one deadline for the whole request, whatever the sending pattern.
        # Every socket timeout bounds a single operation, so a client that
        # dribbles one byte at a time stays under all of them. The timer
        # closes the socket at the deadline, so a blocked read ends at once
        # and a dribbling read ends on its next byte, and the thread
        # returns. _reply() cancels the timer, so the deadline bounds the
        # request, not the work that follows the reply.
        self.request_timer = threading.Timer(REQUEST_TIMEOUT, self._expire)
        self.request_timer.daemon = True
        self.request_timer.start()
        try:
            super().handle()
        except ConnectionError as err:
            # a cut connection, or a client that hangs up mid-request, ends a
            # read or a write on a dead socket, and the stdlib answers a
            # failed parse with an error reply on it. The thread ends the
            # request quietly here, or the error handler of the server
            # prints the traceback on stderr (issue #280).
            log.info(
                "request from %s ended on a dead connection: %s",
                self.address_string(), err,
            )
        finally:
            self.request_timer.cancel()

    def _expire(self) -> None:
        # shutdown() wakes the blocked read of the handler thread; close()
        # alone does not
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def _reply(self, status: int, text: str) -> None:
        raw = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(raw)
        self.wfile.flush()
        # the reply is written, so the request is complete: stop the timer
        self.request_timer.cancel()

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self._reply(200, "ok\n")
        else:
            self._reply(404, "not found\n")

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > BODY_LIMIT:
            self._reply(400, "bad length\n")
            return
        body = self.rfile.read(length)
        try:
            secret = read_secret()
        except OSError:
            log.error("cannot read the webhook secret file")
            self._reply(500, "no secret\n")
            return
        if not hmac.compare_digest(signature(self.headers, body, secret), "ok"):
            self._reply(403, "bad signature\n")
            return
        try:
            payload = json.loads(body)
        except ValueError:
            self._reply(400, "bad json\n")
            return
        event_type = (
            self.headers.get("X-Forgejo-Event")
            or self.headers.get("X-Gitea-Event")
            or self.headers.get("X-GitHub-Event")
            or ""
        )
        delivery = (
            self.headers.get("X-Forgejo-Delivery")
            or self.headers.get("X-Gitea-Delivery")
            or self.headers.get("X-GitHub-Delivery")
            or ""
        )
        delivery = delivery or hashlib.sha256(body).hexdigest()[:16]
        # answer first, then work: forgejo records the delivery as soon as
        # it has the response, and a duplicate delivery is skipped by name
        self._reply(200, "accepted\n")
        try:
            if event_type == "ping":
                log.info("ping delivery, ignore")
            else:
                handle_payload(event_type, payload, delivery)
        except Exception:  # noqa: BLE001 - the receiver must stay up
            log.exception("payload handling failed")
        sweep()

    def log_message(self, fmt: str, *args) -> None:  # journal, not stderr noise
        log.info("%s - %s", self.address_string(), fmt % args)


def signature(headers, body: bytes, secret: bytes) -> str:
    """Compare the HMAC-SHA256 of the raw body with the header, in
    constant time. Returns "ok" or a different string, never the digest."""
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    for header in ("X-Forgejo-Signature", "X-Gitea-Signature", "X-Hub-Signature-256"):
        given = headers.get(header)
        if given is None:
            continue
        if given.startswith("sha256="):
            given = given[len("sha256="):]
        if hmac.compare_digest(given.strip().lower(), expected):
            return "ok"
    return "mismatch"


def serve() -> None:
    if not SECRET_FILE:
        log.error("DISPATCHER_WEBHOOK_SECRET_FILE is not set")
        sys.exit(2)
    init_state()
    server = ThreadingHTTPServer((BIND, PORT), Receiver)
    log.info("receiver on %s:%s, project %s, repository %s", BIND, PORT, PROJECT_DIR, REPO)
    server.serve_forever()


# ------------------------------------------------------------- fallback


def poll() -> None:
    """The fallback of the bridge receiver: read the gated issues with tea,
    queue a worker event for each new human comment, read the newest CI
    status of each open ai/ pull request, then sweep. The cursor file holds
    the newest comment id of each gated issue, the pull requests it already
    queued for review, and the last CI status with its head sha that it saw
    on each of them. A first poll without a cursor file records the baseline
    and queues nothing, so the fallback never replays the whole comment or
    CI history of the repository."""
    init_state()
    cursor_path = state_path("poll-cursor.json")
    baseline = not cursor_path.exists()
    cursor = load_json(cursor_path, {"issues": {}, "prs": [], "ci": {}})
    cursor.setdefault("ci", {})
    if baseline:
        log.info("no poll cursor: record the baseline, queue nothing")
    try:
        listing = subprocess.run(
            [TEA, "issues", "list", "--labels", GATE_LABEL, "--state", "open",
             "--output", "json", "--repo", REPO],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        for issue in json.loads(listing):
            number = as_int(issue.get("index"))
            if number is None:
                continue
            detail = subprocess.run(
                [TEA, "issues", str(number), "--comments", "--output", "json",
                 "--repo", REPO],
                capture_output=True, text=True, timeout=120, check=True,
            ).stdout
            comments = json.loads(detail).get("comments") or []
            seen = as_int(cursor["issues"].get(str(number))) or 0
            for comment in comments:
                comment_id = as_int(comment.get("id")) or 0
                if comment_id <= seen:
                    continue
                if str(comment.get("author", "")).lower() == AGENT_LOGIN:
                    release_entity(number)
                    continue
                if not baseline:
                    queue_gated_issue(f"poll-{comment_id}", number)
            if comments:
                cursor["issues"][str(number)] = max(
                    seen, max(as_int(c.get("id")) or 0 for c in comments)
                )
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("poll of the gated issues failed: %s", err)
    try:
        pulls = subprocess.run(
            [TEA, "pulls", "list", "--state", "open", "--output", "json",
             "--fields", "ci,index,head,body", "--repo", REPO],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        open_numbers = []
        for pull in json.loads(pulls):
            number = as_int(pull.get("index"))
            head = ref_name(pull.get("head"))
            if number is None or not head.startswith(AI_PREFIX):
                continue
            open_numbers.append(str(number))
            if str(number) not in cursor["prs"]:
                if not baseline:
                    enqueue(
                        f"poll-pr-{number}", "reviewer", number, REVIEWER_BRANCH.format(n=number),
                        linked_issue(pull.get("body") or ""), "poll: new pull request", head,
                    )
                cursor["prs"].append(str(number))
            # the newest CI status of the pull request, the same red gate
            # the status delivery tells the receiver: a failure on a head
            # that the cursor has not seen red starts one nudge leg, with
            # the bound of gate_red
            status = str(pull.get("ci") or "").lower()
            seen = cursor["ci"].get(str(number)) or {}
            sha = str(seen.get("sha") or "")
            if status == RED_STATE:
                fresh = pull_head_sha(number)
                if fresh and (baseline or sha != fresh):
                    if not baseline:
                        gate_red(number, head, fresh, f"poll-red-{number}-{fresh[:12]}")
                if fresh:
                    cursor["ci"][str(number)] = {"sha": fresh}
            elif status == GREEN_STATE:
                if not baseline:
                    gate_green(number)
                cursor["ci"][str(number)] = {"sha": sha} if sha else {}
            else:
                # pending or unreadable: the webhook owns the transitions
                cursor["ci"][str(number)] = {"sha": sha} if sha else {}
        for gone in [key for key in cursor["ci"] if key not in open_numbers]:
            cursor["ci"].pop(gone)
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("poll of the pull requests failed: %s", err)
    store_json(cursor_path, cursor)
    sweep()


def main(argv: list[str]) -> int:
    logging.basicConfig(
        level=os.environ.get("DISPATCHER_LOG", "INFO"),
        format="%(levelname)s %(name)s %(message)s",
    )
    if len(argv) != 2 or argv[1] not in ("serve", "run", "poll"):
        print("usage: dispatcher.py serve|run|poll", file=sys.stderr)
        return 2
    {"serve": serve, "run": sweep, "poll": poll}[argv[1]]()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
