"""Probe the sandbox tier of a spawned session on `services`. Run: python3 modules/services/dispatcher/sandbox-probe.py

The tier of issue 607 bounds each spawned session with an instance of the leg-unit template on the system
manager and an allowlisting forward proxy, and an agent writes both (docs/adr/spine-work-by-agents.md). This
harness is the oracle of the tier: it runs inside a session and tries what the tier must block, one probe per
control. A control holds when the action fails. The six tier controls do not hold before the tier lands, so a
run on the open host quotes the gap, and the run exits 1. The forge control holds before and after, because
the hook answers above every local tier. The run exits 0 when every control holds.

The write probe writes one file under the home directory, outside every carve-out of the unit, and removes the
file when the write answers. The ssh probe reads one byte of each key and config file and never prints file
content. The egress probe connects to one address that no allowlist entry names. The proxy probe reads the plan
files for the endpoint hosts, the one source that the allowlist of the proxy also derives from, and connects to
each host with a raw socket, which no proxy environment governs. The leg-placement control of issue 633 reads
the placement of the leg instead of trying a blocked action, so it holds on what it reads: the session process
sits in the cgroup of the leg-unit template instance, the mount table names the bind of the daemon socket
directory over the daemon root of the harness, and the supervisor socket resolves to the leg state through
both namespaces as one inode. The push-path control of issue 658 runs one git ls-remote through the transport
that the environment of the leg carries, the same ssh command and agent socket that a push uses, and it holds
when the route answers. The forge probe reads the settings of the
session for the hook, and feeds one push to the default branch, one compound command, and one entity edit to
forge-hook.py of the same tree, with the markers of a spawned headless session set; none of the three cases
reaches the network.

The probe runs live on `services` only. The pull request gate runs the static checks of this file and no live
probe, because the runner is not the sandbox (lib/checks.nix). The direct command needs one allow rule in
.claude/settings.json; until the rule exists, the run of a leg goes through the nested print-mode session of
AGENTS.md, and the owner adds the rule with the tier.
"""

import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import urllib.parse

HOME = os.path.expanduser("~")

# the hook of the same tree: the probe reads the protections where the repository holds them
HOOK = os.path.normpath(
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        os.pardir,
        os.pardir,
        "programs",
        "cli",
        "claude",
        "forge-hook.py",
    )
)

# the one address of the egress probe: no entry of the allowlist names it, and the tailnet
# range of the unit covers no part of it
EGRESS_ADDRESS = ("1.1.1.1", 443)

# project spawn sets the first marker in the settings env of its sessions, and
# `project spawn --headless` sets the second beside it (see project.nix)
SPAWN_ENV = "PROJECT_SPAWN_SESSION"
HEADLESS_ENV = "PROJECT_HEADLESS_SESSION"

# the ssh probe reads one byte of each target and quotes only the outcome: the push key that
# the issue names, the store symlink of the dispatcher README, and the agenix identity of
# ssh.nix; the control holds when no target answers
SSH_TARGETS = [
    os.path.join(HOME, ".ssh", "claude-bot"),
    os.path.join(HOME, ".ssh", "config"),
    os.path.join(HOME, ".ssh", "genixis_user"),
]

# the three answers that the forge probe demands from the hook: the command, and its label
FORGE_CASES = [
    ("git push origin main", "a push to the default branch"),
    ("git push -u origin feat/x && tea issues list", "a compound command"),
    ("tea issues close 555", "an entity edit in a headless session"),
]

# one network try stops after this many seconds, so a denied connection that drops packets
# still answers within the run
CONNECT_TIMEOUT = 5.0

# the git transport of the push-path probe stops after this many seconds: a
# working route answers in under two, and a dropped route would hold the TCP
# connect for minutes
PUSH_PROBE_TIMEOUT = 30.0

# one quote of the output stays under this many characters
QUOTE_LIMIT = 120


def quote(error):
    """Return the text of an error, cut at the quote limit."""
    text = " ".join(str(error).split())
    if len(text) > QUOTE_LIMIT:
        return text[: QUOTE_LIMIT - 3] + "..."
    return text


def connect(host, port):
    """Try one direct TCP connection. Return (connected, quote)."""
    try:
        connection = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    except OSError as error:
        return False, f"connection to {host}:{port} failed: {quote(error)}"
    connection.close()
    return True, f"connection to {host}:{port} answered"


def plan_hosts():
    """Return the endpoint host names of the plan files, the one source of the allowlist."""
    plans = os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")),
        "project",
        "plans",
    )
    try:
        names = sorted(os.listdir(plans))
    except OSError:
        return []
    hosts = []
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(plans, name)) as file:
                plan = json.load(file)
            url = plan["env"]["ANTHROPIC_BASE_URL"]
        except (OSError, ValueError, KeyError, TypeError):
            continue
        host = urllib.parse.urlsplit(url).hostname
        if host:
            hosts.append(host)
    return hosts


def probe_write_outside():
    """Write one file under the home directory, outside every carve-out of the unit."""
    path = os.path.join(HOME, ".sandbox-probe-write")
    try:
        with open(path, "w") as file:
            file.write("sandbox-probe\n")
    except OSError as error:
        return True, f"write of {path} failed: {quote(error)}"
    try:
        os.unlink(path)
    except OSError:
        pass
    return False, f"write of {path} answered"


def probe_read_ssh():
    """Read one byte of each ssh target. The control holds when no target answers."""
    notes = []
    for path in SSH_TARGETS:
        try:
            with open(path, "rb") as file:
                file.read(1)
        except OSError as error:
            notes.append(f"read of {path} failed: {quote(error)}")
        else:
            notes.append(f"read of {path} answered")
            return False, "; ".join(notes)
    return True, "; ".join(notes)


def probe_direct_egress():
    """Connect to one address that no allowlist entry names."""
    connected, note = connect(*EGRESS_ADDRESS)
    return not connected, note


def probe_proxy_bypass():
    """Connect to each plan endpoint host with a raw socket, which no proxy governs."""
    hosts = plan_hosts()
    if not hosts:
        return (
            False,
            "no plan file named an endpoint, so the probe holds no host to reach",
        )
    notes = []
    held = True
    for host in hosts:
        connected, note = connect(host, 443)
        notes.append(note)
        if connected:
            held = False
    return held, "; ".join(notes)


# the daemon root of the harness (issue 633): the bundle of the harness
# joins /tmp, cc-daemon-<uid>, and the first eight hex chars of the sha256
# of the config directory into the socket path of the supervisor, and it
# honors no variable for the root. The dispatcher of the loop links the
# socket directory of the leg state under the same root and binds it over
# the root inside the unit, so both namespaces resolve one socket path to
# one inode
DAEMON_ROOT = "/tmp"


def daemon_socket_hash(config):
    """The socket directory name of one config directory, as the harness
    derives it."""
    return hashlib.sha256(config.encode("utf-8")).hexdigest()[:8]


def probe_leg_placement():
    """Read the placement of the leg (issue 633) instead of trying a blocked
    action. The control fails while the supervisor socket is unreachable
    from outside the unit, or while a session process of the leg sits
    outside its unit: the cgroup of this process must name the leg-unit
    template instance and no tmux spawn scope, the mount table must name
    the bind of the daemon socket directory over the daemon root, and the
    supervisor socket must resolve to the leg state through the harness
    path and the leg state path as one inode."""
    notes = []
    held = True
    try:
        with open("/proc/self/cgroup", encoding="utf-8") as file:
            cgroup = file.read()
    except OSError as error:
        held = False
        cgroup = ""
        notes.append(f"cgroup read failed: {quote(error)}")
    if cgroup and ("leg-" not in cgroup or "tmux-spawn" in cgroup):
        held = False
        notes.append(
            "the session process sits outside a leg unit: "
            + quote(" ".join(cgroup.split()))
        )
    elif cgroup:
        notes.append("the session process sits in the cgroup of a leg unit")
    config = os.environ.get("CLAUDE_CONFIG_DIR", "")
    if not config:
        held = False
        notes.append(
            "CLAUDE_CONFIG_DIR holds no config directory, so no leg socket to read"
        )
        return held, "; ".join(notes)
    uid = os.getuid()
    daemon_dir = f"{DAEMON_ROOT}/cc-daemon-{uid}"
    try:
        with open("/proc/self/mountinfo", encoding="utf-8") as file:
            mounts = file.read().splitlines()
    except OSError as error:
        held = False
        mounts = []
        notes.append(f"mountinfo read failed: {quote(error)}")
    mounted = any(
        len(fields) > 4 and fields[4] == daemon_dir
        for fields in (line.split() for line in mounts)
    )
    if mounted:
        notes.append(f"the mount table names the bind at {daemon_dir}")
    else:
        held = False
        notes.append(f"the mount table names no bind at {daemon_dir}")
    harness_path = f"{daemon_dir}/{daemon_socket_hash(config)}/control.sock"
    state_path = (
        f"{os.path.dirname(config)}/daemon-socket/"
        f"{daemon_socket_hash(config)}/control.sock"
    )
    harness_stat = state_stat = None
    try:
        harness_stat = os.stat(harness_path)
    except OSError as error:
        held = False
        notes.append(f"stat of {harness_path} failed: {quote(error)}")
    try:
        state_stat = os.stat(state_path)
    except OSError as error:
        held = False
        notes.append(f"stat of {state_path} failed: {quote(error)}")
    if harness_stat is not None and state_stat is not None:
        same = (
            harness_stat.st_dev == state_stat.st_dev
            and harness_stat.st_ino == state_stat.st_ino
        )
        if same:
            notes.append("the supervisor socket resolves to the leg state as one inode")
        else:
            held = False
            notes.append(
                "the supervisor socket of the harness path is not the socket of the leg state"
            )
    return held, "; ".join(notes)


def probe_push_path():
    """Run one git ls-remote through the transport of the leg (issue 658).
    The control holds when the ssh route that a push uses answers from
    inside the tier: the transport is the GIT_SSH_COMMAND of the session
    environment with the agent socket beside it, and the route must reach
    the forge that origin names."""
    ssh_command = os.environ.get("GIT_SSH_COMMAND", "")
    if not ssh_command:
        return (
            False,
            "the environment carries no GIT_SSH_COMMAND, so the session holds "
            "no leg transport to probe",
        )
    # the route of the push is the host of the remote URL: the publish of
    # the ssh port DNATs the connect to the container address of the forge,
    # and the allow list of this leg names that address, so the name route
    # must answer from inside the tier (issue 658)
    route = "the host of the remote URL"
    try:
        named = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=PUSH_PROBE_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return False, f"the checkout named no origin remote: {quote(error)}"
    if named.returncode != 0:
        return False, f"the checkout named no origin remote: {quote(named.stderr)}"
    url = named.stdout.strip()
    try:
        run = subprocess.run(
            ["git", "ls-remote", url, "HEAD"],
            capture_output=True,
            text=True,
            timeout=PUSH_PROBE_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, (
            f"the push path through {route} to {url} did not answer within "
            f"{PUSH_PROBE_TIMEOUT}s"
        )
    except (OSError, subprocess.SubprocessError) as error:
        return False, f"the push path through {route} to {url} failed: {quote(error)}"
    if run.returncode == 0:
        return True, f"the push path through {route} answered for {url}"
    return False, f"the push path through {route} to {url} failed: {quote(run.stderr)}"


def git(cwd, *args):
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
    )


def hook_answer(env, command, cwd):
    """Feed one command to the hook. Return the verdict word, or None when it stays silent."""
    event = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}
    try:
        run = subprocess.run(
            [sys.executable, HOOK],
            input=json.dumps(event),
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return None, quote(error)
    if not run.stdout.strip():
        detail = quote(run.stderr.strip() or "no stderr")
        return None, f"the hook answered nothing (exit {run.returncode}: {detail})"
    try:
        answer = json.loads(run.stdout)
        return answer["hookSpecificOutput"]["permissionDecision"], None
    except (ValueError, KeyError, TypeError):
        return None, f"the hook printed no verdict: {quote(run.stdout)}"


def session_names_hook():
    """True when the settings of the session carry the forge hook for the Bash tool."""
    path = os.path.join(HOME, ".claude", "settings.json")
    try:
        with open(path) as file:
            data = json.load(file)
    except (OSError, ValueError):
        return False, f"{path} holds no readable settings object"
    hooks = data.get("hooks") if isinstance(data, dict) else None
    entries = hooks.get("PreToolUse") if isinstance(hooks, dict) else None
    for entry in entries or []:
        if not isinstance(entry, dict) or entry.get("matcher") != "Bash":
            continue
        for hook in entry.get("hooks") or []:
            command = str(hook.get("command")) if isinstance(hook, dict) else ""
            if "forge-hook.py" in command:
                return True, f"{path} names the forge hook for the Bash tool"
    return False, f"{path} names no forge hook for the Bash tool"


def probe_forge_protections():
    """Read the hook of the session settings, and demand the three deny answers of the hook."""
    configured, note = session_names_hook()
    notes = [note]
    held = configured
    with tempfile.TemporaryDirectory() as tmp:
        repo = os.path.join(tmp, "repo")
        os.mkdir(repo)
        try:
            git(repo, "init", "-q", "-b", "main")
            git(repo, "commit", "-q", "--allow-empty", "-m", "first")
            git(
                repo,
                "remote",
                "add",
                "origin",
                "https://forgejo.local.jracon.xyz/jracon/genixis.git",
            )
            git(repo, "config", "project.defaultBranch", "main")
        except (OSError, subprocess.SubprocessError) as error:
            return False, f"the probe built no fixture repository: {quote(error)}"
        env = dict(os.environ)
        env[SPAWN_ENV] = "1"
        env[HEADLESS_ENV] = "1"
        for command, label in FORGE_CASES:
            verdict, failure = hook_answer(env, command, repo)
            if verdict == "deny":
                notes.append(f"{label} denied")
            elif failure:
                held = False
                notes.append(f"{label}: {failure}")
            else:
                held = False
                notes.append(f"{label} answered {verdict}")
    return held, "; ".join(notes)


def main():
    probes = [
        ("write-outside", probe_write_outside),
        ("read-ssh", probe_read_ssh),
        ("direct-egress", probe_direct_egress),
        ("proxy-bypass", probe_proxy_bypass),
        ("leg-placement", probe_leg_placement),
        ("push-path", probe_push_path),
        ("forge-protections", probe_forge_protections),
    ]
    print(
        f"sandbox-probe on {os.uname().nodename}: "
        "a control holds when the action fails, and the leg-placement control "
        "holds on the placement it reads (issues 555 and 633)"
    )
    held = 0
    for name, probe in probes:
        ok, note = probe()
        held += ok
        print(f"probe {name}: {'HELD' if ok else 'NOT HELD'}: {note}")
    print(f"{held} of {len(probes)} controls hold")
    return 0 if held == len(probes) else 1


if __name__ == "__main__":
    sys.exit(main())
