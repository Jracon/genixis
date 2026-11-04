#!/usr/bin/env python3
"""The stub harness of the dispatcher (issue #74, phase 4).

Runs dispatcher.py against stub project, tea, git, systemd-run, and claude
binaries and a temporary state directory, then drives the filter rules, the
spool, the in-flight map, the poll fallback, and the receiver over HTTP. It
also reads the source of dispatcher.nix, to check the gate environment that
the units give a spawned leg. Every check prints one line. The exit status
is 0 when every check passes.

The stubs stand in a temporary directory and read their behaviour from
environment variables, so this harness writes nothing outside its
temporary directory and talks to no network address except loopback.
"""

from __future__ import annotations

import hashlib
import hmac
import importlib.util
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

REPO = "jracon/genixis"
AGENT = "claude-bot"

root = Path(tempfile.mkdtemp(prefix="dispatcher-test-"))
state = root / "state"
home = root / "home"
stubs = root / "bin"
for directory in (state, home / "projects" / "genixis-test" / "main", stubs):
    directory.mkdir(parents=True)

secret_file = root / "webhook-secret"
secret_file.write_text("test-secret\n", encoding="utf-8")

scenario_file = root / "tea-scenario.json"
spawn_log = root / "project-log.jsonl"
tea_log = root / "tea-log.jsonl"
git_log = root / "git-log.jsonl"
scope_log = root / "systemd-run-log.jsonl"
claude_log = root / "claude-log.jsonl"
codes_file = root / "project-codes.txt"

TEA_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_TEA_LOG"], "a") as handle:
    handle.write(json.dumps(argv) + "\n")
if argv[:2] == ["comments", "add"]:
    sys.exit(0)
scenario = json.load(open(os.environ["DISPATCHER_TEST_TEA"]))
if argv[0] == "pulls" and argv[1] == "list":
    print(json.dumps(scenario["pulls_list"]))
elif argv[0] == "pulls":
    print(json.dumps(scenario["pulls"][argv[1]]))
elif argv[0] == "issues" and argv[1] == "list":
    print(json.dumps(scenario["issues_list"]))
elif argv[0] == "issues":
    print(json.dumps(scenario["issues"][argv[1]]))
else:
    sys.exit(2)
"""

PROJECT_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
codes = []
if os.path.exists(os.environ["DISPATCHER_TEST_PROJECT_CODES"]):
    with open(os.environ["DISPATCHER_TEST_PROJECT_CODES"]) as handle:
        codes = [line.strip() for line in handle if line.strip()]
code = int(codes.pop(0)) if codes else 0
with open(os.environ["DISPATCHER_TEST_PROJECT_CODES"], "w") as handle:
    handle.write("\n".join(codes) + ("\n" if codes else ""))
with open(os.environ["DISPATCHER_TEST_PROJECT_LOG"], "a") as handle:
    handle.write(json.dumps({"argv": argv, "code": code}) + "\n")
if code == 0:
    branch = argv[2] if len(argv) > 2 else ""
    print(json.dumps({"data": {"session": "genixis-test: " + branch, "worktree": "/nowhere"}}))
sys.exit(code)
"""

GIT_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_GIT_LOG"], "a") as handle:
    handle.write(json.dumps(argv) + "\n")
fail = os.environ.get("DISPATCHER_TEST_GIT_FAIL", "")
if fail and fail in " ".join(argv):
    sys.exit(1)
sys.exit(0)
"""

# stands in for systemd-run: it logs its own arguments, then replaces
# itself with the command after the options, so the exit code and the
# stdout of the wrapped spawn flow back to the dispatcher unchanged
SYSTEMD_RUN_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_SYSTEMD_RUN_LOG"], "a") as handle:
    handle.write(json.dumps(argv) + "\n")
command = list(argv)
while command and command[0].startswith("-"):
    command.pop(0)
os.execvp(command[0], command)
"""

CLAUDE_STUB = r"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["DISPATCHER_TEST_CLAUDE_LOG"], "a") as handle:
    handle.write(json.dumps(sys.argv[1:]) + "\n")
sys.exit(0)
"""

for name, text in (
    ("tea-stub", TEA_STUB),
    ("project-stub", PROJECT_STUB),
    ("git-stub", GIT_STUB),
    ("systemd-run-stub", SYSTEMD_RUN_STUB),
    ("claude-stub", CLAUDE_STUB),
):
    path = stubs / name
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)

os.environ.update(
    {
        "HOME": str(home),
        "DISPATCHER_STATE_DIR": str(state),
        "DISPATCHER_PROJECT": "genixis-test",
        "DISPATCHER_TEA": str(stubs / "tea-stub"),
        "DISPATCHER_PROJECT_BIN": str(stubs / "project-stub"),
        "DISPATCHER_GIT": str(stubs / "git-stub"),
        "DISPATCHER_CLAUDE": str(stubs / "claude-stub"),
        "DISPATCHER_SYSTEMD_RUN": str(stubs / "systemd-run-stub"),
        "DISPATCHER_WEBHOOK_SECRET_FILE": str(secret_file),
        "DISPATCHER_READ_TIMEOUT": "0.5",
        "DISPATCHER_REQUEST_TIMEOUT": "1",
        "DISPATCHER_RETRY_DELAYS": "0,0",
        "DISPATCHER_TEST_TEA": str(scenario_file),
        "DISPATCHER_TEST_TEA_LOG": str(tea_log),
        "DISPATCHER_TEST_PROJECT_LOG": str(spawn_log),
        "DISPATCHER_TEST_PROJECT_CODES": str(codes_file),
        "DISPATCHER_TEST_GIT_LOG": str(git_log),
        "DISPATCHER_TEST_SYSTEMD_RUN_LOG": str(scope_log),
        "DISPATCHER_TEST_CLAUDE_LOG": str(claude_log),
        "DISPATCHER_LOG": "ERROR",
    }
)

spec = importlib.util.spec_from_file_location(
    "dispatcher_under_test", Path(__file__).with_name("dispatcher.py")
)
dispatcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatcher)


# ---------------------------------------------------------------- helpers


results: list[tuple[str, bool]] = []


def check(name: str, condition: bool) -> None:
    results.append((name, condition))
    print(("ok   " if condition else "FAIL ") + name)


def write_scenario(scenario: dict) -> None:
    scenario_file.write_text(json.dumps(scenario), encoding="utf-8")


def read_log(path: Path) -> list:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def spawns() -> list:
    return read_log(spawn_log)


def git_calls() -> list:
    return read_log(git_log)


def tea_calls() -> list:
    return read_log(tea_log)


def scope_calls() -> list:
    return read_log(scope_log)


def claude_calls() -> list:
    return read_log(claude_log)


def events() -> dict:
    return {
        path.name: json.loads(path.read_text(encoding="utf-8"))
        for path in (state / "events").glob("*.json")
    }


def processed(name: str):
    path = state / "processed" / (name + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def clear_spool() -> None:
    for path in (state / "events").glob("*.json"):
        path.unlink()


def comment_event(number, body, sender="jracon", state_name="open", labels=None, is_pr=False):
    issue = {"number": number, "state": state_name, "labels": labels or []}
    if is_pr:
        issue["pull_request"] = {"url": "x"}
    return {
        "action": "created",
        "issue": issue,
        "comment": {"body": body},
        "repository": {"full_name": REPO},
        "sender": {"login": sender},
    }


def pr_event(action, number, head, body=""):
    return {
        "action": action,
        "number": number,
        "pull_request": {"head": {"ref": head}, "body": body},
        "repository": {"full_name": REPO},
        "sender": {"login": "jracon"},
    }


def gated_comment(number, body, sender="jracon", delivery="d"):
    dispatcher.handle_payload(
        "issue_comment", comment_event(number, body, sender=sender, labels=["gate"]), delivery
    )


write_scenario({"issues_list": [], "issues": {}, "pulls_list": [], "pulls": {}})


# ------------------------------------------------------- filter and spool


gated_comment(35, "please work", delivery="d1")
spool = events()
check(
    "a gated comment queues a worker leg",
    len(spool) == 1 and spool["d1.json"]["kind"] == "worker"
    and spool["d1.json"]["branch"] == "ai/issue-35",
)

gated_comment(35, "please work again", delivery="d1")
check("the same delivery id is skipped", len(events()) == 1)

dispatcher.sweep()
entry = dispatcher.inflight().get("ai/issue-35")
spawn_argv = spawns()[0]["argv"]
check(
    "a sweep spawns the leg and takes the in-flight slot",
    len(spawns()) == 1
    and spawn_argv[:3] == ["spawn", "genixis-test", "ai/issue-35"]
    and spawn_argv[spawn_argv.index("--permission-mode") + 1] == "dontAsk"
    and "Work issue 35" in spawns()[0]["argv"][-1]
    and processed("d1") is not None
    and entry is not None
    and entry["session"] == "genixis-test: ai/issue-35",
)
scope = scope_calls()
check(
    "each spawn runs inside a transient user scope",
    len(scope) == 1
    and scope[0][:5] == [
        "--user", "--scope", "--collect", "--quiet", "--expand-environment=no",
    ]
    and scope[0][6:9] == ["spawn", "genixis-test", "ai/issue-35"],
)

gated_comment(35, "done, pull request 100 is open", sender=AGENT, delivery="d2")
check(
    "an agent comment spawns nothing and releases the slot",
    len(events()) == 0 and "ai/issue-35" not in dispatcher.inflight(),
)
check(
    "the release stops the background session of the leg",
    claude_calls() == [["stop", "genixis-test: ai/issue-35"]],
)

dispatcher.take_slot("ai/issue-35", "live-session", 35)
gated_comment(35, "and one more thing", delivery="d3")
dispatcher.sweep()
check(
    "an event for an in-flight branch waits in the spool",
    "d3.json" in events() and len(spawns()) == 1,
)

gated_comment(35, "another nudge", delivery="d4")
check(
    "a delivery for a branch with a pending event is superseded",
    len([e for e in events().values() if e["branch"] == "ai/issue-35"]) == 1
    and (processed("d4") or {}).get("superseded") is True,
)

gated_comment(35, "done for real", sender=AGENT, delivery="d5")
dispatcher.sweep()
check(
    "the waiting event runs after the release",
    len(events()) == 0 and len(spawns()) == 2 and processed("d3") is not None,
)

dispatcher.handle_payload(
    "issue_comment", comment_event(36, "/loop go", labels=[]), "d6"
)
spool = events()
check(
    "a /loop comment works without the gate label",
    spool.get("d6.json", {}).get("branch") == "ai/issue-36",
)
clear_spool()

dispatcher.handle_payload("issue_comment", comment_event(37, "hello", labels=[]), "d7")
check("a comment without gate label and prefix is ignored", len(events()) == 0)

dispatcher.handle_payload(
    "issue_comment",
    comment_event(35, "too late", state_name="closed", labels=["gate"]),
    "d8",
)
check("a comment on a closed issue is ignored", len(events()) == 0)

closed_repo = comment_event(35, "hi", labels=["gate"])
closed_repo["repository"]["full_name"] = "other/repo"
dispatcher.handle_payload("issue_comment", closed_repo, "d9")
check("an event of another repository is ignored", len(events()) == 0)

write_scenario(
    {
        "issues_list": [],
        "issues": {},
        "pulls_list": [],
        "pulls": {"100": {"head": {"ref": "ai/issue-35"}}},
    }
)
dispatcher.handle_payload(
    "issue_comment", comment_event(100, "fix the findings", is_pr=True), "d10"
)
spool = events()
check(
    "a human comment on a pull request queues a nudge leg",
    spool.get("d10.json", {}).get("kind") == "nudge"
    and spool["d10.json"]["branch"] == "ai/issue-35"
    and spool["d10.json"]["entity"] == 100,
)
gated_comment(35, "the worker finished", sender=AGENT, delivery="d10r")
dispatcher.sweep()
check(
    "the nudge prompt names the pull request and forbids a second one",
    len(spawns()) == 3
    and "pull request 100" in spawns()[2]["argv"][-1]
    and "do not open a second one" in spawns()[2]["argv"][-1]
    and "Work issue" not in spawns()[2]["argv"][-1],
)

dispatcher.handle_payload(
    "pull_request", pr_event("opened", 100, "ai/issue-35", "Closes #35"), "d11"
)
spool = events()
check(
    "an opened ai/ pull request queues a reviewer leg and records the link",
    spool.get("d11.json", {}).get("kind") == "reviewer"
    and spool["d11.json"]["branch"] == "ai/review-100"
    and spool["d11.json"]["issue"] == 35
    and dispatcher.load_json(state / "links.json", {}).get("100") == 35,
)
dispatcher.sweep()
git_args = git_calls()
check(
    "the reviewer branch is pointed at the worker tip with plain git",
    ["branch", "-f", "ai/review-100", "refs/remotes/origin/ai/issue-35"] in git_args
    and ["branch", "--set-upstream-to=origin/ai/issue-35", "ai/review-100"] in git_args
    and "Review pull request 100" in spawns()[3]["argv"][-1],
)

dispatcher.handle_payload(
    "pull_request", pr_event("synchronized", 100, "ai/issue-35"), "d12"
)
dispatcher.sweep()
check(
    "a push while the review is in flight waits in the spool",
    "d12.json" in events() and len(spawns()) == 4,
)

dispatcher.handle_payload(
    "pull_request", pr_event("closed", 100, "ai/issue-35"), "d13"
)
inflight = dispatcher.inflight()
check(
    "a closed pull request releases both in-flight entries",
    "ai/issue-35" not in inflight and "ai/review-100" not in inflight,
)
check(
    "a closed pull request stops the sessions of both legs",
    claude_calls()[-2:] == [
        ["stop", "genixis-test: ai/issue-35"],
        ["stop", "genixis-test: ai/review-100"],
    ],
)
clear_spool()

dispatcher.handle_payload(
    "pull_request", pr_event("opened", 101, "feature/x"), "d14"
)
check("a pull request without an ai/ head is ignored", len(events()) == 0)

# a crashed leg: the two-hour ttl drops its entry, and the drop also stops
# its session, so nothing of the leg keeps running on the host
dispatcher.take_slot("ai/issue-45", "stale-session", 45)
inflight = dispatcher.inflight()
inflight["ai/issue-45"]["since"] = int(time.time()) - 3 * 3600
dispatcher.store_json(state / "inflight.json", inflight)
check(
    "the ttl drop of a crashed leg stops its session",
    dispatcher.claim_slot("ai/issue-45")
    and ["stop", "stale-session"] in claude_calls(),
)

codes_file.write_text("11\n0\n", encoding="utf-8")
gated_comment(38, "work this too", delivery="d15")
dispatcher.sweep()
check(
    "a rate-limited spawn is retried and then succeeds",
    len(spawns()) == 6
    and [s["code"] for s in spawns()[4:]] == [11, 0]
    and processed("d15") is not None,
)

codes_file.write_text("7\n", encoding="utf-8")
gated_comment(39, "and this", delivery="d16")
dispatcher.sweep()
comment_bodies = [" ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]]
check(
    "a refused spawn escalates to the owner on the entity",
    (state / "failed" / "d16.json").exists()
    and len(comment_bodies) == 1
    and "39" in comment_bodies[0]
    and "jracon" in comment_bodies[0],
)


# --------------------------------------------------- the stale-base guard


# a clone that cannot reach origin must spawn nothing: a leg on a base that
# cannot be verified against origin main works on problems that main already
# solved (issue #100), so the sweep says so on the entity instead
os.environ["DISPATCHER_TEST_GIT_FAIL"] = "fetch"
gated_comment(46, "work while offline", delivery="d17")
dispatcher.sweep()
comment_bodies = [" ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]]
check(
    "a failed fetch of the clone spawns nothing and reports on the entity",
    (state / "failed" / "d17.json").exists()
    and len(spawns()) == 7
    and len(comment_bodies) == 2
    and "46" in comment_bodies[1]
    and "did not start" in comment_bodies[1]
    and "origin main" in comment_bodies[1],
)
os.environ.pop("DISPATCHER_TEST_GIT_FAIL")

# with origin back, the sweep fetches the clone and the leg runs: the fetch
# is the last git call of that pass, and the spawn it verified is the one
# after the guard
gated_comment(47, "work again", delivery="d18")
dispatcher.sweep()
check(
    "a healthy fetch lets the spawn run",
    processed("d18") is not None
    and len(spawns()) == 8
    and git_calls()[-1][:2] == ["fetch", "origin"]
    and spawns()[7]["argv"][2] == "ai/issue-47",
)


# --------------------------------------------------------- poll fallback


clear_spool()
(state / "poll-cursor.json").unlink(missing_ok=True)
write_scenario(
    {
        "issues_list": [{"index": 35}],
        "issues": {
            "35": {
                "index": 35,
                "comments": [
                    {"id": 1, "author": "jracon", "body": "old work"},
                    {"id": 2, "author": AGENT, "body": "done"},
                ],
            }
        },
        "pulls_list": [{"index": 100, "head": {"ref": "ai/issue-35"}, "body": "Closes #35"}],
        "pulls": {"100": {"head": {"ref": "ai/issue-35"}}},
    }
)
dispatcher.take_slot("ai/issue-35", "live-session", 35)
dispatcher.poll()
cursor = dispatcher.load_json(state / "poll-cursor.json", {})
check(
    "the first poll records the baseline and queues nothing",
    len(events()) == 0
    and cursor.get("issues", {}).get("35") == 2
    and cursor.get("prs") == ["100"],
)
check(
    "an agent comment that the poll reads releases the slot",
    "ai/issue-35" not in dispatcher.inflight(),
)

scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["35"]["comments"].append(
    {"id": 3, "author": "jracon", "body": "more work"}
)
write_scenario(scenario)
dispatcher.poll()
check(
    "the second poll queues and sweeps a worker leg for a new human comment",
    processed("poll-3") is not None
    and len(spawns()) == 9
    and spawns()[8]["argv"][2] == "ai/issue-35"
    and "Work issue 35" in spawns()[8]["argv"][-1],
)

scenario["pulls_list"].append(
    {"index": 102, "head": {"ref": "ai/issue-41"}, "body": "Closes #41"}
)
write_scenario(scenario)
dispatcher.poll()
check(
    "the poll queues and sweeps a reviewer leg for a new ai/ pull request",
    processed("poll-pr-102") is not None
    and len(spawns()) == 10
    and spawns()[9]["argv"][2] == "ai/review-102"
    and "Review pull request 102" in spawns()[9]["argv"][-1],
)
check(
    "every tea call names the repository",
    bool(tea_calls())
    and all("--repo" in call and "jracon/genixis" in call for call in tea_calls()),
)
clear_spool()


# --------------------------------------------------- leg gate environment

# a spawned leg inherits the environment of the dispatcher unit, so the unit
# source decides whether the leg can run the machine gate itself (issue #96):
# the unit PATH must carry python3, or the two allowlisted harness commands
# exit 127. No unit may carry a sandbox option: every sandbox option in a
# user unit implies PrivateUsers, the namespace makes root-owned files read
# as nobody, and ssh then refuses the store symlink ~/.ssh/config, so every
# fetch and push of a leg fails (the run of issue 93 proved it)
unit_source = (Path(__file__).with_name("dispatcher.nix")).read_text(encoding="utf-8")
check(
    "the unit PATH carries python3 for the harness commands",
    "PATH=${unitPath}" in unit_source and "${pkgs.python3}/bin" in unit_source,
)
check(
    "no dispatcher unit sets a sandbox option",
    "TemporaryFileSystem" not in unit_source and "PrivateUsers" not in unit_source,
)


# ------------------------------------------------------------- receiver


server = ThreadingHTTPServer(("127.0.0.1", 0), dispatcher.Receiver)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % server.server_address[1]


def post(headers: dict, raw: bytes) -> int:
    request = urllib.request.Request(base, data=raw, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def wait_for(condition, timeout=10.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if condition():
            return True
        time.sleep(0.05)
    return False


def signed_headers(event: str, delivery: str, raw: bytes) -> dict:
    digest = hmac.new(b"test-secret", raw, hashlib.sha256).hexdigest()
    return {
        "Content-Type": "application/json",
        "X-Forgejo-Event": event,
        "X-Forgejo-Delivery": delivery,
        "X-Forgejo-Signature": digest,
    }


raw = json.dumps(comment_event(44, "fresh work", labels=["gate"])).encode()
status = post(signed_headers("issue_comment", "recv-1", raw) | {"X-Forgejo-Signature": "0" * 64}, raw)
check("a delivery with a wrong signature gets 403", status == 403 and len(events()) == 0)

status = post(signed_headers("issue_comment", "recv-2", raw), raw)
swept = wait_for(lambda: processed("recv-2") is not None)
check(
    "a signed delivery is accepted and swept",
    status == 200 and swept and len(spawns()) == 11,
)

status = post(signed_headers("ping", "recv-3", b"{}"), b"{}")
check("a ping delivery is accepted and ignored", status == 200 and len(events()) == 0)

# every spawn attempt, retried or failed, went through the scope wrapper:
# the machinery of no leg can land in the cgroup of the receiver unit
check(
    "every spawn attempt went through the scope wrapper",
    len(scope_calls()) == len(spawns()),
)

# a client that opens a connection and sends no data: the read timeout
# (0.5s in this harness) must close it, so no thread of the receiver waits
stalled = socket.create_connection(("127.0.0.1", server.server_address[1]))
stalled.settimeout(5)
started = time.monotonic()
try:
    quiet = stalled.recv(1) == b""
except OSError:
    quiet = False
elapsed = time.monotonic() - started
stalled.close()
check(
    "a connection that sends nothing is closed after the read timeout",
    quiet and 0.4 <= elapsed < 5,
)

# a client that dribbles one byte every 0.15 seconds: every single read
# stays under the socket timeout (0.5s here), so only the request
# deadline (1s here) can end the connection and free the thread
dribble = socket.create_connection(("127.0.0.1", server.server_address[1]))
dribble.settimeout(5)
started = time.monotonic()
cut = False
try:
    for _ in range(60):
        dribble.sendall(b"x")
        time.sleep(0.15)
except OSError:
    cut = True
elapsed = time.monotonic() - started
dribble.close()
check(
    "a connection that sends one byte at a time is cut at the request deadline",
    cut and 0.8 <= elapsed < 5,
)

server.shutdown()
server.server_close()
shutil.rmtree(root, ignore_errors=True)

failed = [name for name, ok in results if not ok]
print("%d of %d checks pass" % (len(results) - len(failed), len(results)))
if failed:
    print("failed: " + ", ".join(failed))
    sys.exit(1)
