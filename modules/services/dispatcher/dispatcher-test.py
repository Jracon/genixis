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

import contextlib
import hashlib
import hmac
import importlib.util
import io
import json
import logging
import re
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

# the session listing that the claude stub answers `agents --json` with:
# one background entry for each session name that a name-fallback release in
# this harness stops (an in-flight entry that predates the session id,
# issue #208), and one interactive entry, so the kind filter of the
# dispatcher has an entry to refuse
default_claude_sessions = json.dumps(
    [
        {"id": "bg-35", "kind": "background", "name": "genixis-test: ai/issue-35"},
        {"id": "bg-77", "kind": "background", "name": "genixis-test: ai/issue-77"},
        {"id": "bg-100r", "kind": "background", "name": "genixis-test: ai/review-100"},
        {"id": "bg-live", "kind": "background", "name": "live-session"},
        {"id": "bg-stale", "kind": "background", "name": "stale-session"},
        {"id": "fg-main", "kind": "interactive", "name": "genixis: main"},
    ]
)

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
elif argv[0] == "pulls" and argv[1] == "review-comments":
    print(json.dumps(scenario.get("review_comments", {}).get(argv[2], [])))
elif argv[0] == "comments" and argv[1] == "list":
    # the real tea answers a comments read of an empty set with the human
    # sentence and exit 0, never with JSON (issue #421), so the stub answers
    # the same shape
    listed = scenario.get("comments", {}).get(argv[2], [])
    if listed:
        print(json.dumps(listed))
    else:
        print("No comments found")
elif argv[0] == "pulls":
    print(json.dumps(scenario["pulls"][argv[1]]))
elif argv[0] == "issues" and argv[1] == "list":
    print(json.dumps(scenario["issues_list"]))
elif argv[:2] == ["issues", "edit"]:
    # the one label write of the loop (issue #525): apply it to every
    # scenario entry that names the entity, then keep the file, so a later
    # read of the same entity sees the changed labels and a check catches a
    # write that runs before a read that must precede it. An edit of an
    # entity that no entry names changes nothing, the answer of the forge
    # for a label that no entity holds
    entity = argv[2] if len(argv) > 2 else ""
    entries = []
    for group in ("pulls", "issues"):
        entry = scenario.get(group, {}).get(entity)
        if isinstance(entry, dict):
            entries.append(entry)
    for group in ("pulls_list", "issues_list"):
        for entry in scenario.get(group, []):
            if isinstance(entry, dict) and str(entry.get("index")) == entity:
                entries.append(entry)
    for entry in entries:
        if "labels" not in entry:
            # a removal on an entity that holds no label list changes
            # nothing and leaves the entry untouched, the answer of the
            # forge: the shape of an entity must not drift through a no-op
            # edit, or two payload reads around one drift apart
            if not any(flag == "--add-labels" for flag in argv):
                continue
            entry["labels"] = []
        labels = entry["labels"] if isinstance(entry["labels"], list) else []
        for i in range(len(argv) - 1):
            name = argv[i + 1]
            if argv[i] == "--add-labels":
                known = [l.get("name") if isinstance(l, dict) else l for l in labels]
                if name not in known:
                    labels.append({"name": name})
            elif argv[i] == "--remove-labels":
                labels = [
                    l
                    for l in labels
                    if (l.get("name") if isinstance(l, dict) else l) != name
                ]
        entry["labels"] = labels
    if entries:
        with open(os.environ["DISPATCHER_TEST_TEA"], "w") as handle:
            json.dump(scenario, handle)
    sys.exit(0)
elif argv[0] == "issues":
    print(json.dumps(scenario["issues"][argv[1]]))
else:
    sys.exit(2)
"""

# the project stub answers as the phase 3 binary: the envelope carries the
# session name, the session id that `claude --bg` printed (issue #208), the
# full session uuid of the session listing (issue #524), and the worktree,
# and its stderr carries one diagnostic line, so the harness can check that
# the stderr of a spawn reaches the log of the dispatcher
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
    print(json.dumps({"data": {
        "session": "genixis-test: " + branch,
        "session_id": "sid-" + branch,
        "session_uuid": "uuid-" + branch.replace("/", "-"),
        "worktree": "/nowhere",
    }, "meta": {"exit_code": code, "duration_ms": 1}}))
print("stub: view window opened", file=sys.stderr)
sys.exit(code)
"""

GIT_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_GIT_LOG"], "a") as handle:
    handle.write(json.dumps(argv) + "\n")
if argv[:1] == ["symbolic-ref"]:
    # origin/HEAD names the default branch of the clone; an empty knob of
    # the environment answers no default branch
    print(os.environ.get("DISPATCHER_TEST_GIT_ORIGIN_HEAD", "origin/main"))
fail = os.environ.get("DISPATCHER_TEST_GIT_FAIL", "")
if fail and fail in " ".join(argv):
    sys.exit(1)
sys.exit(0)
"""

# stands in for systemd-run: it logs its own arguments, then replaces
# itself with the command after the options, so the exit code and the
# stdout of the wrapped spawn flow back to the dispatcher unchanged. The
# options of the sandbox tier ride along: --unit=, --service-type=, -p, and
# -E carry their own values, a -p StandardOutput=append:<path> or
# StandardError=append:<path> moves the stream of the wrapped command into
# that file the way the real unit file directive does, and each -E entry
# enters the environment of the wrapped command, so the stub answers the
# same shape for the scope of the code before the tier and the forking
# service of the tier
SYSTEMD_RUN_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_SYSTEMD_RUN_LOG"], "a") as handle:
    handle.write(json.dumps(argv) + "\n")
value_options = {"-p", "-E"}
skip_values = {"--unit", "--service-type"}
command = []
index = 0
stdout_path = ""
stderr_path = ""
while index < len(argv):
    arg = argv[index]
    index += 1
    if not arg.startswith("-"):
        command = argv[index - 1:]
        break
    if "=" in arg and arg.startswith("--"):
        continue
    if arg in skip_values:
        index += 1
        continue
    if arg in value_options:
        value = argv[index]
        index += 1
        if arg == "-E" and "=" in value:
            name, _, env_value = value.partition("=")
            os.environ[name] = env_value
        if arg == "-p":
            if value.startswith("StandardOutput=append:"):
                stdout_path = value[len("StandardOutput=append:"):]
            if value.startswith("StandardError=append:"):
                stderr_path = value[len("StandardError=append:"):]
        continue
if stdout_path:
    handle = open(stdout_path, "a")
    os.dup2(handle.fileno(), 1)
if stderr_path:
    handle = open(stderr_path, "a")
    os.dup2(handle.fileno(), 2)
os.execvp(command[0], command)
"""

# stands in for claude: `agents --json` answers with the session listing
# that the environment names, so a release of an entry without a recorded
# id resolves the session name of its leg to the id that the stop call must
# use (issue #144); every other call only logs and succeeds. The log names
# the config directory of the harness instance that the call reached, so a
# check of the tier proves that the stop and the listing of a leg speak to
# the instance of that leg
CLAUDE_STUB = r"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["DISPATCHER_TEST_CLAUDE_LOG"], "a") as handle:
    handle.write(json.dumps({"argv": argv, "config_dir": os.environ.get("CLAUDE_CONFIG_DIR", "")}) + "\n")
if argv[:1] == ["agents"]:
    print(os.environ.get("DISPATCHER_TEST_CLAUDE_SESSIONS", "[]"))
sys.exit(0)
"""

# the agent stubs of the tier: ssh-agent logs and stays short-lived, and
# ssh-add logs the key it loaded and answers success, so the harness checks
# the agent start and the key load without a real agent
SSH_AGENT_STUB = r"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["DISPATCHER_TEST_SSH_AGENT_LOG"], "a") as handle:
    handle.write(json.dumps(sys.argv[1:]) + "\n")
sys.exit(0)
"""

SSH_ADD_STUB = r"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["DISPATCHER_TEST_SSH_ADD_LOG"], "a") as handle:
    handle.write(json.dumps({"argv": sys.argv[1:], "sock": os.environ.get("SSH_AUTH_SOCK", "")}) + "\n")
sys.exit(0)
"""

# stands in for systemctl: the release of the tier stops the transient units
# of a leg through it, and the log proves which units it stopped
SYSTEMCTL_STUB = r"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["DISPATCHER_TEST_SYSTEMCTL_LOG"], "a") as handle:
    handle.write(json.dumps(sys.argv[1:]) + "\n")
sys.exit(0)
"""

push_key_file = root / "push-key"
push_key_file.write_text("test-push-key\n", encoding="utf-8")

for name, text in (
    ("tea-stub", TEA_STUB),
    ("project-stub", PROJECT_STUB),
    ("git-stub", GIT_STUB),
    ("systemd-run-stub", SYSTEMD_RUN_STUB),
    ("claude-stub", CLAUDE_STUB),
    ("ssh-agent-stub", SSH_AGENT_STUB),
    ("ssh-add-stub", SSH_ADD_STUB),
    ("systemctl-stub", SYSTEMCTL_STUB),
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
        "DISPATCHER_SSH_AGENT": str(stubs / "ssh-agent-stub"),
        "DISPATCHER_SSH_ADD": str(stubs / "ssh-add-stub"),
        "DISPATCHER_SYSTEMCTL": str(stubs / "systemctl-stub"),
        "DISPATCHER_PUSH_KEY": str(push_key_file),
        "DISPATCHER_WEBHOOK_SECRET_FILE": str(secret_file),
        # the daemon root of the harness (issue 633): the real root is /tmp,
        # and the harness of this test writes nothing outside its temporary
        # directory, so the socket links of the tier rows land under root
        "DISPATCHER_DAEMON_TMP_ROOT": str(root / "tmp-root"),
        "DISPATCHER_READ_TIMEOUT": "0.5",
        "DISPATCHER_REQUEST_TIMEOUT": "1",
        "DISPATCHER_RETRY_DELAYS": "0,0",
        # the floor of the spawn pace is 0 for the whole run, so each sweep
        # measures the one-attempt rule alone; the dedicated pace section below
        # turns the floor on through the module global, because the knob is
        # read at import time
        "DISPATCHER_SPAWN_SPACING": "0",
        "DISPATCHER_TEST_TEA": str(scenario_file),
        "DISPATCHER_TEST_TEA_LOG": str(tea_log),
        "DISPATCHER_TEST_PROJECT_LOG": str(spawn_log),
        "DISPATCHER_TEST_PROJECT_CODES": str(codes_file),
        "DISPATCHER_TEST_GIT_LOG": str(git_log),
        "DISPATCHER_TEST_SYSTEMD_RUN_LOG": str(scope_log),
        "DISPATCHER_TEST_CLAUDE_LOG": str(claude_log),
        "DISPATCHER_TEST_CLAUDE_SESSIONS": default_claude_sessions,
        "DISPATCHER_TEST_SSH_AGENT_LOG": str(root / "ssh-agent-log.jsonl"),
        "DISPATCHER_TEST_SSH_ADD_LOG": str(root / "ssh-add-log.jsonl"),
        "DISPATCHER_TEST_SYSTEMCTL_LOG": str(root / "systemctl-log.jsonl"),
        "DISPATCHER_LOG": "ERROR",
    }
)

spec = importlib.util.spec_from_file_location(
    "dispatcher_under_test", Path(__file__).with_name("dispatcher.py")
)
assert spec is not None and spec.loader is not None
dispatcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dispatcher)


# ---------------------------------------------------------------- helpers


results: list[tuple[str, bool]] = []


# the log of the dispatcher under test, caught in memory: the harness checks
# that the stderr of a spawn reaches it (issue #208), because the journal of
# the unit is where a person reads why a view window did not open
log_messages: list[str] = []


class LogCatcher(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        log_messages.append(record.getMessage())


dispatcher.log.addHandler(LogCatcher())
dispatcher.log.setLevel(logging.INFO)


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


def delivery_calls(feed):
    """The tea calls that one delivery pass appends to the log (issue #583):
    the slice of the call log between two reads, so a check counts the tea
    calls of one delivery alone."""
    before = len(tea_calls())
    feed()
    return tea_calls()[before:]


def listing_calls(calls):
    """The calls of a pass that list the open pull requests."""
    return [call for call in calls if call[:2] == ["pulls", "list"]]


def pull_reads(calls):
    """The calls of a pass that read one pull request: the per-pull
    head-sha reads of the sha scan of the gate mapping."""
    return [call for call in calls if call[:1] == ["pulls"] and call[1].isdigit()]


def scope_calls() -> list:
    return read_log(scope_log)


def claude_calls() -> list:
    # the claude stub logs one object per call, with the argv and the config
    # directory of the harness instance it reached; the argv list of every
    # call keeps the old comparisons working
    return [entry["argv"] for entry in read_log(claude_log) if isinstance(entry, dict)]


def claude_config_dirs() -> list:
    return [
        entry.get("config_dir", "")
        for entry in read_log(claude_log)
        if isinstance(entry, dict)
    ]


def events() -> dict:
    return {
        path.name: json.loads(path.read_text(encoding="utf-8"))
        for path in (state / "events").glob("*.json")
    }


def processed(name: str):
    path = state / "processed" / (name + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def queued_event(name: str) -> dict:
    """The event of name from the spool or from the processed records, as one
    dict: the empty dict when neither holds it, so a check reads one shape
    whether the sweep already took the event."""
    entry = events().get(name + ".json") or processed(name) or {}
    return entry if isinstance(entry, dict) else {}


def clear_spool() -> None:
    for path in (state / "events").glob("*.json"):
        path.unlink()


def comment_event(
    number, body, sender="jracon", state_name="open", labels=None, is_pr=False
):
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


def loop_comment(number, body, sender="jracon", delivery="d"):
    dispatcher.handle_payload(
        "issue_comment",
        comment_event(number, "/loop " + body, sender=sender),
        delivery,
    )


# the readiness body of a ready issue: one plain line per class, the shape
# that the gate of the dispatcher parses (issue #356, L2). Every issue that a
# check of this harness sends through a worker path carries either this body
# or no scenario entry at all, which makes the tea read fail and the gate
# fail open (the same rule the receiver applies to every tea read)
def ready_body(extra=""):
    lines = [
        "Readiness A: the reference is main.",
        "Readiness B: the gate of the repository is the oracle.",
        "Readiness C: not applicable by jracon",
        "Readiness D: no materials, decided by jracon",
        "Readiness E: the build rules of the repository hold.",
        "Readiness F: the factory skill holds the loop contract.",
    ]
    return "\n".join(lines) + extra


write_scenario(
    {
        "issues_list": [],
        "issues": {"35": {"index": 35, "body": ready_body()}},
        "pulls_list": [],
        "pulls": {},
    }
)


# ------------------------------------------------------- filter and spool


loop_comment(35, "please work", delivery="d1")
spool = events()
check(
    "a /loop comment queues a worker leg",
    len(spool) == 1
    and spool["d1.json"]["kind"] == "worker"
    and spool["d1.json"]["branch"] == "ai/issue-35",
)

loop_comment(35, "please work again", delivery="d1")
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
    and "one plain command" in spawns()[0]["argv"][-1]
    and processed("d1") is not None
    and entry is not None
    and entry["session"] == "genixis-test: ai/issue-35"
    and entry["session_id"] == "sid-ai/issue-35",
)
check(
    "the stderr of a spawn reaches the log of the dispatcher",
    any(
        "spawn of ai/issue-35 stderr" in message
        and "stub: view window opened" in message
        for message in log_messages
    ),
)
scope = scope_calls()
check(
    "each spawn runs inside a transient user scope",
    len(scope) == 1
    and scope[0][:5]
    == [
        "--user",
        "--scope",
        "--collect",
        "--quiet",
        "--expand-environment=no",
    ]
    and scope[0][6:9] == ["spawn", "genixis-test", "ai/issue-35"],
)

loop_comment(35, "done, pull request 100 is open", sender=AGENT, delivery="d2")
check(
    "an agent comment spawns nothing and releases the slot",
    len(events()) == 0 and "ai/issue-35" not in dispatcher.inflight(),
)
check(
    "the release stops the session by its recorded id and reads no listing",
    claude_calls() == [["stop", "sid-ai/issue-35"]],
)

# an entry that predates the session id (issue #208): the release falls back
# to the name lookup of issue #144, because `claude stop` accepts no name
dispatcher.take_slot("ai/issue-35", "live-session", "", 35)
loop_comment(35, "and one more thing", delivery="d3")
dispatcher.sweep()
check(
    "an event for an in-flight branch waits in the spool",
    "d3.json" in events() and len(spawns()) == 1,
)

loop_comment(35, "another nudge", delivery="d4")
check(
    "a delivery for a branch with a pending event is superseded",
    len([e for e in events().values() if e["branch"] == "ai/issue-35"]) == 1
    and (processed("d4") or {}).get("superseded") is True,
)

loop_comment(35, "done for real", sender=AGENT, delivery="d5")
dispatcher.sweep()
check(
    "the waiting event runs after the release",
    len(events()) == 0 and len(spawns()) == 2 and processed("d3") is not None,
)

# the three shapes of the loop command (issue #387): the command with prose
# on the same line, the command alone, and the command with prose on later
# lines, the shape of the silent delivery on issue #372. Each case must queue
# the worker leg
dispatcher.handle_payload(
    "issue_comment", comment_event(36, "/loop go", labels=[]), "d6"
)
spool = events()
check(
    "a /loop comment with prose on the same line queues the worker leg",
    spool.get("d6.json", {}).get("branch") == "ai/issue-36"
    and spool["d6.json"]["kind"] == "worker",
)
clear_spool()

dispatcher.handle_payload("issue_comment", comment_event(53, "/loop", labels=[]), "d6b")
spool = events()
check(
    "a /loop comment with no prose queues the worker leg",
    spool.get("d6b.json", {}).get("branch") == "ai/issue-53"
    and spool["d6b.json"]["kind"] == "worker",
)

dispatcher.handle_payload(
    "issue_comment",
    comment_event(54, "/loop\n\nthe branch protection of main is the block", labels=[]),
    "d6c",
)
spool = events()
check(
    "a /loop comment with prose on later lines queues the worker leg",
    spool.get("d6c.json", {}).get("branch") == "ai/issue-54"
    and spool["d6c.json"]["kind"] == "worker",
)
clear_spool()

dispatcher.handle_payload("issue_comment", comment_event(37, "hello", labels=[]), "d7")
check("a plain comment on an issue starts nothing", len(events()) == 0)

# the retired gate label: the label triggered a leg for every comment while
# it stood; it triggers nothing now, and a comment that carries it is prose
# (issue #525, the label decision of the owner)
dispatcher.handle_payload(
    "issue_comment", comment_event(37, "please work", labels=["gate"]), "d7b"
)
check(
    "a plain comment on an issue with the retired gate label starts nothing",
    len(events()) == 0,
)

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
check(
    "a plain comment on a pull request starts nothing",
    len(events()) == 0,
)
dispatcher.handle_payload(
    "issue_comment", comment_event(100, "/loop fix the findings", is_pr=True), "d10"
)
spool = events()
check(
    "a /loop comment on a pull request queues a nudge leg",
    spool.get("d10.json", {}).get("kind") == "nudge"
    and spool["d10.json"]["branch"] == "ai/issue-35"
    and spool["d10.json"]["entity"] == 100,
)
loop_comment(35, "the worker finished", sender=AGENT, delivery="d10r")
dispatcher.sweep()
check(
    "the nudge prompt names the pull request and forbids a second one",
    len(spawns()) == 3
    and "pull request 100" in spawns()[2]["argv"][-1]
    and "do not open a second one" in spawns()[2]["argv"][-1]
    and "one plain command" in spawns()[2]["argv"][-1]
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
    and "Review pull request 100" in spawns()[3]["argv"][-1]
    and "one plain command" in spawns()[3]["argv"][-1],
)

dispatcher.handle_payload(
    "pull_request", pr_event("synchronized", 100, "ai/issue-35"), "d12"
)
dispatcher.sweep()
check(
    "a push while the review is in flight waits in the spool",
    "d12.json" in events() and len(spawns()) == 4,
)

dispatcher.handle_payload("pull_request", pr_event("closed", 100, "ai/issue-35"), "d13")
inflight = dispatcher.inflight()
check(
    "a closed pull request releases both in-flight entries",
    "ai/issue-35" not in inflight and "ai/review-100" not in inflight,
)
check(
    "a closed pull request stops the sessions of both legs by their ids",
    claude_calls()[-2:]
    == [
        ["stop", "sid-ai/issue-35"],
        ["stop", "sid-ai/review-100"],
    ],
)
clear_spool()

dispatcher.handle_payload("pull_request", pr_event("opened", 101, "feature/x"), "d14")
check("a pull request without an ai/ head is ignored", len(events()) == 0)

# a crashed leg: the two-hour ttl drops its entry, and the drop also stops
# its session, so nothing of the leg keeps running on the host; the entry
# has no id, so the stop goes through the name fallback
dispatcher.take_slot("ai/issue-45", "stale-session", "", 45)
inflight = dispatcher.inflight()
inflight["ai/issue-45"]["since"] = int(time.time()) - 3 * 3600
dispatcher.store_json(state / "inflight.json", inflight)
check(
    "the ttl drop of a crashed leg stops its session",
    dispatcher.claim_slot("ai/issue-45") and ["stop", "bg-stale"] in claude_calls(),
)

# the stop call of a release names the id of the session, never its name.
# An entry with a recorded id (issue #208) stops by it with no listing read;
# an entry without one falls back to the name lookup of issue #144, and only
# a background entry counts: the listing here holds one background and one
# interactive entry under the name of the leg, and a name that no background
# entry holds stops nothing
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = json.dumps(
    [
        {"id": "bg-dup", "kind": "background", "name": "dup-session"},
        {"id": "fg-dup", "kind": "interactive", "name": "dup-session"},
        {"id": "fg-quiet", "kind": "interactive", "name": "quiet-session"},
    ]
)
stops_before = [call for call in claude_calls() if call[:1] == ["stop"]]
calls_before = len(claude_calls())
dispatcher.take_slot("ai/issue-50", "dup-session", "bg-50-recorded", 50)
dispatcher.release_entity(50)
check(
    "a release of an entry with a recorded id stops by it and reads no listing",
    claude_calls()[calls_before:] == [["stop", "bg-50-recorded"]],
)
dispatcher.take_slot("ai/issue-52", "dup-session", "", 52)
dispatcher.release_entity(52)
check(
    "a release of an entry without an id stops only the background id under the name",
    [call for call in claude_calls() if call[:1] == ["stop"]]
    == stops_before + [["stop", "bg-50-recorded"], ["stop", "bg-dup"]],
)
dispatcher.take_slot("ai/issue-51", "quiet-session", "", 51)
dispatcher.release_entity(51)
check(
    "a session name that no background entry holds stops nothing",
    [call for call in claude_calls() if call[:1] == ["stop"]]
    == stops_before + [["stop", "bg-50-recorded"], ["stop", "bg-dup"]],
)
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = default_claude_sessions

codes_file.write_text("11\n0\n", encoding="utf-8")
loop_comment(38, "work this too", delivery="d15")
dispatcher.sweep()
check(
    "a rate-limited spawn is retried and then succeeds",
    len(spawns()) == 6
    and [s["code"] for s in spawns()[4:]] == [11, 0]
    and processed("d15") is not None,
)

codes_file.write_text("7\n", encoding="utf-8")
loop_comment(39, "and this", delivery="d16")
dispatcher.sweep()
comment_bodies = [
    " ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]
]
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
loop_comment(46, "work while offline", delivery="d17")
dispatcher.sweep()
comment_bodies = [
    " ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]
]
check(
    "a failed fetch of the clone spawns nothing and reports on the entity",
    (state / "failed" / "d17.json").exists()
    and len(spawns()) == 7
    and len(comment_bodies) == 2
    and "46" in comment_bodies[1]
    and "did not start" in comment_bodies[1]
    and "origin of the serving trunk" in comment_bodies[1],
)
os.environ.pop("DISPATCHER_TEST_GIT_FAIL")

# with origin back, the sweep fetches the clone and the leg runs: the fetch
# and the trunk read it feeds are the last git calls of that pass, and the
# spawn they verified is the one after the guard
loop_comment(47, "work again", delivery="d18")
dispatcher.sweep()
check(
    "a healthy fetch lets the spawn run",
    processed("d18") is not None
    and len(spawns()) == 8
    and git_calls()[-2] == ["fetch", "origin"]
    and git_calls()[-1]
    == ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]
    and spawns()[7]["argv"][2] == "ai/issue-47",
)


# --------------------------------------------------------- spawn pace


# one spawn attempt per sweep pass, and a floor between the passes (issue
# #225): a burst of deliveries must not start a burst of legs. The floor of
# this harness is 0, so each pass above measures the one-attempt rule alone.
# The two checks below hold the rule, then the floor follows through the
# module global, because the knob is read at import time
loop_comment(60, "burst one", delivery="dp-1")
loop_comment(61, "burst two", delivery="dp-2")
burst_before = len(spawns())
dispatcher.sweep()
check(
    "one sweep pass starts one leg of a burst",
    len(spawns()) == burst_before + 1 and len(events()) == 1,
)
dispatcher.sweep()
check(
    "the next pass starts the second leg of the burst",
    len(spawns()) == burst_before + 2 and len(events()) == 0,
)

loop_comment(62, "too soon", delivery="dp-3")
setattr(dispatcher, "SPAWN_SPACING", 60.0)
paced_before = len(spawns())
dispatcher.sweep()
check(
    "a pass inside the spacing of the last start defers the event",
    len(spawns()) == paced_before and len(events()) == 1,
)
pace = dispatcher.load_json(state / "pace.json", {})
pace["last"] = time.time() - 61
dispatcher.store_json(state / "pace.json", pace)
dispatcher.sweep()
check(
    "a pass after the spacing starts the deferred leg",
    len(spawns()) == paced_before + 1 and len(events()) == 0,
)
setattr(dispatcher, "SPAWN_SPACING", 0.0)


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
        "pulls_list": [
            {"index": 100, "head": {"ref": "ai/issue-35"}, "body": "Closes #35"}
        ],
        "pulls": {"100": {"head": {"ref": "ai/issue-35"}}},
    }
)
dispatcher.take_slot("ai/issue-35", "live-session", "", 35)
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
    {"id": 3, "author": "jracon", "body": "/loop more work"}
)
write_scenario(scenario)
dispatcher.poll()
check(
    "the second poll queues and sweeps a nudge leg for a command comment whose branch holds a pull request",
    processed("poll-3") is not None
    and len(spawns()) == 12
    and spawns()[11]["argv"][2] == "ai/issue-35"
    and "pull request 100" in spawns()[11]["argv"][-1]
    and "do not open a second one" in spawns()[11]["argv"][-1],
)

scenario["pulls_list"].append(
    {"index": 102, "head": {"ref": "ai/issue-41"}, "body": "Closes #41"}
)
write_scenario(scenario)
dispatcher.poll()
check(
    "the poll queues and sweeps a reviewer leg for a new ai/ pull request",
    processed("poll-pr-102") is not None
    and len(spawns()) == 13
    and spawns()[12]["argv"][2] == "ai/review-102"
    and "Review pull request 102" in spawns()[12]["argv"][-1],
)
check(
    "every tea call names the repository",
    bool(tea_calls())
    and all("--repo" in call and "jracon/genixis" in call for call in tea_calls()),
)
clear_spool()

# a kept cursor file that predates the pull request comments holds no prc
# map (the second blocking finding of the review of pull request 553): the
# old poll listed the gated issues only, so the widened listing and the new
# comment read would replay the whole comment history once after the
# upgrade. The first poll over such a cursor records a fresh baseline, the
# same rule as a missing cursor file
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues_list"] = [{"index": 35}, {"index": 99}]
scenario["issues"]["99"] = {
    "index": 99,
    "body": ready_body(),
    "comments": [{"id": 9, "author": "jracon", "body": "/loop replay attempt"}],
}
scenario["comments"] = {"100": [{"id": 40, "author": "jracon", "body": "/loop old"}]}
write_scenario(scenario)
dispatcher.store_json(
    state / "poll-cursor.json",
    {"issues": {"35": 1}, "prs": ["100"], "ci": {}},
)
spawns_before = len(spawns())
dispatcher.poll()
cursor = dispatcher.load_json(state / "poll-cursor.json", {})
check(
    "a pre-upgrade cursor records a fresh baseline and queues nothing",
    len(events()) == 0
    and len(spawns()) == spawns_before
    and cursor.get("issues", {}).get("35") == 3
    and cursor.get("issues", {}).get("99") == 9
    and cursor.get("prc", {}).get("100") == 40,
)
dispatcher.poll()
check(
    "the second poll after the upgrade baseline stays quiet",
    len(events()) == 0 and len(spawns()) == spawns_before,
)
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["comments"]["100"].append(
    {"id": 41, "author": "jracon", "body": "/loop new work"}
)
write_scenario(scenario)
dispatcher.poll()
check(
    "a new comment after the upgrade baseline queues its leg",
    queued_event("poll-prc-41").get("kind") == "nudge",
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
    "the unit PATH carries go for the Go gate of a leg",
    "${pkgs.go}/bin" in unit_source,
)
check(
    "no dispatcher unit sets a sandbox option",
    "TemporaryFileSystem" not in unit_source and "PrivateUsers" not in unit_source,
)
check(
    "the units set TMUX_TMPDIR to the runtime directory of the user",
    # a login shell of dev exports TMUX_TMPDIR, but a user unit sources no
    # profile: without this setting every leg opens its view window on the
    # /tmp tmux server, in a second session that no attach of the owner
    # shows (issue #143)
    "TMUX_TMPDIR=%t" in unit_source,
)


# ------------------------------------------------------------- receiver


server = ThreadingHTTPServer(("127.0.0.1", 0), dispatcher.Receiver)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % server.server_address[1]

# no receiver thread of this run may end in the error handler: record
# what the error handler of the server sees, instead of letting it print
# each traceback. The recorder sits before the first request, so the
# check after the dribble case covers every receiver request of the run,
# not only the cut one (issue #280)
receiver_errors: list = []


def record_receiver_error(request, client_address) -> None:
    receiver_errors.append((request, client_address))


server.handle_error = record_receiver_error


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


raw = json.dumps(comment_event(44, "/loop fresh work", labels=[])).encode()
status = post(
    signed_headers("issue_comment", "recv-1", raw) | {"X-Forgejo-Signature": "0" * 64},
    raw,
)
check(
    "a delivery with a wrong signature gets 403", status == 403 and len(events()) == 0
)

status = post(signed_headers("issue_comment", "recv-2", raw), raw)
swept = wait_for(lambda: processed("recv-2") is not None)
check(
    "a signed delivery is accepted and swept",
    status == 200 and swept and len(spawns()) == 14,
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
check(
    "no receiver thread of this run ends in the error handler",
    not receiver_errors,
)


# ------------------------------------------------------------ red gate

# a red gate starts one nudge leg on the open ai/ pull request whose head
# commit carries it, and only while the gate stays red: the second and the
# third red gate show the bound (issue #110). The status payload is the
# shape of the forge family: sha, state, context, repository, sender.


def status_event(state, sha):
    return {
        "sha": sha,
        "state": state,
        "context": "Check CI / gate (pull_request)",
        "repository": {"full_name": REPO},
        "sender": {"login": "jracon"},
    }


def head_scenario(pr, head, sha, ci=None):
    listing = {"index": pr, "head": {"ref": head}}
    if ci is not None:
        listing["ci"] = ci
    write_scenario(
        {
            "issues_list": [],
            "issues": {},
            "pulls_list": [listing],
            "pulls": {str(pr): {"head": {"ref": head}, "headSha": sha}},
        }
    )


head_scenario(200, "ai/issue-77", "deadbee")
dispatcher.handle_payload("status", status_event("failure", "deadbee"), "st-1")
spool = events()
check(
    "a red gate on the head of an open ai/ pull request queues a nudge leg",
    spool.get("st-1.json", {}).get("kind") == "nudge"
    and spool["st-1.json"]["branch"] == "ai/issue-77"
    and spool["st-1.json"]["entity"] == 200
    and "machine gate of the repository is red" in spool["st-1.json"]["cause"],
)

dispatcher.handle_payload("status", status_event("failure", "deadbee"), "st-2")
check(
    "a second failure status of the same commit starts no second leg",
    len([e for e in events().values() if e["branch"] == "ai/issue-77"]) == 1,
)

dispatcher.handle_payload("status", status_event("failure", "cafebabe"), "st-3")
dispatcher.handle_payload("status", status_event("pending", "deadbee"), "st-4")
check(
    "a status without a matching open head, and a pending status, queue nothing",
    len([e for e in events().values() if e["branch"] == "ai/issue-77"]) == 1,
)

dispatcher.sweep()
spawned = spawns()
check(
    "the red-gate nudge leg spawns with the red-gate prompt",
    spawned[-1]["argv"][2] == "ai/issue-77"
    and "machine gate of the repository is red" in spawned[-1]["argv"][-1]
    and "do not open a second one" in spawned[-1]["argv"][-1],
)

# the bound: two red-gate nudge legs per pull request while the gate stays
# red, then one comment that names jracon, and no further leg on its own
dispatcher.release_entity(200)  # the closing comment of the first nudge leg
head_scenario(200, "ai/issue-77", "feedface")
dispatcher.handle_payload("status", status_event("failure", "feedface"), "st-5")
check(
    "the second red gate queues the second nudge leg",
    (events().get("st-5.json") or {}).get("kind") == "nudge",
)
dispatcher.sweep()
head_scenario(200, "ai/issue-77", "badf00d")
dispatcher.handle_payload("status", status_event("failure", "badf00d"), "st-6")
redgate_bodies = [
    " ".join(call[3:])
    for call in tea_calls()
    if call[:2] == ["comments", "add"] and "stayed red" in " ".join(call[3:])
]
check(
    "the third red gate comments on the pull request, names jracon, sets needs-owner, and starts no leg",
    len(redgate_bodies) == 1
    and "200" in redgate_bodies[0]
    and "jracon" in redgate_bodies[0]
    and "st-6.json" not in events()
    and processed("st-6") is None
    and [
        "issues",
        "edit",
        "200",
        "--add-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in tea_calls(),
)

head_scenario(200, "ai/issue-77", "badcafe")
dispatcher.handle_payload("status", status_event("failure", "badcafe"), "st-7")
redgate_bodies = [
    " ".join(call[3:])
    for call in tea_calls()
    if call[:2] == ["comments", "add"] and "stayed red" in " ".join(call[3:])
]
check(
    "a red gate after the escalation stays quiet",
    len(redgate_bodies) == 1 and "st-7.json" not in events(),
)

dispatcher.handle_payload("status", status_event("success", "badcafe"), "st-8")
check(
    "a green gate clears the red episode of the pull request",
    dispatcher.redgate().get("200") is None,
)

# the workflow run delivery: this forge offers no status event on its
# webhook page, so the owner ticks Failure and Success under the workflow
# run events instead (issue #228). The recorded delivery holds the action
# word run_completed and a run object with status and commit_sha, with the
# repository inside the run object and nothing at the top level besides the
# action word. The rule keys on that shape, not on the event header, so it
# fires whatever name the forge gives the event. The run object also names
# the pull request or the branch in prettyref, and the gate mapping
# resolves a delivery that names one from that field (issue #583).


def workflow_run_event(status, sha, repo=REPO, prettyref="#203"):
    return {
        "action": "run_completed",
        "run": {
            "id": 499,
            "workflow_id": "check-commit-subjects.yaml",
            "prettyref": prettyref,
            "commit_sha": sha,
            "event": "pull_request",
            "trigger_event": "pull_request",
            "status": status,
            "repository": {"full_name": repo},
        },
    }


head_scenario(203, "ai/issue-79", "c0ffee")
dispatcher.handle_payload(
    "workflow_run", workflow_run_event("failure", "c0ffee"), "wf-1"
)
spool = events()
check(
    "a failed workflow run on the head of an open ai/ pull request queues a nudge leg",
    spool.get("wf-1.json", {}).get("kind") == "nudge"
    and spool["wf-1.json"]["branch"] == "ai/issue-79"
    and spool["wf-1.json"]["entity"] == 203
    and "machine gate of the repository is red" in spool["wf-1.json"]["cause"],
)

# a second workflow of the same commit fails too: one leg per head commit,
# the sha bound of gate_red
second = workflow_run_event("failure", "c0ffee")
second["run"]["workflow_id"] = "pull-request.yaml"
dispatcher.handle_payload("workflow_run", second, "wf-2")
check(
    "a second failed workflow run of the same commit starts no second leg",
    len([e for e in events().values() if e["branch"] == "ai/issue-79"]) == 1,
)

dispatcher.sweep()
spawned = spawns()
check(
    "the workflow-run nudge leg spawns with the red-gate prompt",
    spawned[-1]["argv"][2] == "ai/issue-79"
    and "machine gate of the repository is red" in spawned[-1]["argv"][-1]
    and "do not open a second one" in spawned[-1]["argv"][-1],
)

dispatcher.release_entity(203)  # the closing comment of the nudge leg
dispatcher.handle_payload("status", status_event("failure", "c0ffee"), "wf-st")
check(
    "a failure status of the commit that the workflow run already reported starts no leg",
    len([e for e in events().values() if e["branch"] == "ai/issue-79"]) == 0,
)

# the rule fires on the payload shape alone: the record of the delivery
# holds the body, not the header name of the event
dispatcher.handle_payload("", workflow_run_event("success", "c0ffee"), "wf-3")
check(
    "a successful workflow run clears the red episode, whatever the event header",
    dispatcher.redgate().get("203") is None and "wf-3.json" not in events(),
)

dispatcher.handle_payload(
    "workflow_run", workflow_run_event("cancelled", "c0ffee"), "wf-4"
)
other_repo = workflow_run_event("failure", "c0ffee", repo="other/repo")
dispatcher.handle_payload("workflow_run", other_repo, "wf-5")
check(
    "a workflow run of a status other than failure and success, and of another repository, queue nothing",
    "wf-4.json" not in events() and "wf-5.json" not in events(),
)

# the recorded delivery itself (issue #228, comment 3997): the body as the
# forge sent it for run 499 of check-commit-subjects.yaml on the head of
# pull request 227, with the identity objects of the record cut to the
# field that the rule reads: the repository object keeps full_name, and the
# trigger_user object and the event_payload string are gone. No other
# field of the record is cut. The registration of the event set is issue
# #236, comment 4240. The case pins the shape of the record against the
# rule, so a delivery that the forge reshaped fails here before it fails
# a leg. The check counts the tea calls of the pass, so the named mapping
# of issue #583 stays pinned to the real shape too: a delivery of a forge
# that dropped prettyref falls back to the sha scan, and its per-pull read
# fails the count.

recorded_delivery = {
    "action": "run_completed",
    "run": {
        "id": 499,
        "title": "feat(project): register the ide follow hook in the session settings",
        "repository": {"full_name": REPO},
        "workflow_id": "check-commit-subjects.yaml",
        "index_in_repo": 496,
        "ScheduleID": 0,
        "prettyref": "#227",
        "is_ref_deleted": False,
        "commit_sha": "c36619637be06b1acf8e69c546d21472dd0f183b",
        "is_fork_pull_request": False,
        "need_approval": False,
        "approved_by": 0,
        "event": "pull_request",
        "trigger_event": "pull_request",
        "status": "failure",
        "started": "2026-11-09T12:13:43-07:00",
        "stopped": "2026-11-09T12:13:45-07:00",
        "created": "2026-11-09T00:59:24-07:00",
        "updated": "2026-11-09T12:13:43-07:00",
        "duration": 4000000000,
        "html_url": "https://forgejo.local.jracon.xyz/jracon/genixis/actions/runs/496",
    },
}

head_scenario(227, "ai/issue-190", "c36619637be06b1acf8e69c546d21472dd0f183b")
recorded_calls = delivery_calls(
    lambda: dispatcher.handle_payload("workflow_run", recorded_delivery, "wf-recorded")
)
spool = events()
check(
    "the recorded delivery of issue 228 queues a nudge leg through its named pull request, with no per-pull sha read",
    spool.get("wf-recorded.json", {}).get("kind") == "nudge"
    and spool["wf-recorded.json"]["branch"] == "ai/issue-190"
    and spool["wf-recorded.json"]["entity"] == 227
    and "machine gate of the repository is red" in spool["wf-recorded.json"]["cause"]
    and dispatcher.redgate().get("227", {}).get("sha")
    == "c36619637be06b1acf8e69c546d21472dd0f183b"
    and len(listing_calls(recorded_calls)) == 1
    and not pull_reads(recorded_calls),
)

# the tea call count of the gate mapping (issue #583): a workflow run
# delivery that names its pull request or its branch resolves through one
# listing of the open pull requests, so one conclusion costs one listing
# call and no per-pull head-sha read, whatever the count of open ai/ pull
# requests is. Before the change, the same delivery paid one head-sha read
# per open ai/ pull request, so the cost of each conclusion grew with the
# activity of the loop itself. The status delivery, whose payload names no
# branch and no pull request, keeps the sha scan.

write_scenario(
    {
        "issues_list": [],
        "issues": {},
        "pulls_list": [
            {"index": 210, "head": {"ref": "ai/issue-210"}},
            {"index": 211, "head": {"ref": "ai/issue-211"}},
            {"index": 212, "head": {"ref": "ai/issue-212"}},
        ],
        "pulls": {
            "210": {"head": {"ref": "ai/issue-210"}, "headSha": "count210"},
            "211": {"head": {"ref": "ai/issue-211"}, "headSha": "count211"},
            "212": {"head": {"ref": "ai/issue-212"}, "headSha": "count212"},
        },
    }
)

red_named = delivery_calls(
    lambda: dispatcher.handle_payload(
        "workflow_run",
        workflow_run_event("failure", "count212", prettyref="#212"),
        "count-red",
    )
)
check(
    "a red delivery that names its pull request costs one listing call and no per-pull read",
    len(listing_calls(red_named)) == 1
    and not pull_reads(red_named)
    and queued_event("count-red").get("entity") == 212,
)

green_named = delivery_calls(
    lambda: dispatcher.handle_payload(
        "workflow_run",
        workflow_run_event("success", "count212", prettyref="#212"),
        "count-green",
    )
)
check(
    "a green delivery that names its pull request costs one listing call and no per-pull read",
    len(listing_calls(green_named)) == 1
    and not pull_reads(green_named)
    and queued_event("count-green") == {},
)

# a run of a branch, not of a pull request: the nightly run of main names
# its branch, and a push to an ai/ branch names the branch too
branch_run = workflow_run_event("failure", "count211", prettyref="ai/issue-211")
branch_run["run"]["event"] = "push"
branch_run["run"]["trigger_event"] = "push"
branch_named = delivery_calls(
    lambda: dispatcher.handle_payload("workflow_run", branch_run, "count-branch")
)
check(
    "a red delivery that names its branch costs one listing call and no per-pull read",
    len(listing_calls(branch_named)) == 1
    and not pull_reads(branch_named)
    and queued_event("count-branch").get("branch") == "ai/issue-211",
)

trunk_run = workflow_run_event("success", "dead000", prettyref="main")
trunk_run["run"]["event"] = "schedule"
trunk_run["run"]["trigger_event"] = "schedule"
trunk_named = delivery_calls(
    lambda: dispatcher.handle_payload("workflow_run", trunk_run, "count-main")
)
check(
    "a delivery of the default branch concludes from the listing alone and queues nothing",
    len(listing_calls(trunk_named)) == 1
    and not pull_reads(trunk_named)
    and queued_event("count-main") == {},
)

status_scan = delivery_calls(
    lambda: dispatcher.handle_payload(
        "status", status_event("failure", "nosuch0"), "count-status"
    )
)
check(
    "a status delivery that names no branch keeps the sha scan of the mapping",
    len(listing_calls(status_scan)) == 1
    and len(pull_reads(status_scan)) == 3
    and queued_event("count-status") == {},
)

# the poll fallback reads the newest CI status of each open ai/ pull request
# and queues the same nudge leg
head_scenario(201, "ai/issue-78", "aaa111", ci="success")
dispatcher.poll()
cursor = dispatcher.load_json(state / "poll-cursor.json", {})
check(
    "the poll registers a new pull request without a red-gate leg",
    "201" in cursor.get("prs", []) and dispatcher.redgate().get("201") is None,
)

head_scenario(201, "ai/issue-78", "bbb222", ci="failure")
dispatcher.poll()
check(
    "the poll queues one red-gate nudge leg for a new red head",
    processed("poll-red-201-bbb222") is not None
    or events().get("poll-red-201-bbb222.json") is not None,
)


# ---------------------------------------------- prompt by branch state

# a comment on a gated issue whose branch holds an open pull request starts
# a leg that works on that pull request: the worker prompt would tell the
# leg to open a second pull request, and the forge refuses that (issue #110)


def branch_pr_scenario(pr, head):
    write_scenario(
        {
            "issues_list": [],
            "issues": {},
            "pulls_list": [{"index": pr, "head": {"ref": head}}],
            "pulls": {str(pr): {"head": {"ref": head}, "headSha": "ddd444"}},
        }
    )


branch_pr_scenario(300, "ai/issue-90")
loop_comment(90, "please continue", delivery="dg-1")
spool = events()
check(
    "a gated comment on a branch with an open pull request queues a nudge leg",
    spool.get("dg-1.json", {}).get("kind") == "nudge"
    and spool["dg-1.json"]["branch"] == "ai/issue-90"
    and spool["dg-1.json"]["entity"] == 300,
)
dispatcher.sweep()
spawned = spawns()
check(
    "the nudge leg of a gated comment opens no second pull request",
    spawned[-1]["argv"][2] == "ai/issue-90"
    and "pull request 300" in spawned[-1]["argv"][-1]
    and "do not open a second one" in spawned[-1]["argv"][-1]
    and "Open the pull request" not in spawned[-1]["argv"][-1],
)

loop_comment(91, "fresh work", delivery="dg-3")
spool = events()
check(
    "a gated comment on a branch with no pull request still queues a worker leg",
    spool.get("dg-3.json", {}).get("kind") == "worker"
    and spool["dg-3.json"]["branch"] == "ai/issue-91",
)


# ------------------------------------------------------- entity payload


# the sweep fetches the entity of a leg at spawn time and renders it into the
# prompt (issue #311): a worker leg carries its issue with its comments; a
# nudge or reviewer leg carries the pull request, its comments, its review
# comments, and the linked issue with its comments. The prompt names the
# payload, what it holds, and the time of the read. A fetch that fails, or a
# payload past the cap, cuts the payload whole and falls back to the prompt
# form that sends the leg to its own read. One sweep pass starts one leg, so
# the section starts from an empty spool and each check queues one event.
# The scenario keeps pulls_list empty, so a gated comment on an issue always
# queues a worker leg here
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "82": {
                "index": 82,
                "title": "Fix the frobnicator",
                "body": "The frobnicator is broken.\n" + ready_body(),
                "comments": [
                    {"id": 1, "author": "jracon", "body": "please fix it"},
                    {"id": 2, "author": AGENT, "body": "an old comment of the agent"},
                ],
            }
        },
        "pulls_list": [],
        "pulls": {
            "400": {
                "index": 400,
                "head": {"ref": "ai/issue-82"},
                "body": "Closes #82",
                "title": "fix(frobnicator): the repair",
            }
        },
        "comments": {
            "400": [
                {"id": 11, "author": "jracon", "body": "a comment on the pull request"}
            ]
        },
        "review_comments": {
            "400": [{"id": 12, "author": "jracon", "body": "a review comment"}]
        },
    }
)

loop_comment(82, "work with the payload", delivery="pay-1")
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "the worker prompt carries the issue payload and the time of the read",
    spawns()[-1]["argv"][2] == "ai/issue-82"
    and "Entity payload, read at 2" in prompt
    and "Fix the frobnicator" in prompt
    and "please fix it" in prompt
    and "an old comment of the agent" in prompt
    and "first entity read of this leg" in prompt
    and "Read the issue and every comment first" not in prompt,
)

dispatcher.handle_payload(
    "pull_request", pr_event("opened", 400, "ai/issue-82", "Closes #82"), "pay-2"
)
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "the reviewer prompt carries the pull request payload with the linked issue",
    spawns()[-1]["argv"][2] == "ai/review-400"
    and "Entity payload, read at 2" in prompt
    and "fix(frobnicator): the repair" in prompt
    and "a comment on the pull request" in prompt
    and "a review comment" in prompt
    and "The frobnicator is broken." in prompt
    and "again immediately before the verdict" in prompt,
)

# the worker of pay-1 ends with its closing comment: the release frees the
# branch for the nudge leg of pay-3
dispatcher.release_entity(82)
dispatcher.handle_payload(
    "issue_comment", comment_event(400, "/loop continue here", is_pr=True), "pay-3"
)
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "the nudge prompt resolves the linked issue from the pull request body",
    spawns()[-1]["argv"][2] == "ai/issue-82"
    and "Entity payload, read at 2" in prompt
    and "The frobnicator is broken." in prompt
    and "do not open a second one" in prompt,
)

scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls"]["401"] = {"index": 401, "head": {"ref": "ai/issue-83"}, "body": ""}
write_scenario(scenario)
dispatcher.handle_payload(
    "issue_comment", comment_event(401, "/loop no link here", is_pr=True), "pay-4"
)
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "a payload without the linked issue keeps that read with the leg",
    spawns()[-1]["argv"][2] == "ai/issue-83"
    and "Entity payload, read at 2" in prompt
    and "The frobnicator is broken." not in prompt
    and "read the issue that the body of the pull request names" in prompt,
)

# the sentence of the empty set (issue #421): the real tea answers a
# comments read of an entity that holds no comment with the human sentence
# and exit 0, not JSON, so the stub answers that shape too. The read treats
# the sentence as the empty list, so the payload stays a payload. The first
# reviewer leg of every factory pull request meets the empty set, because
# the first comment of such a pull request is the verdict of its reviewer
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls"]["402"] = {
    "index": 402,
    "head": {"ref": "ai/issue-82"},
    "body": "Closes #82",
    "title": "fix(frobnicator): the comment-free repair",
}
write_scenario(scenario)
sentence = subprocess.run(
    [
        str(stubs / "tea-stub"),
        "comments",
        "list",
        "402",
        "--output",
        "json",
        "--repo",
        REPO,
    ],
    capture_output=True,
    text=True,
    check=True,
).stdout
check(
    "the stub feeds the sentence of the empty set and the read answers the empty list",
    sentence.strip() == "No comments found"
    and dispatcher.tea_read("comments", "list", "402") == [],
)
dispatcher.handle_payload(
    "pull_request", pr_event("opened", 402, "ai/issue-82", "Closes #82"), "pay-4b"
)
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "the reviewer prompt of a pull request without a comment carries the payload",
    spawns()[-1]["argv"][2] == "ai/review-402"
    and "Entity payload, read at 2" in prompt
    and "the comment-free repair" in prompt
    and "tea comments list 402\n[]" in prompt
    and "carries no entity payload" not in prompt,
)

# issue 84 sits in no scenario, so the payload fetch fails: the prompt falls
# back to the read commands, with one sentence that names the cut, and the
# leg runs
loop_comment(84, "the fetch will fail", delivery="pay-5")
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "a failed payload fetch falls back to the read prompt",
    spawns()[-1]["argv"][2] == "ai/issue-84"
    and "Entity payload, read at" not in prompt
    and "carries no entity payload" in prompt
    and "the fetch at spawn time failed or its answer held no JSON" in prompt
    and "Read the issue and every comment first, with: tea issues 84 --comments"
    in prompt
    and "Work issue 84" in prompt,
)

# the body of issue 85 renders past the cap of 96 KiB, far below the kernel
# cap of 128 KiB on one argument: the payload is cut whole, the note names
# the cap, and the leg runs. The readiness lines sit in front of the filler,
# so the gate passes and the cap cuts the payload alone
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["85"] = {
    "index": 85,
    "title": "A long thread",
    "body": ready_body() + "\n" + "x" * 100000,
    "comments": [],
}
write_scenario(scenario)
loop_comment(85, "too long", delivery="pay-6")
dispatcher.sweep()
prompt = spawns()[-1]["argv"][-1]
check(
    "a payload past the cap falls back to the read prompt and names the cut",
    spawns()[-1]["argv"][2] == "ai/issue-85"
    and "Entity payload, read at" not in prompt
    and "carries no entity payload" in prompt
    and "size cap of 98304 bytes" in prompt
    and "Read the issue and every comment first, with: tea issues 85 --comments"
    in prompt,
)

# ------------------------------------------------- the prompt command


# the prompt of a hand-spawned leg (issue #388): one command prints the brief
# of one role for one entity, with the payload rendered and the read time
# named, and starts no leg. A hand spawner passes the printed text to project
# spawn, so a hand-spawned leg receives the same brief shape as a looped leg.
# The checks hold the counts of the spawn log, the scope log, and the tea
# comment log against the state before the command, and one spawn at the end
# of the section proves the parity with the looped prompt of the same issue
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "86": {
                "index": 86,
                "title": "Print the prompt",
                "body": ready_body(),
                "comments": [{"id": 21, "author": "jracon", "body": "hand spawn this"}],
            }
        },
        "pulls_list": [],
        "pulls": {
            "410": {"index": 410, "head": {"ref": "ai/issue-86"}, "body": "Closes #86"},
        },
        "comments": {
            "410": [{"id": 22, "author": "jracon", "body": "a pull request comment"}]
        },
        "review_comments": {
            "410": [{"id": 23, "author": "jracon", "body": "a review comment"}]
        },
    }
)
spawns_before = len(spawns())
scopes_before = len(scope_calls())
comments_before = len([call for call in tea_calls() if call[:2] == ["comments", "add"]])


def run_prompt(*args: str):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = dispatcher.main(["dispatcher.py", "prompt", *args])
    return code, out.getvalue(), err.getvalue()


def no_stamp(text: str) -> str:
    return re.sub(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", "<time>", text)


code, printed, err = run_prompt("worker", "86")
check(
    "the prompt command prints the worker prompt with the payload at its end",
    code == 0
    and err == ""
    and "Work issue 86" in printed
    and "branch ai/issue-86" in printed
    and "Entity payload, read at 2" in printed
    and "Print the prompt" in printed
    and "hand spawn this" in printed
    and "first entity read of this leg" in printed
    and printed.endswith("End of the entity payload.\n"),
)

code, prompt, _ = run_prompt("nudge", "410")
check(
    "the prompt command prints the nudge prompt of the head branch",
    code == 0
    and "branch ai/issue-86" in prompt
    and "pull request 410" in prompt
    and "do not open a second one" in prompt
    and "a pull request comment" in prompt
    and "Print the prompt" in prompt,
)

code, prompt, _ = run_prompt("reviewer", "410")
check(
    "the prompt command prints the reviewer prompt on the review branch",
    code == 0
    and "branch ai/review-410" in prompt
    and "Review pull request 410" in prompt
    and "a review comment" in prompt
    and "a pull request comment" in prompt
    and "Print the prompt" in prompt,
)
check(
    "the reviewer prompt pulls only when the worktree is behind",
    "git pull --ff-only only when" in prompt,
)

check(
    "the prompt command starts no leg and comments on nothing",
    len(spawns()) == spawns_before
    and len(scope_calls()) == scopes_before
    and len([call for call in tea_calls() if call[:2] == ["comments", "add"]])
    == comments_before
    and len(events()) == 0,
)

code, prompt, err = run_prompt("chef", "86")
check(
    "a role the program does not know prints the usage and exits 2",
    code == 2
    and prompt == ""
    and "serve|run|poll" in err
    and "prompt worker <issue>" in err,
)
code, prompt, err = run_prompt("worker", "abc")
check(
    "an entity that is no number prints the usage and exits 2",
    code == 2 and prompt == "" and "nudge|reviewer" in err,
)

code, prompt, _ = run_prompt("nudge", "499")
check(
    "a pull request read that fails fails the prompt command",
    code == 1 and prompt == "",
)

code, prompt, _ = run_prompt("worker", "499")
check(
    "a failed payload fetch prints the cut prompt, the fallback of the looped path",
    code == 0
    and "carries no entity payload" in prompt
    and "the fetch at spawn time failed or its answer held no JSON" in prompt
    and "tea issues 499 --comments" in prompt,
)

# the parity claim of the issue: the printed prompt of a worker leg equals the
# prompt of a looped leg on the same issue, beside the read time of the
# payload, which the two reads stamp on their own
loop_comment(86, "spawn the same brief", delivery="prnt-1")
dispatcher.sweep()
check(
    "the printed worker prompt equals the spawned prompt beside the read time",
    spawns()[-1]["argv"][2] == "ai/issue-86"
    and no_stamp(spawns()[-1]["argv"][-1]) == no_stamp(printed),
)


# ------------------------------------------------------ readiness gate


# the gate of the worker path (issue #356, L2): an issue whose brief answers
# no class, seeds a line with an empty answer, or holds a not-applicable
# without its answerer, is parked with one comment that names the classes and
# the blocked step, and no event is queued. A ready body queues the worker
# leg through the same path
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "110": {"index": 110, "body": "## Problem\nThe frobnicator is broken.\n"},
            "111": {
                "index": 111,
                "body": (
                    "Readiness A: the reference is main.\n"
                    "Readiness B: the gate of the repository is the oracle.\n"
                    "Readiness C: not applicable\n"
                    "Readiness D: no materials, decided by jracon\n"
                    "Readiness E: the build rules of the repository hold.\n"
                    "Readiness F: the factory skill holds the loop contract.\n"
                ),
            },
            "112": {"index": 112, "body": ready_body()},
            # the body of issue 406 (issue #409): the empty C line sits in
            # front of the filled D line, and the seeded section of issue 114
            # holds six empty lines, the shape that the filing rule of the
            # factory skill writes
            "113": {
                "index": 113,
                "body": (
                    "Readiness A: the reference is main.\n"
                    "Readiness B: the gate of the repository is the oracle.\n"
                    "Readiness C:\n"
                    "Readiness D: no materials, decided by jracon\n"
                    "Readiness E: the build rules of the repository hold.\n"
                    "Readiness F: the factory skill holds the loop contract.\n"
                ),
            },
            "114": {
                "index": 114,
                "body": (
                    "## Readiness\n"
                    "\n"
                    "Readiness A:\n"
                    "Readiness B:\n"
                    "Readiness C:\n"
                    "Readiness D:\n"
                    "Readiness E:\n"
                    "Readiness F:\n"
                ),
            },
            # the C and F lines of the body of issue 563 (issue #566) hold
            # the word seeded as their whole answer: the second reading of
            # the filing rule, which the gate now reads as no answer
            "115": {
                "index": 115,
                "body": (
                    "Readiness A: the reference is main.\n"
                    "Readiness B: the gate of the repository is the oracle.\n"
                    "Readiness C: seeded\n"
                    "Readiness D: no materials, decided by jracon\n"
                    "Readiness E: the build rules of the repository hold.\n"
                    "Readiness F: seeded\n"
                ),
            },
        },
        "pulls_list": [],
        "pulls": {},
    }
)


def park_comments():
    return [
        " ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]
    ]


loop_comment(110, "work it", delivery="rdy-1")
check(
    "an issue without readiness lines is parked and queues no leg",
    len(events()) == 0 and len(park_comments()) == 4,
)
check(
    "the park comment names the missing classes and the blocked step",
    "110" in park_comments()[-1]
    and "A (reference and product)" in park_comments()[-1]
    and "F (loop contract)" in park_comments()[-1]
    and "Question" in park_comments()[-1]
    and "blocked step" in park_comments()[-1],
)

loop_comment(111, "work it", delivery="rdy-2")
check(
    "a not-applicable without an answerer parks the issue with the reason",
    len(events()) == 0
    and len(park_comments()) == 5
    and "C (basis)" in park_comments()[-1]
    and "names no answerer" in park_comments()[-1],
)

loop_comment(112, "work it", delivery="rdy-3")
spool = events()
check(
    "a ready issue queues the worker leg",
    spool.get("rdy-3.json", {}).get("kind") == "worker"
    and spool["rdy-3.json"]["branch"] == "ai/issue-112",
)

# the line-stop rule of the pattern (issue #409): a match never reaches into
# the line below, so an empty Readiness line counts as its own unanswered
# class. The direct bodies repeat the scenario entries of issues 113 to 115,
# so the checks bind to the pattern and the report also when the scenario
# entry changes
empty_line_body = (
    "Readiness A: the reference is main.\n"
    "Readiness B: the gate of the repository is the oracle.\n"
    "Readiness C:\n"
    "Readiness D: no materials, decided by jracon\n"
    "Readiness E: the build rules of the repository hold.\n"
    "Readiness F: the factory skill holds the loop contract.\n"
)
missing, anonymous = dispatcher.readiness_report(empty_line_body)
check(
    "an empty readiness line counts as its own unanswered class",
    missing == ["c"] and anonymous == [],
)
captured = {
    letter.lower(): value
    for letter, value in dispatcher.READINESS_LINE.findall(empty_line_body)
}
check(
    "a filled readiness line captures no text of the line below",
    captured
    == {
        "a": "the reference is main.",
        "b": "the gate of the repository is the oracle.",
        "d": "no materials, decided by jracon",
        "e": "the build rules of the repository hold.",
        "f": "the factory skill holds the loop contract.",
    },
)
seeded_body = (
    "## Readiness\n"
    "\n"
    "Readiness A:\n"
    "Readiness B:\n"
    "Readiness C:\n"
    "Readiness D:\n"
    "Readiness E:\n"
    "Readiness F:\n"
)
missing, anonymous = dispatcher.readiness_report(seeded_body)
check(
    "a seeded section of six empty lines reports all six classes missing",
    missing == ["a", "b", "c", "d", "e", "f"] and anonymous == [],
)
check(
    "no class of a seeded section holds a value",
    dispatcher.READINESS_LINE.findall(seeded_body) == [],
)

# the seeded word as the whole answer (issue #566): the body of issue 563
# held two lines with the word alone, and the gate counted both classes as
# answered. The word names the seeded empty line of the protocol, so its
# line reads as no answer, beside the empty-line rule of issue #409, and
# the gate still reads no other content of an answer
seeded_word_body = (
    "Readiness A: the reference is main.\n"
    "Readiness B: the gate of the repository is the oracle.\n"
    "Readiness C: seeded\n"
    "Readiness D: no materials, decided by jracon\n"
    "Readiness E: the build rules of the repository hold.\n"
    "Readiness F: seeded\n"
)
missing, anonymous = dispatcher.readiness_report(seeded_word_body)
check(
    "a whole answer of the word seeded counts as its own unanswered class",
    missing == ["c", "f"] and anonymous == [],
)
missing, anonymous = dispatcher.readiness_report(
    "Readiness C: seeded, the owner fills this class later\n"
)
check(
    "the word seeded inside a longer answer keeps the class answered",
    missing == ["a", "b", "d", "e", "f"] and anonymous == [],
)

parks = len(park_comments())
loop_comment(113, "work it", delivery="rdy-5")
check(
    "a park on an empty line names the empty class, not the line below",
    events().get("rdy-5.json") is None
    and len(park_comments()) == parks + 1
    and "113" in park_comments()[-1]
    and "C (basis)" in park_comments()[-1]
    and "D (materials)" not in park_comments()[-1],
)

# the wording of the finding of a missing class (issue #404): the seeded
# empty line sits in the body, so the finding names the absent answer and
# makes no claim of a missing Readiness line
check(
    "the park comment of an empty seeded line asks for the answer, not the line",
    "no Readiness answer in the body of this issue" in park_comments()[-1]
    and "no Readiness line" not in park_comments()[-1],
)

loop_comment(114, "work it", delivery="rdy-6")
check(
    "a park on a seeded section names all six classes",
    events().get("rdy-6.json") is None
    and len(park_comments()) == parks + 2
    and "114" in park_comments()[-1]
    and all(f"{letter.upper()} (" in park_comments()[-1] for letter in "abcdef"),
)

loop_comment(115, "work it", delivery="rdy-7")
check(
    "a park on a seeded word names the class, like a park on an empty line",
    events().get("rdy-7.json") is None
    and len(park_comments()) == parks + 3
    and "115" in park_comments()[-1]
    and "C (basis)" in park_comments()[-1]
    and "F (loop contract)" in park_comments()[-1],
)

# the Refs keyword of a composition flow records the link the same way as a
# closing keyword (issue #356, L7): the forge closes the issue only on a
# closing keyword, but links.json and the payload of the reviewer leg resolve
# the number either way
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls_list"] = [{"index": 120, "head": {"ref": "ai/issue-112"}}]
scenario["pulls"]["120"] = {"head": {"ref": "ai/issue-112"}, "headSha": "eee555"}
write_scenario(scenario)
dispatcher.handle_payload(
    "pull_request", pr_event("opened", 120, "ai/issue-112", "Refs #112"), "rdy-4"
)
spool = events()
check(
    "a Refs keyword records the link for the payload of the reviewer leg",
    spool.get("rdy-4.json", {}).get("kind") == "reviewer"
    and spool["rdy-4.json"]["issue"] == 112
    and dispatcher.load_json(state / "links.json", {}).get("120") == 112,
)


# ---------------------------------------------------- the windowed route


# the watch command of the watched leg (issue #470, option C; the split
# into its own command is issue #525): the first word of the comment starts
# a watched leg. The harness gates each edit of a settings file above the
# allow rules, and a plain leg gets a denial for the edit, so the spawn of
# the command waits at each prompt and the owner answers them in the view
# window. The prompt of the command also rules the park (issue #505): the
# leg asks its park question in the session, posts no park comment while it
# waits, and falls back to the park comment when the session ends with no
# answer. The spawn keeps every headless property: the envelope, the session
# id, and the markers that keep the forge hook strict. The plain /loop
# command stays a plain leg, and the word window behind it is prose since
# the split
clear_spool()
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["130"] = {"index": 130, "body": ready_body(), "comments": []}
scenario["issues"]["131"] = {"index": 131, "body": ready_body(), "comments": []}
scenario["pulls_list"] = []
scenario["pulls"] = {}
write_scenario(scenario)

dispatcher.handle_payload(
    "issue_comment",
    comment_event(130, "/watch\n\nthe allowlist entry of the gate", labels=[]),
    "win-1",
)
spool = events()
check(
    "a /watch comment queues a windowed worker leg",
    spool.get("win-1.json", {}).get("kind") == "worker"
    and spool["win-1.json"]["branch"] == "ai/issue-130"
    and spool["win-1.json"].get("windowed") is True,
)
dispatcher.sweep()
spawned = spawns()[-1]
check(
    "the windowed worker keeps the headless shape and waits at its prompts",
    spawned["argv"][2] == "ai/issue-130"
    and "--headless" in spawned["argv"]
    and spawned["argv"][spawned["argv"].index("--permission-mode") + 1] == "default"
    and "wait for the answer of the person" in spawned["argv"][-1]
    and "comment on the issue that you are blocked" in spawned["argv"][-1],
)
check(
    "the windowed worker asks its park question in the session",
    "ask your question in this session" in spawned["argv"][-1]
    and "Post no park comment on the issue while you wait" in spawned["argv"][-1]
    and "The typed answer continues this leg on the same branch" in spawned["argv"][-1]
    and "The park comment holds the three parts of the park discipline"
    in spawned["argv"][-1]
    and "post the park comment on the issue" in spawned["argv"][-1],
)

dispatcher.release_entity(130)  # the closing comment of the windowed worker
dispatcher.handle_payload(
    "issue_comment", comment_event(130, "/loop window is prose now", labels=[]), "win-2"
)
check(
    "the word window behind the loop command is prose, and the leg stays plain",
    (events().get("win-2.json") or {}).get("kind") == "worker"
    and (events().get("win-2.json") or {}).get("windowed") is False,
)
clear_spool()

dispatcher.handle_payload(
    "issue_comment", comment_event(131, "/loop go", labels=[]), "win-3"
)
dispatcher.sweep()
spawned = spawns()[-1]
check(
    "a plain loop command keeps the denying mode and the plain stop rule",
    spawned["argv"][2] == "ai/issue-131"
    and spawned["argv"][spawned["argv"].index("--permission-mode") + 1] == "dontAsk"
    and "wait for the answer of the person" not in spawned["argv"][-1]
    and "comment on the issue that you are blocked" in spawned["argv"][-1]
    and "ask your question in this session" not in spawned["argv"][-1]
    and "Post no park comment" not in spawned["argv"][-1],
)

# the variant follows the issue into the nudge path: the allowlist work can
# continue on the branch of the pull request of the issue, watched
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls_list"] = [{"index": 140, "head": {"ref": "ai/issue-130"}}]
scenario["pulls"]["140"] = {
    "index": 140,
    "head": {"ref": "ai/issue-130"},
    "headSha": "fff000",
}
write_scenario(scenario)
dispatcher.handle_payload(
    "issue_comment", comment_event(130, "/watch", labels=[]), "win-4"
)
spool = events()
check(
    "a /watch comment on a branch with a pull request queues a windowed nudge",
    spool.get("win-4.json", {}).get("kind") == "nudge"
    and spool["win-4.json"]["branch"] == "ai/issue-130"
    and spool["win-4.json"].get("windowed") is True,
)
dispatcher.sweep()
spawned = spawns()[-1]
check(
    "the windowed nudge keeps the pull request rule and waits at its prompts",
    spawned["argv"][2] == "ai/issue-130"
    and spawned["argv"][spawned["argv"].index("--permission-mode") + 1] == "default"
    and "do not open a second one" in spawned["argv"][-1]
    and "comment on the pull request that you are blocked" in spawned["argv"][-1]
    and "Post no park comment on the pull request while you wait"
    in spawned["argv"][-1],
)

# the pull request is the second surface of the command (issue #516): the
# answer of comment 6318 on pull request 514 asked for a watched leg and
# started a plain one, because the receiver of a pull request comment read no
# word of the body. A /watch comment on the pull request now starts the
# windowed nudge, and the word window behind a plain loop comment keeps it
# plain
dispatcher.release_entity(140)  # the closing comment of the win-4 windowed nudge
dispatcher.handle_payload(
    "issue_comment", comment_event(140, "/watch", is_pr=True), "win-5"
)
spool = events()
check(
    "a /watch comment on a pull request queues a windowed nudge",
    spool.get("win-5.json", {}).get("kind") == "nudge"
    and spool["win-5.json"]["branch"] == "ai/issue-130"
    and spool["win-5.json"]["entity"] == 140
    and spool["win-5.json"].get("windowed") is True,
)
dispatcher.sweep()
spawned = spawns()[-1]
check(
    "the windowed nudge of a pull request comment waits at its prompts",
    spawned["argv"][2] == "ai/issue-130"
    and spawned["argv"][spawned["argv"].index("--permission-mode") + 1] == "default"
    and "wait for the answer of the person" in spawned["argv"][-1]
    and "do not open a second one" in spawned["argv"][-1]
    and "Post no park comment on the pull request while you wait"
    in spawned["argv"][-1],
)
dispatcher.release_entity(140)  # the closing comment of the win-5 windowed nudge
dispatcher.handle_payload(
    "issue_comment",
    comment_event(140, "/loop window is prose now", is_pr=True),
    "win-6",
)
check(
    "the word window behind a plain loop comment keeps the pull request nudge plain",
    (events().get("win-6.json") or {}).get("kind") == "nudge"
    and (events().get("win-6.json") or {}).get("windowed") is False,
)
clear_spool()

# the poll fallback reads the variant from the comment body, so the webhook
# path and the poll path queue the same watched leg
dispatcher.release_entity(130)  # entity 130 holds no entry: its worker ended above
dispatcher.release_entity(131)  # the closing comment of the plain worker
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues_list"] = [{"index": 131}]
scenario["pulls_list"] = []
scenario["pulls"] = {}
scenario["issues"]["131"]["comments"] = [
    {"id": 9, "author": "jracon", "body": "/watch"}
]
write_scenario(scenario)
dispatcher.poll()
spawned = spawns()[-1]
check(
    "the poll queues the windowed leg from the watch command of the comment",
    spawned["argv"][2] == "ai/issue-131"
    and spawned["argv"][spawned["argv"].index("--permission-mode") + 1] == "default"
    and processed("poll-9") is not None,
)

# the hand spawner prints the same brief: the prompt command takes the
# watch word, and only the worker role takes it
code, printed, err = run_prompt("worker", "131", "watch")
check(
    "the prompt command prints the windowed worker brief",
    code == 0
    and err == ""
    and "wait for the answer of the person" in printed
    and "ask your question in this session" in printed
    and "Post no park comment on the issue while you wait" in printed,
)
check(
    "the printed windowed brief equals the spawned one beside the read time",
    no_stamp(printed) == no_stamp(spawned["argv"][-1]),
)
code, prompt, err = run_prompt("worker", "131", "watched")
check(
    "a word the program does not know prints the usage and exits 2",
    code == 2 and prompt == "" and "[watch]" in err,
)
code, prompt, err = run_prompt("reviewer", "140", "watch")
check(
    "the reviewer role takes no watched variant",
    code == 2 and prompt == "" and "[watch]" in err,
)


# ---------------------------------------------------- the session resume


# the continuation legs of a branch resume the recorded session of the
# branch (issue #524): the envelope of every spawn records the transcript
# uuid of its session in sessions.json, the record survives the release of
# the in-flight entry, and the next worker or nudge spawn on the branch
# passes --resume with that uuid beside the resumed brief. A reviewer
# spawn, a windowed spawn, and a record without a live transcript resume
# nothing: that leg starts fresh with the full brief
clear_spool()
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["150"] = {"index": 150, "body": ready_body(), "comments": []}
scenario["issues"]["151"] = {"index": 151, "body": ready_body(), "comments": []}
scenario["pulls_list"] = []
scenario["pulls"] = {}
write_scenario(scenario)

# the transcripts of the stub sessions: the stub worktree is /nowhere, so a
# transcript sits under the munged name of that path in the home of the
# harness, the same rule the dispatcher reads
transcript_dir = home / ".claude" / "projects" / "-nowhere"
transcript_dir.mkdir(parents=True, exist_ok=True)


def write_transcript(uuid):
    (transcript_dir / (uuid + ".jsonl")).write_text("{}\n", encoding="utf-8")


loop_comment(150, "the first leg", delivery="res-1")
dispatcher.sweep()
first = spawns()[-1]
check(
    "a spawned worker records the transcript uuid of its branch",
    "--resume" not in first["argv"]
    and dispatcher.branch_sessions().get("ai/issue-150")
    == {"uuid": "uuid-ai-issue-150", "windowed": False, "worktree": "/nowhere"},
)

# the final comment of the leg releases the in-flight entry, and the record
# survives the release: a later leg of the branch still finds the session
dispatcher.release_entity(150)
check(
    "the session record survives the release of the in-flight entry",
    "ai/issue-150" not in dispatcher.inflight()
    and dispatcher.branch_sessions().get("ai/issue-150", {}).get("uuid")
    == "uuid-ai-issue-150",
)

# a transcript the cleanup removed answers no resume: the next worker leg
# starts fresh, with the full brief and no sentence of a resumed leg
loop_comment(150, "the transcript is gone", delivery="res-2")
dispatcher.sweep()
fresh = spawns()[-1]
check(
    "a resume on a missing transcript starts a fresh leg with the full brief",
    fresh["argv"][2] == "ai/issue-150"
    and "--resume" not in fresh["argv"]
    and "resumes the recorded session" not in fresh["argv"][-1]
    and "first entity read of this leg" in fresh["argv"][-1],
)
dispatcher.release_entity(150)

# with the transcript on disk, the next worker leg of the branch resumes
write_transcript("uuid-ai-issue-150")
loop_comment(150, "the second leg", delivery="res-3")
dispatcher.sweep()
resumed = spawns()[-1]
check(
    "a worker leg of a branch with a live transcript resumes the session",
    resumed["argv"][2] == "ai/issue-150"
    and resumed["argv"][resumed["argv"].index("--resume") + 1] == "uuid-ai-issue-150"
    and "resumes the recorded session" in resumed["argv"][-1]
    and "comments of the issue" in resumed["argv"][-1]
    and "denial history" in resumed["argv"][-1]
    and "permission rules may have changed" in resumed["argv"][-1],
)
stops_before = [call for call in claude_calls() if call[:1] == ["stop"]]
dispatcher.release_entity(150)
check(
    "the release of a resumed leg stops the session of the latest envelope",
    [call for call in claude_calls() if call[:1] == ["stop"]]
    == stops_before + [["stop", "sid-ai/issue-150"]],
)

# the nudge leg of the branch resumes with it and names the cause as the
# delta since the prior leg
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls_list"] = [{"index": 160, "head": {"ref": "ai/issue-150"}}]
scenario["pulls"]["160"] = {
    "index": 160,
    "head": {"ref": "ai/issue-150"},
    "headSha": "abc123",
    "body": "Closes #150",
}
write_scenario(scenario)
loop_comment(150, "more work through the pull request", delivery="res-4")
dispatcher.sweep()
nudge = spawns()[-1]
check(
    "a nudge leg of the branch resumes the session and names the cause",
    nudge["argv"][2] == "ai/issue-150"
    and nudge["argv"][nudge["argv"].index("--resume") + 1] == "uuid-ai-issue-150"
    and "cause above" in nudge["argv"][-1]
    and "do not open a second one" in nudge["argv"][-1],
)
dispatcher.release_entity(160)

# a reviewer leg never resumes, and the record of its own branch changes
# nothing: the reviewer reads independently
dispatcher.handle_payload(
    "pull_request", pr_event("synchronized", 160, "ai/issue-150"), "res-5"
)
dispatcher.sweep()
check(
    "a reviewer spawn takes no resume flag",
    spawns()[-1]["argv"][2] == "ai/review-160"
    and "--resume" not in spawns()[-1]["argv"],
)
dispatcher.release_entity(160)  # the verdict comment
write_transcript("uuid-ai-review-160")  # the record of the review branch is live
dispatcher.handle_payload(
    "pull_request", pr_event("synchronized", 160, "ai/issue-150"), "res-6"
)
dispatcher.sweep()
check(
    "a second reviewer spawn resumes nothing, live record or not",
    spawns()[-1]["argv"][2] == "ai/review-160"
    and "--resume" not in spawns()[-1]["argv"],
)
dispatcher.release_entity(160)

# a windowed leg never resumes, whatever the record holds, and its own
# record keeps the next plain leg fresh: a resumed session keeps its launch
# flags, so the waiting mode of a windowed leg may hang a plain leg that
# nobody watches
loop_comment(151, "a plain first leg", delivery="res-7")
dispatcher.sweep()
check(
    "the plain leg of issue 151 records its session",
    dispatcher.branch_sessions().get("ai/issue-151", {}).get("uuid")
    == "uuid-ai-issue-151",
)
dispatcher.release_entity(151)
write_transcript("uuid-ai-issue-151")
dispatcher.handle_payload(
    "issue_comment", comment_event(151, "/watch", labels=[]), "res-8"
)
dispatcher.sweep()
check(
    "a windowed leg takes no resume flag",
    spawns()[-1]["argv"][2] == "ai/issue-151"
    and "--resume" not in spawns()[-1]["argv"],
)
dispatcher.release_entity(151)
loop_comment(151, "a plain leg after a windowed one", delivery="res-9")
dispatcher.sweep()
plain = spawns()[-1]
check(
    "the record of a windowed leg keeps the next plain leg fresh",
    plain["argv"][2] == "ai/issue-151"
    and "--resume" not in plain["argv"]
    and "resumes the recorded session" not in plain["argv"][-1],
)
dispatcher.release_entity(151)


# ------------------------------------------------------------- the wake


# the wake command of the loop (issue #525): the first word of the final
# comment of a leg, the comment that releases the in-flight entries of its
# entity. A released reviewer branch wakes the worker nudge of the same
# pull request; a released worker or nudge branch wakes the issue that the
# Refs keyword of the branch's open pull request names. One wake per
# comment, at most two per entity pair until a human act resets, and the
# trip sets the needs-owner label beside the comment that names the owner
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "80": {"index": 80, "body": ready_body()},
            "95": {"index": 95, "body": ready_body()},
        },
        "pulls_list": [{"index": 210, "head": {"ref": "ai/issue-80"}}],
        "pulls": {
            "210": {"head": {"ref": "ai/issue-80"}, "body": "Closes #80"},
        },
    }
)
dispatcher.take_slot("ai/review-210", "s-210", "sid-210", 210)
dispatcher.handle_payload(
    "issue_comment",
    comment_event(
        210,
        "/wake\n\nissue (blocking): The gate did not run.",
        sender=AGENT,
        is_pr=True,
    ),
    "wk-1",
)
spool = events()
check(
    "a reviewer verdict with /wake queues the worker nudge of the pull request",
    spool.get("wk-1.json", {}).get("kind") == "nudge"
    and spool["wk-1.json"]["branch"] == "ai/issue-80"
    and spool["wk-1.json"]["entity"] == 210
    and "reviewer verdict on pull request 210" in spool["wk-1.json"]["cause"],
)
check(
    "the verdict wake releases the reviewer entry and spends one wake of the pair",
    "ai/review-210" not in dispatcher.inflight()
    and ["stop", "sid-210"] in claude_calls()
    and dispatcher.wakegate().get("210-210", {}).get("wakes") == 1,
)
dispatcher.sweep()
check(
    "the woken nudge leg spawns with the verdict cause",
    spawns()[-1]["argv"][2] == "ai/issue-80"
    and "reviewer verdict on pull request 210" in spawns()[-1]["argv"][-1]
    and "do not open a second one" in spawns()[-1]["argv"][-1],
)

# an agent comment on an entity with no in-flight entry is a mid-run or a
# stray comment: it releases nothing, so it wakes nothing, whatever its
# first word is, and a confused leg cannot summon work while it runs
# (issue #525, acceptance criterion 2)
dispatcher.handle_payload(
    "issue_comment", comment_event(88, "/wake the findings stand", sender=AGENT), "wk-2"
)
check(
    "an agent comment that releases no entry wakes nothing",
    "wk-2.json" not in events()
    and not any(
        "no wake target" in " ".join(call[3:])
        for call in tea_calls()
        if call[:2] == ["comments", "add"]
    ),
)

# the bound: the second wake of the pair queues the second nudge, the third
# comments on the pull request, names jracon, sets needs-owner, and starts
# no leg, and the fourth stays quiet
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "done", sender=AGENT, is_pr=True), "wk-3"
)
dispatcher.take_slot("ai/review-210", "s-210b", "sid-210b", 210)
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "/wake", sender=AGENT, is_pr=True), "wk-4"
)
check(
    "the second wake of the pair queues the second nudge",
    (events().get("wk-4.json") or {}).get("kind") == "nudge"
    and dispatcher.wakegate().get("210-210", {}).get("wakes") == 2,
)
dispatcher.sweep()
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "done", sender=AGENT, is_pr=True), "wk-5"
)
dispatcher.take_slot("ai/review-210", "s-210c", "sid-210c", 210)
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "/wake", sender=AGENT, is_pr=True), "wk-6"
)
wake_bound_bodies = [
    " ".join(call[3:])
    for call in tea_calls()
    if call[:2] == ["comments", "add"] and "passed its bound" in " ".join(call[3:])
]
check(
    "the third wake past the bound comments, names jracon, sets needs-owner, and starts no leg",
    "wk-6.json" not in events()
    and len(wake_bound_bodies) == 1
    and "210" in wake_bound_bodies[0]
    and "jracon" in wake_bound_bodies[0]
    and [
        "issues",
        "edit",
        "210",
        "--add-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in tea_calls(),
)
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "done", sender=AGENT, is_pr=True), "wk-6b"
)
dispatcher.take_slot("ai/review-210", "s-210d", "sid-210d", 210)
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "/wake", sender=AGENT, is_pr=True), "wk-6c"
)
check(
    "a wake after the escalation stays quiet",
    "wk-6c.json" not in events()
    and len(
        [
            call
            for call in tea_calls()
            if call[:2] == ["comments", "add"]
            and "passed its bound" in " ".join(call[3:])
        ]
    )
    == 1,
)

# the reset: a human comment on either entity of the pair clears the bound
# and removes the label, so the next wake gets a fresh bound
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "I looked at it, go on", is_pr=True), "wk-7"
)
check(
    "a human comment on the entity clears the wake bound and removes the label",
    dispatcher.wakegate().get("210-210") is None
    and [
        "issues",
        "edit",
        "210",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in tea_calls(),
)
# the human comment queued a nudge leg of its own: drain it before the next
# wake, so the pending event supersede rule keeps out of this check
dispatcher.sweep()
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "done", sender=AGENT, is_pr=True), "wk-7b"
)
dispatcher.take_slot("ai/review-210", "s-210e", "sid-210e", 210)
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "/wake", sender=AGENT, is_pr=True), "wk-8"
)
check(
    "the wake after the reset gets a fresh bound",
    (events().get("wk-8.json") or {}).get("kind") == "nudge"
    and dispatcher.wakegate().get("210-210", {}).get("wakes") == 1,
)
dispatcher.sweep()
dispatcher.handle_payload(
    "issue_comment", comment_event(210, "done", sender=AGENT, is_pr=True), "wk-8b"
)

# the composition handoff: the final comment of a worker or nudge branch
# wakes the issue that the Refs keyword of the branch's open pull request
# names, through the branch-state rule of a human comment on an issue, so
# the readiness gate runs for the woken worker
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["91"] = {"index": 91, "body": "## Problem\nNo readiness lines.\n"}
scenario["pulls_list"] = [
    {"index": 211, "head": {"ref": "ai/issue-81"}},
    {"index": 212, "head": {"ref": "ai/issue-84"}},
    {"index": 213, "head": {"ref": "ai/issue-85"}},
]
scenario["pulls"]["211"] = {"head": {"ref": "ai/issue-81"}, "body": "Refs #95"}
scenario["pulls"]["212"] = {"head": {"ref": "ai/issue-84"}, "body": "Closes #84"}
scenario["pulls"]["213"] = {"head": {"ref": "ai/issue-85"}, "body": "Refs #91"}
write_scenario(scenario)
clear_spool()

dispatcher.take_slot("ai/issue-81", "s-81", "sid-81", 81)
dispatcher.handle_payload(
    "issue_comment", comment_event(81, "/wake", sender=AGENT), "wk-9"
)
spool = events()
check(
    "a worker final comment wakes the Refs issue of its branch",
    spool.get("wk-9.json", {}).get("kind") == "worker"
    and spool["wk-9.json"]["branch"] == "ai/issue-95"
    and spool["wk-9.json"]["entity"] == 95
    and spool["wk-9.json"]["reason"] == "wake of a composition handoff"
    and dispatcher.wakegate().get("81-95", {}).get("wakes") == 1,
)
dispatcher.sweep()
check(
    "the woken worker leg spawns on the Refs issue",
    spawns()[-1]["argv"][2] == "ai/issue-95"
    and "Work issue 95" in spawns()[-1]["argv"][-1],
)
dispatcher.handle_payload(
    "issue_comment", comment_event(95, "done", sender=AGENT), "wk-9b"
)

# a closing keyword names the work of the same branch, so it wakes nothing
dispatcher.take_slot("ai/issue-84", "s-84", "sid-84", 84)
dispatcher.handle_payload(
    "issue_comment", comment_event(84, "/wake", sender=AGENT), "wk-10"
)
check(
    "a closing keyword in the pull request body wakes nothing",
    "wk-10.json" not in events()
    and any(
        "no wake target derives" in " ".join(call[3:])
        and "no issue with a Refs keyword" in " ".join(call[3:])
        for call in tea_calls()
        if call[:2] == ["comments", "add"]
    ),
)

# an unready target parks through the readiness gate and counts no wake
dispatcher.take_slot("ai/issue-85", "s-85", "sid-85", 85)
dispatcher.handle_payload(
    "issue_comment", comment_event(85, "/wake", sender=AGENT), "wk-11"
)
check(
    "a wake on an unready issue parks it and counts no wake",
    events().get("wk-11.json") is None
    and any(
        "parked" in " ".join(call[3:])
        for call in tea_calls()
        if call[:2] == ["comments", "add"]
    )
    and dispatcher.wakegate().get("85-91") is None,
)

# a wake on a branch without an open pull request has no target
dispatcher.take_slot("ai/issue-86", "s-86", "sid-86", 86)
dispatcher.handle_payload(
    "issue_comment", comment_event(86, "/wake", sender=AGENT), "wk-12"
)
check(
    "a wake on a branch without an open pull request comments and wakes nothing",
    "wk-12.json" not in events()
    and any(
        "no wake target derives" in " ".join(call[3:])
        and "no open pull request" in " ".join(call[3:])
        for call in tea_calls()
        if call[:2] == ["comments", "add"]
    ),
)

# the poll fallback parses the same grammar of the final comment, so the
# webhook path and the poll path wake the same legs
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues_list"] = [{"index": 92}]
scenario["issues"]["92"] = {
    "index": 92,
    "body": ready_body(),
    "comments": [{"id": 5, "author": AGENT, "body": "/wake"}],
}
scenario["issues"]["93"] = {"index": 93, "body": ready_body()}
scenario["pulls_list"] = [{"index": 214, "head": {"ref": "ai/issue-92"}}]
scenario["pulls"]["214"] = {"head": {"ref": "ai/issue-92"}, "body": "Refs #93"}
write_scenario(scenario)
clear_spool()
dispatcher.take_slot("ai/issue-92", "s-92", "sid-92", 92)
dispatcher.poll()
poll5 = queued_event("poll-5")
check(
    "the poll parses the wake word of a final comment and wakes the Refs issue",
    poll5.get("kind") == "worker" and poll5.get("branch") == "ai/issue-93",
)

# ------------------------------------------- commands and the held threads


# the human surface of the loop after issue #525: commands only. A plain
# comment starts nothing, on an issue and on a pull request, with one
# exception: the needs-owner label marks a thread that the loop stopped, and
# the plain prose of a person continues it. The same comment resets the
# wake bound and removes the label, and the label write of the reset runs
# only when the entity holds the label (issue #582): the delivery and the
# poll listing carry the state, so a comment on an entity that never
# stopped costs no label write
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "96": {"index": 96, "body": ready_body()},
            "97": {"index": 97, "body": ready_body()},
        },
        "pulls_list": [],
        "pulls": {},
    }
)
write_calls = delivery_calls(
    lambda: dispatcher.handle_payload(
        "issue_comment", comment_event(97, "a plain comment of a person"), "write-1"
    )
)
check(
    "a plain comment on an issue without the label writes no label removal",
    [call for call in write_calls if call[:2] == ["issues", "edit"]] == [],
)
dispatcher.handle_payload(
    "issue_comment",
    comment_event(96, "I resolved the cause, go on", labels=["needs-owner"]),
    "held-1",
)
spool = events()
check(
    "a plain comment on a needs-owner issue queues the leg and removes the label",
    spool.get("held-1.json", {}).get("kind") == "worker"
    and spool["held-1.json"]["branch"] == "ai/issue-96"
    and [
        "issues",
        "edit",
        "96",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in tea_calls(),
)
clear_spool()
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls_list"] = [{"index": 215, "head": {"ref": "ai/issue-96"}}]
scenario["pulls"]["215"] = {"head": {"ref": "ai/issue-96"}, "body": "Closes #96"}
write_scenario(scenario)
dispatcher.handle_payload(
    "issue_comment",
    comment_event(
        215, "the runner is fixed, continue", is_pr=True, labels=["needs-owner"]
    ),
    "held-2",
)
spool = events()
check(
    "a plain comment on a needs-owner pull request queues the nudge",
    spool.get("held-2.json", {}).get("kind") == "nudge"
    and spool["held-2.json"]["branch"] == "ai/issue-96"
    and spool["held-2.json"]["entity"] == 215
    and "a bound of the loop had stopped" in spool["held-2.json"]["cause"],
)
check(
    "a plain comment on a needs-owner pull request removes the label",
    [
        "issues",
        "edit",
        "215",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in tea_calls(),
)
write_calls = delivery_calls(
    lambda: dispatcher.handle_payload(
        "issue_comment",
        comment_event(215, "another plain comment, the label is gone", is_pr=True),
        "write-2",
    )
)
check(
    "a plain comment on a pull request without the label writes no label removal",
    [call for call in write_calls if call[:2] == ["issues", "edit"]] == [],
)

# the poll fallback reads all open issues and parses the same human surface
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues_list"] = [
    {"index": 96, "labels": [{"name": "needs-owner"}]},
    {"index": 97, "labels": []},
]
scenario["issues"]["96"]["comments"] = [
    {"id": 6, "author": "jracon", "body": "the answer of the person"}
]
scenario["issues"]["97"]["comments"] = [
    {"id": 7, "author": "jracon", "body": "plain prose without a command"}
]
scenario["pulls_list"] = []
scenario["pulls"] = {}
write_scenario(scenario)
clear_spool()
issue_calls = delivery_calls(dispatcher.poll)
poll6 = queued_event("poll-6")
check(
    "the poll continues a needs-owner issue from a plain comment",
    poll6.get("kind") == "worker" and poll6.get("branch") == "ai/issue-96",
)
check(
    "the poll removes the label of the needs-owner issue it continues",
    [
        "issues",
        "edit",
        "96",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in issue_calls,
)
check(
    "the poll queues nothing for a plain comment on an issue without the label",
    events().get("poll-7.json") is None and processed("poll-7") is None,
)
check(
    "the poll writes no label removal for the comment without the label",
    not any(call[:3] == ["issues", "edit", "97"] for call in issue_calls),
)

# the bound reset keeps its shape (issue #582, acceptance criterion 3): the
# comment clears the pair and removes the label of the waker, while the
# label state of the entity gates the entity write alone
dispatcher.wake_count(97, 96)
write_calls = delivery_calls(
    lambda: dispatcher.handle_payload(
        "issue_comment",
        comment_event(96, "a plain comment on a paired entity"),
        "write-3",
    )
)
check(
    "a comment on a paired entity without the label clears the pair and removes the waker label alone",
    dispatcher.wakegate().get("97-96") is None
    and [
        "issues",
        "edit",
        "97",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in write_calls
    and not any(call[:3] == ["issues", "edit", "96"] for call in write_calls),
)

# the poll fallback reads the comments of each open ai/ pull request for the
# same surface as the webhook (issue #525): the final comment of a released
# leg wakes through the same rule, a command comment of a person continues
# the work, and plain prose continues a needs-owner thread. The slots of
# pull request legs now free through the poll as well
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {"98": {"index": 98, "body": ready_body()}},
        "pulls_list": [{"index": 216, "head": {"ref": "ai/issue-98"}}],
        "pulls": {
            "216": {
                "head": {"ref": "ai/issue-98"},
                "body": "Closes #98",
                "labels": [],
            }
        },
        "comments": {"216": [{"id": 31, "author": AGENT, "body": "/wake"}]},
    }
)
dispatcher.take_slot("ai/review-216", "s-216", "sid-216", 216)
dispatcher.poll()
prc = queued_event("poll-prc-31")
check(
    "the poll wakes the worker of a reviewer verdict from the pull request comments",
    prc.get("kind") == "nudge"
    and prc.get("branch") == "ai/issue-98"
    and prc.get("entity") == 216
    and prc.get("reason") == "wake of a reviewer verdict"
    and "reviewer verdict on pull request 216" in (prc.get("cause") or ""),
)
check(
    "the poll comment releases the reviewer slot and stops its session",
    ["stop", "sid-216"] in claude_calls(),
)
dispatcher.sweep()
dispatcher.sweep()
dispatcher.handle_payload(
    "issue_comment", comment_event(216, "done", sender=AGENT, is_pr=True), "prc-r"
)
clear_spool()

scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["comments"]["216"].append(
    {"id": 32, "author": "jracon", "body": "/loop address the new finding"}
)
write_scenario(scenario)
dispatcher.poll()
prc = queued_event("poll-prc-32")
check(
    "the poll queues the nudge of a command comment on the pull request",
    prc.get("kind") == "nudge" and prc.get("branch") == "ai/issue-98",
)
clear_spool()

scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
# the label sits on the forge with no wake pair behind it, the shape that a
# red-gate bound trip leaves (issue #582, acceptance criterion 2): the
# removal below proves that the label state alone drives the write
scenario["pulls"]["216"]["labels"] = [{"name": "needs-owner"}]
scenario["comments"]["216"].append(
    {"id": 33, "author": "jracon", "body": "the runner is fixed, continue"}
)
write_scenario(scenario)
prc_calls = delivery_calls(dispatcher.poll)
prc = queued_event("poll-prc-33")
check(
    "the poll continues a needs-owner pull request from a plain comment",
    prc.get("kind") == "nudge"
    and prc.get("branch") == "ai/issue-98"
    and "a bound of the loop had stopped" in (prc.get("cause") or ""),
)
check(
    "the poll removes the label of the needs-owner pull request it continues",
    [
        "issues",
        "edit",
        "216",
        "--remove-labels",
        "needs-owner",
        "--repo",
        REPO,
    ]
    in prc_calls,
)
# the tea stub applies the label write to the scenario, so the check above
# holds only when the label read runs before the reset removes the label
# (the first blocking finding of the review of pull request 553): a read
# after the reset finds no label and queues nothing. The emptied label list
# proves that the removal landed, and the queued nudge proves that the
# decision read the state before the removal
scenario_after = json.loads(scenario_file.read_text(encoding="utf-8"))
check(
    "the label read of the continuation precedes the reset that removes the label",
    scenario_after["pulls"]["216"].get("labels") == [] and prc.get("kind") == "nudge",
)
scenario = scenario_after
scenario["comments"]["216"].append(
    {"id": 34, "author": "jracon", "body": "one more prose comment"}
)
write_scenario(scenario)
plain_calls = delivery_calls(dispatcher.poll)
check(
    "a second plain comment after the continuation starts nothing and writes no label removal",
    queued_event("poll-prc-34") == {}
    and not any(call[:3] == ["issues", "edit", "216"] for call in plain_calls),
)

# ------------------------------------------------------- the serving trunk


# a repository can hold a second live trunk beside its default branch
# (issue #571): Minecraft_Recomposed holds 1.0.0/jarmod/trunk as the default
# branch and 1.0.0/native/trunk beside it. An instance that serves the
# native trunk names it through DISPATCHER_TRUNK, a knob the module reads at
# import time, so this section turns the knob through the module global.
# The spawn base, the pull request base, and the catch-up merge of the legs
# read the trunk, and an instance whose knob is empty keeps the shape of a
# single-trunk repository
clear_spool()
write_scenario(
    {
        "issues_list": [],
        "issues": {
            "170": {"index": 170, "body": ready_body()},
            "171": {"index": 171, "body": ready_body()},
            "172": {"index": 172, "body": ready_body()},
        },
        "pulls_list": [],
        "pulls": {},
    }
)
setattr(dispatcher, "TRUNK", "1.0.0/native/trunk")

loop_comment(170, "serve the native trunk", delivery="trunk-1")
dispatcher.sweep()
worker = spawns()[-1]
worker_text = worker["argv"][-1]
check(
    "a worker spawn of a named trunk starts the branch at the trunk",
    worker["argv"][2] == "ai/issue-170"
    and worker["argv"][worker["argv"].index("--verified-trunk") + 1]
    == "1.0.0/native/trunk"
    and "--from" not in worker["argv"],
)
check(
    "the worker prompt of a named trunk reads the trunk at every point",
    "The serving trunk of this dispatcher instance is 1.0.0/native/trunk" in worker_text
    and "origin/1.0.0/native/trunk" in worker_text
    and "tea pulls create --base 1.0.0/native/trunk" in worker_text
    and "against the default branch" not in worker_text,
)

loop_comment(170, "the worker ended", sender=AGENT, delivery="trunk-1r")
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["pulls_list"] = [{"index": 230, "head": {"ref": "ai/issue-170"}}]
scenario["pulls"]["230"] = {"head": {"ref": "ai/issue-170"}, "body": "Closes #170"}
write_scenario(scenario)
dispatcher.handle_payload(
    "issue_comment",
    comment_event(230, "/loop go on with the trunk", is_pr=True),
    "trunk-2",
)
dispatcher.sweep()
nudge = spawns()[-1]
check(
    "the nudge prompt of a named trunk names the trunk for the catch-up merge",
    nudge["argv"][2] == "ai/issue-170"
    and "origin/1.0.0/native/trunk" in nudge["argv"][-1]
    and "--from" not in nudge["argv"]
    and "--base" not in nudge["argv"][-1],
)
dispatcher.release_entity(230)

code, printed, err = run_prompt("worker", "171")
check(
    "the prompt command prints the trunk sentences of a hand spawn",
    code == 0
    and err == ""
    and "serving trunk of this dispatcher instance is 1.0.0/native/trunk" in printed
    and "tea pulls create --base 1.0.0/native/trunk" in printed,
)

# the stale-base guard under a named trunk: the report names the origin of
# the serving trunk, the base the fetch was to verify
os.environ["DISPATCHER_TEST_GIT_FAIL"] = "fetch"
loop_comment(172, "work while offline", delivery="trunk-3")
dispatcher.sweep()
comment_bodies = [
    " ".join(call[3:]) for call in tea_calls() if call[:2] == ["comments", "add"]
]
check(
    "the stale-base report under a named trunk names the serving trunk",
    (state / "failed" / "trunk-3.json").exists()
    and "172" in comment_bodies[-1]
    and "origin of the serving trunk" in comment_bodies[-1]
    and "origin main" not in comment_bodies[-1],
)
os.environ.pop("DISPATCHER_TEST_GIT_FAIL")

# the knob empty keeps the single-trunk shape, and the ruled route of
# issue #637 holds: the worker spawn names the default branch that
# origin/HEAD holds in the clone as a base that rule 4 verified, so the
# project tool runs no fetch of its own inside the sandbox tier
setattr(dispatcher, "TRUNK", "")
loop_comment(171, "and now the default trunk", delivery="trunk-4")
dispatcher.sweep()
plain = spawns()[-1]
check(
    "an instance with no named trunk passes the default branch as the verified trunk",
    plain["argv"][2] == "ai/issue-171"
    and plain["argv"][plain["argv"].index("--verified-trunk") + 1] == "main"
    and "--from" not in plain["argv"]
    and "against the default branch with tea pulls create" in plain["argv"][-1]
    and "serving trunk" not in plain["argv"][-1],
)
loop_comment(171, "the section ended", sender=AGENT, delivery="trunk-4r")

# a clone whose origin/HEAD answers nothing names no trunk: the spawn then
# passes no base, and the project tool keeps its own stale-base guard
os.environ["DISPATCHER_TEST_GIT_ORIGIN_HEAD"] = ""
loop_comment(172, "no origin head", delivery="trunk-5")
dispatcher.sweep()
bare = spawns()[-1]
check(
    "a clone with no origin/HEAD names no verified trunk",
    bare["argv"][2] == "ai/issue-172"
    and "--verified-trunk" not in bare["argv"]
    and "--from" not in bare["argv"],
)
os.environ.pop("DISPATCHER_TEST_GIT_ORIGIN_HEAD")
loop_comment(172, "the fallback row ended", sender=AGENT, delivery="trunk-5r")


# ------------------------------------------- the release of a crashed leg


# a crashed leg releases its entry before the ttl (issue #605): the sweep
# reads the state of the recorded session from `claude agents --json --all`,
# and a session that the harness reports ended frees the branch at once, so
# a leg that dies with no comment holds the commands of its entity for one
# sweep pass, not two hours. The stub listing carries one state word per
# session, the shape that the harness documents for every background entry
clear_spool()
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["65"] = {"index": 65, "body": ready_body(), "comments": []}
scenario["issues"]["66"] = {"index": 66, "body": ready_body(), "comments": []}
scenario["pulls_list"] = []
scenario["pulls"] = {}
write_scenario(scenario)

# the entry records the kind of its leg, so the liveness read of a later
# sweep knows the park wait of a windowed leg (issue #505)
dispatcher.handle_payload(
    "issue_comment", comment_event(66, "/watch", labels=[]), "crash-w"
)
dispatcher.sweep()
check(
    "the in-flight entry of a windowed spawn carries the windowed mark",
    spawns()[-1]["argv"][2] == "ai/issue-66"
    and dispatcher.inflight().get("ai/issue-66", {}).get("windowed") is True,
)
dispatcher.release_entity(66)

loop_comment(65, "the first leg", delivery="crash-1")
dispatcher.sweep()
entry = dispatcher.inflight().get("ai/issue-65")
check(
    "the in-flight entry of a plain spawn carries no windowed mark",
    entry is not None
    and entry.get("session_id") == "sid-ai/issue-65"
    and entry.get("windowed") is False,
)

# the session of the entry works: a later command of a person queues and
# waits in the spool, the incident shape of issue #605
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = json.dumps(
    [
        {
            "id": "sid-ai/issue-65",
            "kind": "background",
            "name": "genixis-test: ai/issue-65",
            "state": "working",
        }
    ]
)
spawns_before = len(spawns())
loop_comment(65, "go on after the crash", delivery="crash-2")
dispatcher.sweep()
check(
    "a queued command waits while the session of the entry works",
    "crash-2.json" in events() and len(spawns()) == spawns_before,
)

# the session ends with no comment: the next sweep releases the entry and
# runs the queued command, inside the ttl and with one liveness read
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = json.dumps(
    [
        {
            "id": "sid-ai/issue-65",
            "kind": "background",
            "name": "genixis-test: ai/issue-65",
            "state": "stopped",
        }
    ]
)
claude_before = len(claude_calls())
inflight = dispatcher.inflight()
inflight["ai/issue-65"]["since"] = int(time.time()) - 300
dispatcher.store_json(state / "inflight.json", inflight)
dispatcher.sweep()
check(
    "a session that ended with no comment frees the branch inside the ttl",
    len(spawns()) == spawns_before + 1
    and processed("crash-2") is not None
    and "ai/issue-65" in dispatcher.inflight()
    and ["agents", "--json", "--all"] in claude_calls()[claude_before:]
    and ["stop", "sid-ai/issue-65"] in claude_calls()[claude_before:],
)
dispatcher.release_entity(65)

# the state words rule the release: a plain leg ends with the turn, so done
# also releases it; a windowed leg holds on done, because its park question
# waits for the answer of the owner. A read that answers no state word, and
# an entry that no listing or no id names, hold the entry, so the ttl stays
# the backstop of the liveness rule


def holds_entry(listing, windowed=False, session_id="sid-62", unmarked=False):
    """claim_slot of one fresh entry whose session the stub listing names:
    True when the entry holds, so the sweep must wait for the leg. An
    unmarked entry carries no windowed key, the shape that the code before
    issue #605 wrote, so its kind is unknown."""
    dispatcher.take_slot("ai/issue-62", "s-62", session_id, 62, windowed)
    if unmarked:
        inflight = dispatcher.inflight()
        inflight["ai/issue-62"].pop("windowed")
        dispatcher.store_json(state / "inflight.json", inflight)
    os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = listing
    return not dispatcher.claim_slot("ai/issue-62")


check(
    "a plain entry holds while its session works or waits on a person",
    holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "working"}])
    )
    and holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "blocked"}])
    ),
)
check(
    "a plain entry releases on done, failed, and stopped",
    not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "done"}])
    )
    and not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "failed"}])
    )
    and not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "stopped"}])
    ),
)
check(
    "a windowed entry holds on done, the park wait of its leg",
    holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "done"}]),
        windowed=True,
    ),
)
check(
    "a windowed entry releases on failed and stopped",
    not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "failed"}]),
        windowed=True,
    )
    and not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "stopped"}]),
        windowed=True,
    ),
)
check(
    "a listing without a state word holds the entry",
    holds_entry(json.dumps([{"id": "sid-62", "kind": "background"}])),
)
check(
    "a listing that names no matching session holds the entry",
    holds_entry(json.dumps([{"id": "other", "kind": "background", "state": "done"}])),
)
check(
    "a listing that answers no json holds the entry",
    holds_entry(""),
)
check(
    "an entry with no session id holds, whatever the listing says",
    holds_entry(
        json.dumps([{"id": "s-62", "kind": "background", "state": "done"}]),
        session_id="",
    ),
)
check(
    "an entry with no windowed mark holds on done, the shape before the mark",
    holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "done"}]),
        unmarked=True,
    ),
)
check(
    "an entry with no windowed mark releases on failed and stopped",
    not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "failed"}]),
        unmarked=True,
    )
    and not holds_entry(
        json.dumps([{"id": "sid-62", "kind": "background", "state": "stopped"}]),
        unmarked=True,
    ),
)
dispatcher.release_inflight("ai/issue-62")

# the owner release step (issue #605): one command frees a held entry at
# once, whatever its session does, stops the session of the leg, and starts
# no leg and no comment, so it wakes nothing
spawns_before = len(spawns())
comments_before = len([call for call in tea_calls() if call[:2] == ["comments", "add"]])
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = json.dumps(
    [{"id": "sid-63", "kind": "background", "state": "working"}]
)
dispatcher.take_slot("ai/issue-63", "s-63", "sid-63", 63)
out = io.StringIO()
with contextlib.redirect_stdout(out):
    code = dispatcher.main(["dispatcher.py", "release", "ai/issue-63"])
check(
    "the release command frees a held entry at once and stops its session",
    code == 0
    and "ai/issue-63" not in dispatcher.inflight()
    and ["stop", "sid-63"] in claude_calls()
    and "released the entry of ai/issue-63" in out.getvalue()
    and len(spawns()) == spawns_before
    and len([call for call in tea_calls() if call[:2] == ["comments", "add"]])
    == comments_before,
)
out = io.StringIO()
with contextlib.redirect_stdout(out):
    code = dispatcher.main(["dispatcher.py", "release", "ai/issue-64"])
check(
    "the release command of a free branch answers 1 and changes nothing",
    code == 1
    and "no in-flight entry" in out.getvalue()
    and len(spawns()) == spawns_before,
)
os.environ["DISPATCHER_TEST_CLAUDE_SESSIONS"] = default_claude_sessions

# ---------------------------------------------------------- the sandbox tier
# (issue 607): with a spec loaded, each spawn runs as a transient forking
# service that carries the properties of the spec, the state of the branch
# records the harness instance and the units of the leg, and the release
# ends the session, the supervisor, and the units through that instance.
# The spec knob is read at import time, so this section sets the module
# global, like the pace section above, and a fake live user layer under the
# test home proves the copy into the per-leg config directory

# the loader half of the contract, before the parsed value is set by hand:
# the tier module writes the spec file and load_sandbox_spec reads it, and
# the two sides live in different languages, so these rows pin the key
# names of the wire contract (issue 619). The good file carries the emitted
# shape, and the bad file carries the camelCase key that the first switched
# host shipped: the loader must read one and degrade the other to the empty
# mapping, the plain-scope answer that the first after run of the probe
# harness quoted
spec_emitted = root / "sandbox-spec-emitted.json"
spec_emitted.write_text(
    json.dumps(
        {
            "unit_properties": ["ProtectSystem=strict", "IPAddressDeny=any"],
            "environment": {"https_proxy": "http://127.0.0.1:3128"},
        }
    ),
    encoding="utf-8",
)
spec_camel = root / "sandbox-spec-camel.json"
spec_camel.write_text(
    json.dumps(
        {
            "unitProperties": ["ProtectSystem=strict"],
            "environment": {"https_proxy": "http://127.0.0.1:3128"},
        }
    ),
    encoding="utf-8",
)
saved_spec_file = getattr(dispatcher, "SANDBOX_SPEC_FILE", "")
setattr(dispatcher, "SANDBOX_SPEC_FILE", str(spec_emitted))
check(
    "the loader reads a spec file of the emitted shape",
    dispatcher.load_sandbox_spec()
    == {
        "properties": ["ProtectSystem=strict", "IPAddressDeny=any"],
        "environment": {"https_proxy": "http://127.0.0.1:3128"},
    },
)
setattr(dispatcher, "SANDBOX_SPEC_FILE", str(spec_camel))
check(
    "the loader answers empty on keys it does not name",
    dispatcher.load_sandbox_spec() == {},
)
setattr(dispatcher, "SANDBOX_SPEC_FILE", saved_spec_file)

live_claude = home / ".claude"
live_claude.mkdir(parents=True, exist_ok=True)
(live_claude / "settings.json").write_text(
    '{"permissions": {"allow": ["Bash(fd *)"]}}', encoding="utf-8"
)
(live_claude / "CLAUDE.md").write_text(
    "instructions of the machine\n", encoding="utf-8"
)

setattr(
    dispatcher,
    "SANDBOX",
    {
        "properties": [
            "ProtectSystem=strict",
            "ProtectHome=tmpfs",
            "IPAddressDeny=any",
            "IPAddressAllow=127.0.0.0/8 ::1 100.64.0.0/10",
            "BindReadOnlyPaths=-/run/user/1000/agenix/zai_token",
        ],
        "environment": {"https_proxy": "http://127.0.0.1:3128"},
    },
)

# the socket hash of the harness (issue 633): the bundle of the harness
# derives the name of the socket directory of a config directory as the
# first eight hex chars of the sha256 of the directory string. The pair
# below is the recorded observation of the daemon.log of ai-review-632 on
# services, so a drift of the derivation on either side fails this row
# before a spawn links the wrong name
check(
    "the socket hash of the harness derives from the sha256 of the config directory",
    dispatcher.daemon_socket_hash(
        "/home/dev/projects/genixis/.claude-legs/ai-review-632/config"
    )
    == "f82b52d0",
)

scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["70"] = {"index": 70, "body": ready_body()}
write_scenario(scenario)

tier_log = root / "tier-systemd-run-log.jsonl"
os.environ["DISPATCHER_TEST_SYSTEMD_RUN_LOG"] = str(tier_log)
spawns_before = len(spawns())
loop_comment(70, "the tier run", delivery="tier-1")
dispatcher.sweep()
tier_calls = read_log(tier_log)
check(
    "a spawn under the tier runs a forking service unit and a plain agent unit",
    len(tier_calls) == 2
    and "--service-type=forking" in tier_calls[1]
    and "--scope" not in tier_calls[1]
    and "--scope" not in tier_calls[0]
    and tier_calls[0][0:2] == ["--user", "--unit"]
    and any(str(arg).startswith("leg-agent-ai-issue-70-") for arg in tier_calls[0]),
)
tier_spawn_call = tier_calls[1]
check(
    "the spawn unit carries the properties and the proxy of the spec",
    all(prop in tier_spawn_call for prop in dispatcher.SANDBOX["properties"])
    and f"https_proxy={dispatcher.SANDBOX['environment']['https_proxy']}"
    in tier_spawn_call,
)
tier_state = home / "projects" / "genixis-test" / ".claude-legs" / "ai-issue-70"
tier_config = tier_state / "config"
entry = dispatcher.inflight().get("ai/issue-70") or {}
tier_units = entry.get("units") or []
check(
    "the spawn writes its envelope to the leg state and records the runtime",
    (tier_state / "spawn.out").is_file()
    and len(spawns()) == spawns_before + 1
    and entry.get("config_dir") == str(tier_config)
    and isinstance(tier_units, list)
    and len(tier_units) == 2
    and dispatcher.branch_sessions().get("ai/issue-70", {}).get("config_dir")
    == str(tier_config),
)

# the socket placement of the tier leg (issue 633): the prepare links the
# socket directory of the leg state into the daemon root of the harness,
# and the spawn unit carries the bind property that mounts the same
# directory over the hardcoded daemon root inside the unit, so both
# namespaces resolve the socket path of the harness to one inode
tier_socket_dir = tier_state / "daemon-socket"
tier_socket_target = tier_socket_dir / dispatcher.daemon_socket_hash(str(tier_config))
tier_link = (
    Path(os.environ["DISPATCHER_DAEMON_TMP_ROOT"])
    / ("cc-daemon-%d" % os.getuid())
    / dispatcher.daemon_socket_hash(str(tier_config))
)
check(
    "the prepare of a tier leg links its socket directory into the daemon root",
    tier_socket_target.is_dir()
    and tier_link.is_symlink()
    and Path(os.readlink(tier_link)) == tier_socket_target,
)
check(
    "the spawn unit carries the bind of the socket directory over the daemon root",
    dispatcher.daemon_socket_bind_property(str(tier_config))
    == "BindPaths=%s:%s"
    % (tier_socket_dir, dispatcher.DAEMON_TMP_ROOT / ("cc-daemon-%d" % os.getuid()))
    and dispatcher.daemon_socket_bind_property(str(tier_config)) in tier_spawn_call,
)
check(
    "the config directory copies the live user layer and carries the env of the unit",
    (tier_config / "settings.json").is_file()
    and (tier_config / "CLAUDE.md").is_file()
    and f"CLAUDE_CONFIG_DIR={tier_config}" in tier_spawn_call
    and any(str(arg).startswith("SSH_AUTH_SOCK=") for arg in tier_spawn_call)
    and any(
        str(arg).startswith("GIT_SSH_COMMAND=ssh -F /dev/null -p 222")
        for arg in tier_spawn_call
    )
    and "GIT_CONFIG_COUNT=1" in tier_spawn_call,
)

# the host key pin pairing (issue 644): HostKeyAlias replaces the lookup
# name of the known-hosts database alone and carries no port on its own,
# so the alias of the pinned ssh command must name the bracketed
# host:port token that the committed line holds, the shape ssh-keyscan
# writes for a port. The read of the committed pin binds the token where
# the checkout of main sits beside the test, and stays neutral where the
# path does not exist, for example on the runner of CI
known_hosts_token = ""
try:
    known_hosts_token = (
        dispatcher.FORGE_KNOWN_HOSTS.read_text(encoding="utf-8")
        .splitlines()[0]
        .split()[0]
    )
except (OSError, IndexError):
    pass
check(
    "the pinned ssh command looks the host key up under the token of the committed line",
    any(
        str(arg).startswith("GIT_SSH_COMMAND=ssh -F /dev/null")
        and "HostKeyAlias=[%s]:%s" % (dispatcher.FORGE_HOST, dispatcher.FORGE_SSH_PORT)
        in str(arg)
        for arg in tier_spawn_call
    )
    and (
        not known_hosts_token
        or known_hosts_token
        == "[%s]:%s" % (dispatcher.FORGE_HOST, dispatcher.FORGE_SSH_PORT)
    ),
)
check(
    "the agent unit runs ssh-agent on the socket of the leg state under its own bounds",
    read_log(root / "ssh-agent-log.jsonl")[-1][:2] == ["-D", "-a"]
    and read_log(root / "ssh-add-log.jsonl")[-1]["argv"] == [str(push_key_file)]
    and read_log(root / "ssh-add-log.jsonl")[-1]["sock"]
    == str(tier_state / "agent.sock")
    and "ProtectSystem=strict" in tier_calls[0]
    and "IPAddressDeny=any" in tier_calls[0]
    and f"BindPaths={tier_state}" in tier_calls[0],
)

# the release of a tier leg: the stop and the daemon stop speak to the
# harness instance of the leg, and the units stop through systemctl
claude_calls_before = len(claude_calls())
systemctl_log = root / "systemctl-log.jsonl"
dispatcher.release_entity(70)
check(
    "the release of a tier leg stops the session and the supervisor of its instance and ends its units",
    ["stop", "sid-ai/issue-70"] in claude_calls()[claude_calls_before:]
    and ["daemon", "stop"] in claude_calls()[claude_calls_before:]
    and claude_config_dirs()[claude_calls_before:][-2:]
    == [str(tier_config), str(tier_config)]
    and len(read_log(systemctl_log)) == len(tier_units)
    and all(call[:2] == ["--user", "stop"] for call in read_log(systemctl_log))
    and sorted(call[2] for call in read_log(systemctl_log)) == sorted(tier_units),
)

# a second leg of the branch resumes through the config directory: the
# transcript lands under the per-leg projects tree, so the resume check of
# the record answers True and the spawn carries --resume
scenario = json.loads(scenario_file.read_text(encoding="utf-8"))
scenario["issues"]["70"] = {"index": 70, "body": ready_body()}
write_scenario(scenario)
transcript = tier_config / "projects" / "-nowhere" / "uuid-ai-issue-70.jsonl"
transcript.parent.mkdir(parents=True, exist_ok=True)
transcript.write_text("{}", encoding="utf-8")
os.environ["DISPATCHER_TEST_SYSTEMD_RUN_LOG"] = str(scope_log)
loop_comment(70, "the tier resume", delivery="tier-2")
dispatcher.sweep()
check(
    "a resumed tier leg reads the transcript of its own instance",
    spawns()[-1]["argv"][spawns()[-1]["argv"].index("--resume") + 1]
    == "uuid-ai-issue-70",
)
check(
    "the resume spawn of a tier leg relinks its socket directory",
    tier_link.is_symlink() and Path(os.readlink(tier_link)) == tier_socket_target,
)
dispatcher.release_entity(70)

# the release removes the link of the leg from the daemon root, after the
# daemon stop that itself speaks through the link, and a link that names
# another target stays untouched, because one config directory owns one
# link and the removal reads the target before it unlinks (issue 633)
check(
    "the release of a tier leg removes its link from the daemon root",
    not tier_link.is_symlink() and not tier_link.exists(),
)
foreign_link = (
    Path(os.environ["DISPATCHER_DAEMON_TMP_ROOT"])
    / ("cc-daemon-%d" % os.getuid())
    / ("0" * 8)
)
foreign_link.symlink_to(tier_socket_dir)
dispatcher.remove_daemon_socket_link(str(tier_config))
check(
    "the removal leaves a link that names another target",
    foreign_link.is_symlink(),
)
foreign_link.unlink()

# the copy mode of the tier runtime (issue 607, the record of 2026-11-21
# 12:28): the live CLAUDE.md of the user layer is store-backed and holds
# no owner-write bit, and a copy that propagates the mode of its source
# leaves a read-only copy after the first spawn of a branch, so every
# later spawn of that branch dies on PermissionError and posts nothing.
# The row prepares the runtime of a fresh branch twice over the
# read-only source: no raise, and the copy in the leg config directory
# stays writable and carries the content of the source
(live_claude / "CLAUDE.md").chmod(0o444)
readonly_source_error = ""
try:
    dispatcher.prepare_leg_runtime("ai/issue-71")
    dispatcher.prepare_leg_runtime("ai/issue-71")
except OSError as error:
    readonly_source_error = repr(error)
readonly_config = (
    home / "projects" / "genixis-test" / ".claude-legs" / "ai-issue-71" / "config"
)
check(
    "a second prepare of a branch over a read-only source raises nothing and keeps the copy writable",
    readonly_source_error == ""
    and bool((readonly_config / "CLAUDE.md").stat().st_mode & 0o200)
    and (readonly_config / "CLAUDE.md").read_text(encoding="utf-8")
    == (live_claude / "CLAUDE.md").read_text(encoding="utf-8"),
)
(live_claude / "CLAUDE.md").chmod(0o644)

# the workspace trust of the tier runtime (issue 607, the records of
# 2026-11-21 14:10 and 14:44): the trust state of the harness lives in the
# .claude.json of its config directory, a session of the tier answers no
# trust dialog, and the harness refuses an untrusted working directory, so
# each spawn died at the gate Workspace not trusted. The row gives the live
# user an onboarding file beside the config directory, prepares the runtime
# of a fresh branch, lets the harness state of the leg drift the way the
# live runs made it drift (a config rewrite without the trust of the
# worktree, and a backup that predates the seed, the restore source the
# harness names), prepares again, and asserts the seeded state
live_onboarding = home / ".claude.json"
live_onboarding.write_text(
    json.dumps({"hasCompletedOnboarding": True, "projects": {}}), encoding="utf-8"
)
dispatcher.prepare_leg_runtime("ai/issue-72")
trust_config = (
    home / "projects" / "genixis-test" / ".claude-legs" / "ai-issue-72" / "config"
)
trust_worktree = os.path.realpath(home / "projects" / "genixis-test" / "ai-issue-72")
first_seed = json.loads((trust_config / ".claude.json").read_text(encoding="utf-8"))
(trust_config / ".claude.json").write_text(
    json.dumps({"userID": "drift", "projects": {}}), encoding="utf-8"
)
stale_backup = trust_config / "backups" / ".claude.json.backup.1795000000000"
(trust_config / "backups").mkdir(exist_ok=True)
stale_backup.write_text(json.dumps({"userID": "stale"}), encoding="utf-8")
dispatcher.prepare_leg_runtime("ai/issue-72")
reseeded = json.loads((trust_config / ".claude.json").read_text(encoding="utf-8"))
reseeded_backup = json.loads(stale_backup.read_text(encoding="utf-8"))


def trust_accepted(state: dict) -> bool:
    """The seeded flag of the worktree of the row, read through get chains so
    a missing seed fails the row instead of raising it."""
    projects = state.get("projects")
    entry = projects.get(trust_worktree) if isinstance(projects, dict) else None
    return isinstance(entry, dict) and entry.get("hasTrustDialogAccepted") is True


check(
    "every prepare seeds the worktree trust of the branch into the config state and its backup",
    first_seed.get("hasCompletedOnboarding") is True
    and trust_accepted(first_seed)
    and reseeded.get("userID") == "drift"
    and trust_accepted(reseeded)
    and reseeded_backup.get("userID") == "stale"
    and trust_accepted(reseeded_backup)
    and json.loads(live_onboarding.read_text(encoding="utf-8")).get("projects") == {},
)

# the rebuild of the socket directory (issue 633): a supervisor of a
# previous run that died without its own cleanup leaves its socket file
# behind, and the prepare of a fresh spawn removes the directory, so the
# supervisor of the spawn binds the path that the harness computes
stale_state = home / "projects" / "genixis-test" / ".claude-legs" / "ai-issue-73"
stale_config = str(stale_state / "config")
stale_socket = (
    stale_state
    / "daemon-socket"
    / dispatcher.daemon_socket_hash(stale_config)
    / "control.sock"
)
dispatcher.prepare_leg_runtime("ai/issue-73")
stale_socket.parent.mkdir(parents=True, exist_ok=True)
stale_socket.write_text("", encoding="utf-8")
dispatcher.prepare_leg_runtime("ai/issue-73")
check(
    "the prepare of a leg rebuilds its socket directory without the socket of a dead supervisor",
    stale_socket.parent.is_dir()
    and not stale_socket.exists()
    and (
        Path(os.environ["DISPATCHER_DAEMON_TMP_ROOT"])
        / ("cc-daemon-%d" % os.getuid())
        / dispatcher.daemon_socket_hash(stale_config)
    ).is_symlink(),
)

os.environ["DISPATCHER_TEST_SYSTEMD_RUN_LOG"] = str(scope_log)

server.shutdown()
server.server_close()
shutil.rmtree(root, ignore_errors=True)

failed = [name for name, ok in results if not ok]
print("%d of %d checks pass" % (len(results) - len(failed), len(results)))
if failed:
    print("failed: " + ", ".join(failed))
    sys.exit(1)
