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
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

log = logging.getLogger("dispatcher")

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
PERMISSION_MODE = os.environ.get("DISPATCHER_PERMISSION_MODE", "acceptEdits")

TEA = os.environ.get("DISPATCHER_TEA", "tea")
PROJECT_BIN = os.environ.get("DISPATCHER_PROJECT_BIN", "project")
GIT = os.environ.get("DISPATCHER_GIT", "git")

BIND = os.environ.get("DISPATCHER_BIND", "10.88.0.1")
PORT = int(os.environ.get("DISPATCHER_PORT", "8741"))
SECRET_FILE = os.environ.get("DISPATCHER_WEBHOOK_SECRET_FILE", "")
STATE_DIR = Path(
    os.environ.get("DISPATCHER_STATE_DIR", os.path.expanduser("~/.local/state/dispatcher"))
)

# a leg that started longer ago than this is treated as crashed, so a new
# event may start a fresh leg on the same branch (recovery after a crash)
INFLIGHT_TTL = int(os.environ.get("DISPATCHER_INFLIGHT_TTL", str(2 * 3600)))
# exit codes of the vendored table that tell the caller to retry
RETRY_CODES = {11, 12}
RETRY_DELAYS = [
    int(part)
    for part in os.environ.get("DISPATCHER_RETRY_DELAYS", "30,120").split(",")
    if part.strip()
]
SPAWN_TIMEOUT = int(os.environ.get("DISPATCHER_SPAWN_TIMEOUT", str(300)))
PROCESSED_RETENTION_DAYS = 14
BODY_LIMIT = 1 << 20

CLOSING_KEYWORD = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd]?)?|resolve[sd]?)\s+#(\d+)", re.IGNORECASE
)


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


def closing_issue(body: str):
    """Return the issue number that a closing keyword names, or None."""
    if not body:
        return None
    match = CLOSING_KEYWORD.search(body)
    return int(match.group(1)) if match else None


def as_int(value):
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- events


def enqueue(delivery: str, kind: str, entity: int, branch: str, issue, reason: str, head: str = "") -> bool:
    """Write one event file, named after the delivery ID. The file is the
    delivery record: while it sits in events/, processed/, or failed/, the
    same delivery is skipped."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", delivery)
    state_path("events").mkdir(parents=True, exist_ok=True)
    for done in ("events", "processed", "failed"):
        if state_path(done, name + ".json").exists():
            log.info("delivery %s already known (%s), skip", delivery, done)
            return False
    event = {
        "branch": branch,
        "delivery": delivery,
        "entity": entity,
        "head_branch": head,
        "issue": issue,
        "kind": kind,
        "reason": reason,
        "received": int(time.time()),
    }
    store_json(state_path("events", name + ".json"), event)
    log.info("queued %s leg for entity %s branch %s (%s)", kind, entity, branch, reason)
    return True


def handle_payload(event_type: str, payload: dict) -> None:
    """Turn one forge event into zero or one queued event. The self-trigger
    rule lives here: a comment of the agent login is always ignored."""
    repository = payload.get("repository") or {}
    if repository.get("full_name") != REPO:
        log.info("event of repository %s, ignore", repository.get("full_name"))
        return
    sender = ((payload.get("sender") or {}).get("login") or "").lower()

    if event_type == "issue_comment":
        if sender == AGENT_LOGIN:
            return
        issue = payload.get("issue") or {}
        number = as_int(issue.get("number"))
        if number is None or issue.get("state") != "open":
            return
        comment = (payload.get("comment") or {}).get("body") or ""
        first_word = comment.strip().split(" ", 1)[0].strip().lower()
        if issue.get("pull_request") is not None:
            # a human comment on a pull request: re-trigger the worker on
            # the branch of that pull request
            head = pr_head(number)
            if head.startswith(AI_PREFIX):
                enqueue(
                    payload_delivery(), "worker", number, head, None,
                    "human comment on the pull request", head,
                )
            return
        if GATE_LABEL in label_names(issue.get("labels")) or first_word == COMMAND_PREFIX.lower():
            enqueue(
                payload_delivery(), "worker", number, WORKER_BRANCH.format(n=number), None,
                "gated issue comment",
            )
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
            return
        if payload.get("action") not in ("opened", "synchronized"):
            return
        link = closing_issue(pull.get("body") or "")
        record_link(number, link)
        enqueue(
            payload_delivery(), "reviewer", number, REVIEWER_BRANCH.format(n=number), link,
            "pull request " + str(payload.get("action")), head,
        )


def pr_head(number: int) -> str:
    """Read the head branch of a pull request with tea. Used only for a
    human comment on a pull request, where the payload carries no head."""
    try:
        out = subprocess.run(
            [TEA, "pulls", str(number), "--output", "json"],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        return ref_name(json.loads(out).get("head"))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s: %s", number, err)
        return ""


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


def sweep() -> None:
    init_state()
    with SweepLock() as locked:
        if not locked:
            log.info("another sweep runs, exit")
            return
        for path in sorted(state_path("events").glob("*.json")):
            try:
                process_event(load_json(path, {}), path)
            except Exception:  # noqa: BLE001 - one bad event stops no other
                log.exception("event %s failed", path.name)
                move_event(path, "failed")
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


def process_event(event: dict, path: Path) -> None:
    kind = event.get("kind")
    entity = as_int(event.get("entity")) or 0
    branch = str(event.get("branch") or "")
    if kind not in ("worker", "reviewer") or not branch:
        log.warning("event %s has no usable shape, drop", path.name)
        move_event(path, "failed")
        return
    if not claim_slot(branch):
        log.info("branch %s is in flight, suppress double spawn", branch)
        move_event(path, "processed")
        return
    if kind == "reviewer":
        prepare_review_branch(branch, str(event.get("head_branch") or ""))
    code, envelope = spawn_leg(kind, entity, branch, event.get("issue"))
    if code == 0:
        session = ((envelope or {}).get("data") or {}).get("session") or ""
        take_slot(branch, session, entity)
        move_event(path, "processed")
        return
    move_event(path, "failed")
    report_failure(kind, entity, branch, code, envelope)


# ------------------------------------------------------------ in-flight


def inflight() -> dict:
    return load_json(state_path("inflight.json"), {})


def claim_slot(branch: str) -> bool:
    """True when a leg may start on the branch. An entry younger than the
    TTL blocks the spawn; an older one is a crashed leg and is dropped."""
    entry = inflight().get(branch)
    if entry is None:
        return True
    if time.time() - float(entry.get("since", 0)) < INFLIGHT_TTL:
        return False
    release_inflight(branch)
    return True


def take_slot(branch: str, session: str, entity: int) -> None:
    state = inflight()
    state[branch] = {"entity": entity, "session": session, "since": int(time.time())}
    store_json(state_path("inflight.json"), state)


def release_inflight(branch: str) -> None:
    state = inflight()
    if state.pop(branch, None) is not None:
        store_json(state_path("inflight.json"), state)


def record_link(pr: int, issue) -> None:
    links = load_json(state_path("links.json"), {})
    links[str(pr)] = issue
    store_json(state_path("links.json"), links)


# ------------------------------------------------------------- spawning


def prepare_review_branch(branch: str, head: str) -> None:
    """Point the reviewer branch at the tip of the worker branch, without
    --from. A --from spawn would record the worker branch as a projectBase,
    and the forge hook then stops every later push of the worker with a
    prompt, which a headless leg cannot answer. The upstream lets the
    reviewer pull the tip itself."""
    main = Path.home() / "projects" / PROJECT_DIR / "main"
    if not main.is_dir():
        log.warning("no project clone at %s, reviewer starts from the default branch", main)
        return
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [GIT, *args], cwd=main, capture_output=True, text=True, timeout=120
        )
    if git("fetch", "origin").returncode != 0:
        log.warning("fetch of the project clone failed, reviewer may see an old tip")
    remote = "refs/remotes/origin/" + (head or "")
    created = git("branch", "-f", branch, remote)
    if created.returncode != 0:
        # the branch has a worktree already: the reviewer pulls it instead
        log.info("branch %s stays where it is (%s)", branch, created.stderr.strip())
    git("branch", "--set-upstream-to=origin/" + (head or ""), branch)


def worker_prompt(entity: int, branch: str) -> str:
    return (
        f"You are a worker leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        f"Work issue {entity} of this repository. Read the issue and every comment first, with: "
        f"tea issues {entity} --comments. Follow the factory skill, role worker. "
        "Make one topic per commit, run nix fmt before each commit, and follow Conventional Commits. "
        f"Push the branch with: git push -u origin {branch}. "
        "Open the pull request against the default branch with tea pulls create. The body must hold "
        f"the owner brief of the factory skill, one Closes line for issue {entity}, and the test evidence. "
        "Stop after you comment on the issue with the pull request number and what you verified. "
        "When a command stops at a permission prompt, comment on the issue that you are blocked, and stop."
    )


def reviewer_prompt(entity: int, branch: str, issue) -> str:
    issue_part = (
        f"its issue {issue}, with: tea issues {issue} --comments"
        if issue
        else "the issue that its body names"
    )
    return (
        f"You are a reviewer leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        "Run git pull --ff-only first. "
        f"Review pull request {entity}. Read it with: tea pulls {entity}. "
        f"Read its comments with: tea comments list {entity}. Read {issue_part}. "
        "Follow the factory skill, role reviewer. Verify that the pull request body names its issue "
        "with a closing keyword. Challenge the brief of the worker. Run the machine gate in this "
        "worktree: nix fmt -- --ci, then nix flake check --impure. When the diff touches the forge "
        "hook, also run: python3 modules/programs/cli/claude/forge-hook-test.py. "
        "Score the five risk signals of the skill. Comment your verdict on the pull request. "
        "Stop after the verdict comment. When a command stops at a permission prompt, comment on "
        "the pull request that you are blocked, and stop."
    )


def spawn_leg(kind: str, entity: int, branch: str, issue):
    """Run project spawn --headless and parse the phase 3 envelope. Exit
    codes 11 and 12 are retried with a delay; every other failure goes
    back to the caller, which comments on the entity."""
    prompt = (
        worker_prompt(entity, branch)
        if kind == "worker"
        else reviewer_prompt(entity, branch, issue)
    )
    plan = WORKER_PLAN if kind == "worker" else REVIEWER_PLAN
    command = [
        PROJECT_BIN, PROJECT_DIR, branch,
        "--plan", plan,
        "--headless",
        "--permission-mode", PERMISSION_MODE,
        prompt,
    ]
    attempts = len(RETRY_DELAYS) + 1
    for attempt in range(attempts):
        code, envelope = run_spawn(command)
        if code not in RETRY_CODES:
            return code, envelope
        if attempt + 1 < attempts:
            delay = RETRY_DELAYS[attempt]
            log.warning(
                "spawn of %s answered %s (%s), retry in %ss",
                branch, code, (envelope or {}).get("error", {}).get("code"), delay,
            )
            time.sleep(delay)
    return code, envelope


def run_spawn(command: list[str]):
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=SPAWN_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        log.error("spawn of %s timed out", command[2])
        return 1, None
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
        detail = f" The error code is {error.get('code', 'UNKNOWN')}: {error.get('message', '')}".strip()
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
            [TEA, "comments", "add", str(entity), body],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not comment on entity %s: %s", entity, err)


# --------------------------------------------------------------- receiver


def payload_delivery() -> str:
    """Delivery ID of the request that runs now. Set by the receiver; the
    poller sets its own ids before it calls handle_payload."""
    return _current_delivery[0]


_current_delivery = ["local"]


class Receiver(BaseHTTPRequestHandler):
    server_version = "genixis-dispatcher/1"

    def _reply(self, status: int, text: str) -> None:
        raw = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(raw)
        self.wfile.flush()

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
        _current_delivery[0] = delivery or hashlib.sha256(body).hexdigest()[:16]
        # answer first, then work: forgejo records the delivery as soon as
        # it has the response, and a duplicate delivery is skipped by name
        self._reply(200, "accepted\n")
        try:
            if event_type == "ping":
                log.info("ping delivery, ignore")
            else:
                handle_payload(event_type, payload)
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
    queue a worker event for each new human comment, then sweep. The cursor
    file holds the newest comment id of each gated issue."""
    init_state()
    cursor = load_json(state_path("poll-cursor.json"), {"issues": {}, "prs": []})
    try:
        listing = subprocess.run(
            [TEA, "issues", "list", "--labels", GATE_LABEL, "--state", "open", "--output", "json"],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        for issue in json.loads(listing):
            number = as_int(issue.get("index"))
            if number is None:
                continue
            detail = subprocess.run(
                [TEA, "issues", str(number), "--comments", "--output", "json"],
                capture_output=True, text=True, timeout=120, check=True,
            ).stdout
            comments = json.loads(detail).get("comments") or []
            seen = as_int(cursor["issues"].get(str(number))) or 0
            for comment in comments:
                comment_id = as_int(comment.get("id")) or 0
                if comment_id <= seen:
                    continue
                if str(comment.get("author", "")).lower() == AGENT_LOGIN:
                    continue
                _current_delivery[0] = f"poll-{comment_id}"
                enqueue(
                    f"poll-{comment_id}", "worker", number, WORKER_BRANCH.format(n=number),
                    None, "poll: gated issue comment",
                )
            if comments:
                cursor["issues"][str(number)] = max(
                    seen, max(as_int(c.get("id")) or 0 for c in comments)
                )
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("poll of the gated issues failed: %s", err)
    try:
        pulls = subprocess.run(
            [TEA, "pulls", "list", "--state", "open", "--output", "json",
             "--fields", "index,head,body"],
            capture_output=True, text=True, timeout=120, check=True,
        ).stdout
        for pull in json.loads(pulls):
            number = as_int(pull.get("index"))
            head = ref_name(pull.get("head"))
            if number is None or not head.startswith(AI_PREFIX):
                continue
            if str(number) in cursor["prs"]:
                continue
            _current_delivery[0] = f"poll-pr-{number}"
            enqueue(
                f"poll-pr-{number}", "reviewer", number, REVIEWER_BRANCH.format(n=number),
                closing_issue(pull.get("body") or ""), "poll: new pull request", head,
            )
            cursor["prs"].append(str(number))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("poll of the pull requests failed: %s", err)
    store_json(state_path("poll-cursor.json"), cursor)
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
