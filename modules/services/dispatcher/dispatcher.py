#!/usr/bin/env python3
"""The dispatcher of the factory loop (issue #74, phase 4; issue #83).

One program, five entry points:

    dispatcher.py serve   the webhook receiver of the dev user on services
    dispatcher.py run     one pass over the event spool (spawn legs)
    dispatcher.py poll    the tea fallback: read gated issues, then run
    dispatcher.py prompt  print the brief of one leg, and start no leg
    dispatcher.py release free the in-flight entry of one branch at once

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
import shutil
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
COMMAND_PREFIX = os.environ.get("DISPATCHER_COMMAND_PREFIX", "/loop")
# the command that starts a watched leg (issue #470, option C; the split
# into its own command is issue #525): the first word of the comment, the
# same grammar as the loop command. The word behind /loop that the windowed
# route of issue #470 reserved is gone: a command of the loop takes no word
# arguments, each variant is its own command
WATCH_COMMAND = os.environ.get("DISPATCHER_WATCH_COMMAND", "/watch")
# the word of the prompt entry point, which prints the brief of a watched
# leg for a hand spawner: the command word without its slash
WATCH_WORD = WATCH_COMMAND.lstrip("/")
AI_PREFIX = "ai/"
WORKER_BRANCH = "ai/issue-{n}"
REVIEWER_PREFIX = "ai/review-"
REVIEWER_BRANCH = REVIEWER_PREFIX + "{n}"

PROJECT_DIR = os.environ.get("DISPATCHER_PROJECT", "genixis")
# the serving trunk of this instance (issue #571): the base of a worker
# spawn, the base of the pull request of its legs, and the branch that the
# catch-up merge pulls. A repository can hold a second live trunk beside its
# default branch (Minecraft_Recomposed holds 1.0.0/jarmod/trunk as the
# default branch and 1.0.0/native/trunk beside it), and an instance that
# serves such a trunk names it here, so no leg starts on the other platform
# or opens into it. The empty value serves the default branch of the
# repository. The units of this repository set nothing, because its default
# branch is its trunk. One instance serves one trunk: the branch names of
# the loop are one per repository, so a second instance of the same
# repository would collide with the first on every branch (machine decision
# 25)
TRUNK = os.environ.get("DISPATCHER_TRUNK", "")
WORKER_PLAN = os.environ.get("DISPATCHER_WORKER_PLAN", "zai")
REVIEWER_PLAN = os.environ.get("DISPATCHER_REVIEWER_PLAN", "zai")
# dontAsk turns a command that no rule allows into a denial the leg sees, so
# it comments that it is blocked and stops. acceptEdits would hang the leg at
# a prompt no person answers. bypassPermissions follows only when the sandbox
# probes of phase 5 of issue 74 pass (see the machine decisions of the README).
PERMISSION_MODE = os.environ.get("DISPATCHER_PERMISSION_MODE", "dontAsk")
# the mode of a windowed leg (issue #470, option C): the owner watches the
# view window of the session and answers its prompts, so the mode must wait
# for the answer instead of denying the call. default makes every ask wait,
# above all the consent prompt that the harness raises on an edit of a
# settings file, a gate that sits above every allow rule. The session keeps
# its headless markers, so the forge hook still turns its own asks into
# denials: the forge work of the leg stays inside the allow rules, and the
# watched prompts are the asks of the harness
WINDOWED_PERMISSION_MODE = os.environ.get(
    "DISPATCHER_WINDOWED_PERMISSION_MODE", "default"
)

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

# ---------------------------------------------------------- the sandbox tier

# the sandbox tier of issue 607 (section S of issue 393): each spawned leg
# runs inside a transient sandboxed unit, and the spec file of the tier
# (modules/services/sandbox-tier.nix) names its properties. The dispatcher
# reads the spec once and holds it for the run; an absent or unreadable spec
# leaves every spawn on the plain scope of the code before the tier, so the
# loop keeps working while the file travels, and a missing file degrades to
# the unbounded state that the probe harness quotes
SANDBOX_SPEC_FILE = os.environ.get("DISPATCHER_SANDBOX_SPEC", "")
# the per-leg state under the project root: the config directory of the
# harness of the leg (CLAUDE_CONFIG_DIR) and the socket of its agent. The
# checkout carve-out of the unit covers the whole project root, so no extra
# bound carries the directory
LEG_STATE_ROOT = Path(
    os.environ.get(
        "DISPATCHER_LEG_STATE",
        str(Path.home() / "projects" / PROJECT_DIR / ".claude-legs"),
    )
)
# the hardcoded root of the harness daemon socket dirs (issue 633): the
# bundle of the harness joins this root, cc-daemon-<uid>, and the first
# eight hex chars of the sha256 of the config directory into one path, and
# it honors no variable for the root, so the socket placement of a leg meets
# the harness there. The env override serves the stub harness, which writes
# nothing outside its temporary directory
DAEMON_TMP_ROOT = Path(os.environ.get("DISPATCHER_DAEMON_TMP_ROOT", "/tmp"))
# the git transport of a leg inside the tier: no file of ~/.ssh is visible,
# so ssh takes its options from the command line, its key from an agent that
# the dispatcher starts with the push key alone, and its host pin from the
# committed known_hosts file of the checkout. The forge is reached through
# the tailnet name of this host, because the forge name itself resolves to
# the LAN address and the unit bounds the LAN out (docs/adr/forge-naming-chain.md)
PUSH_KEY = os.environ.get("DISPATCHER_PUSH_KEY", "")
FORGE_HOST = os.environ.get("DISPATCHER_FORGE_HOST", "forgejo.local.jracon.xyz")
FORGE_SSH_HOST = os.environ.get("DISPATCHER_FORGE_SSH_HOST", "services")
FORGE_SSH_PORT = os.environ.get("DISPATCHER_FORGE_SSH_PORT", "222")
FORGE_KNOWN_HOSTS = (
    Path.home()
    / "projects"
    / PROJECT_DIR
    / "main"
    / "modules"
    / "programs"
    / "cli"
    / "forge-known-hosts"
)
SSH_AGENT_BIN = os.environ.get("DISPATCHER_SSH_AGENT", "ssh-agent")
SSH_ADD_BIN = os.environ.get("DISPATCHER_SSH_ADD", "ssh-add")
SYSTEMCTL_BIN = os.environ.get("DISPATCHER_SYSTEMCTL", "systemctl")


def load_sandbox_spec() -> dict:
    """The unit spec of the sandbox tier, or the empty mapping when no spec
    holds. The file is JSON with the two keys of the wire contract:
    unit_properties, the systemd properties of the transient unit of each
    leg, and environment, the proxy variables of the leg. The emitter is
    modules/services/sandbox-tier.nix, and the sandbox-spec check of
    lib/checks.nix feeds its text to this loader, so a key drift on either
    side fails the gate (issue 619). A malformed file
    answers the empty mapping, exactly like an absent one: the spawn then
    runs on the plain scope, and the after run of the probe harness quotes
    the open state."""
    if not SANDBOX_SPEC_FILE:
        return {}
    try:
        with open(SANDBOX_SPEC_FILE, encoding="utf-8") as handle:
            spec = json.load(handle)
    except (OSError, ValueError) as err:
        log.warning(
            "sandbox spec %s unreadable, legs run on the plain scope: %s",
            SANDBOX_SPEC_FILE,
            err,
        )
        return {}
    properties = spec.get("unit_properties") if isinstance(spec, dict) else None
    environment = spec.get("environment") if isinstance(spec, dict) else None
    if not isinstance(properties, list) or not all(
        isinstance(p, str) for p in properties
    ):
        log.warning(
            "sandbox spec %s holds no unit_properties list, legs run on the plain scope",
            SANDBOX_SPEC_FILE,
        )
        return {}
    if not isinstance(environment, dict):
        environment = {}
    return {
        "properties": [str(p) for p in properties],
        "environment": {str(k): str(v) for k, v in environment.items()},
    }


SANDBOX = load_sandbox_spec()


def leg_slug(branch: str) -> str:
    """The unit-safe form of a branch name: every character that a systemd
    unit name refuses becomes a hyphen."""
    return re.sub(r"[^A-Za-z0-9]", "-", branch).strip("-") or "leg"


def leg_state_dir(branch: str) -> Path:
    return LEG_STATE_ROOT / leg_slug(branch)


def daemon_socket_hash(config_dir: str) -> str:
    """The name of the socket directory of one config directory, as the
    harness derives it: the first eight hex chars of the sha256 of the
    directory string (the bundle of the harness, the hash function beside
    the socket path builder; issue 633)."""
    return hashlib.sha256(config_dir.encode("utf-8")).hexdigest()[:8]


def daemon_socket_paths(config_dir: str) -> tuple[Path, Path]:
    """The two halves of the socket placement of one leg (issue 633). The
    socket directory of the leg state is the bind source that the transient
    unit mounts over the hardcoded daemon root of the harness, and the link
    beside it is the path that the attach of the view window and every
    claude call of the dispatcher resolve on the host: both namespaces then
    resolve one socket path to one inode. The link carries the name that
    the harness itself derives, so it answers the path that the harness
    computes, and one config directory owns one link."""
    socket_dir = Path(config_dir).parent / "daemon-socket"
    link = (
        DAEMON_TMP_ROOT
        / f"cc-daemon-{os.getuid()}"
        / daemon_socket_hash(config_dir)
    )
    return socket_dir, link


def prepare_daemon_socket(config_dir: str) -> None:
    """Rebuild the socket directory of one leg and link it into the daemon
    root of the harness, before the unit starts (issue 633). The harness
    builds the control socket path of the per-config-directory supervisor
    from the uid alone, and honors no variable for the root, so PrivateTmp
    puts that path into the private tmp of the unit, where no attach
    reaches it, and the stall recovery of the attach then replaces the
    supervisor from the tmux pane and moves the session out of the cgroup
    of the unit. The rebuild answers the other half: a supervisor of a
    previous run that died without its own cleanup leaves its socket file
    behind, and a fresh supervisor could refuse to bind the path. The link
    may dangle until the supervisor binds: the spawn opens the view window
    only after the envelope, and the supervisor binds its socket before the
    envelope."""
    socket_dir, link = daemon_socket_paths(config_dir)
    target = socket_dir / daemon_socket_hash(config_dir)
    link.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    socket_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir(mode=0o700)
    if link.is_symlink() or link.is_file():
        link.unlink()
    elif link.is_dir():
        shutil.rmtree(link)
    link.symlink_to(target)


def daemon_socket_bind_property(config_dir: str) -> str:
    """The -p entry that mounts the socket directory of the leg state over
    the hardcoded daemon root of the harness inside the unit (issue 633).
    systemd applies the bind entries after the private tmp is set up, the
    way the plan token bind of the tier lands over the home that
    ProtectHome=tmpfs hides (modules/services/sandbox-tier.nix, the plan
    token comment), so the supervisor socket lands in the leg state, stays
    reachable from outside the unit, and the rest of /tmp stays private."""
    socket_dir, _ = daemon_socket_paths(config_dir)
    daemon_tmp = DAEMON_TMP_ROOT / f"cc-daemon-{os.getuid()}"
    return f"BindPaths={socket_dir}:{daemon_tmp}"


def remove_daemon_socket_link(config_dir: str) -> None:
    """Remove the host-side link of one leg, after the supervisor it serves
    stopped (issue 633). The link is the only host-side artifact of the
    socket placement, and the removal reads the target before it unlinks,
    so a link that another leg owns stays untouched."""
    socket_dir, link = daemon_socket_paths(config_dir)
    target = socket_dir / daemon_socket_hash(config_dir)
    if link.is_symlink() and Path(os.readlink(link)) == target:
        link.unlink()


def prepare_leg_runtime(branch: str) -> dict | None:
    """Build the per-leg state of one branch for a sandboxed spawn, or answer
    None when the tier is off. The config directory of the harness
    (CLAUDE_CONFIG_DIR) is the heart of the runtime: the supervisor of the
    background sessions runs one instance per config directory, so each leg
    gets its own supervisor inside its own unit, and the sessions of the leg
    land in the cgroup of that unit (the harness docs, Where state is
    stored). The dispatcher copies the live user layer into the directory
    before each spawn — the settings, the instructions, the onboarding state
    — because the config directory holds the whole harness state, and a
    fresh directory would start the session with no allow rules and no forge
    hook. The skills tree is a symlink, so one copy serves every leg. Each
    copy of the settings and the instructions lands writable, whatever mode
    its source holds: a mode-propagating copy of a store-backed source
    leaves a read-only file behind, and the next spawn of the branch cannot
    rewrite it. The trust of the worktree is seeded into the config state
    on every spawn, because a session of the tier answers no trust dialog
    and the harness refuses an untrusted working directory (see
    seed_workspace_trust)."""
    if not SANDBOX:
        return None
    base = leg_state_dir(branch)
    config = base / "config"
    config.mkdir(parents=True, exist_ok=True)
    live = Path.home() / ".claude"
    for name in ("settings.json", "CLAUDE.md"):
        source = live / name
        if source.is_file():
            destination = config / name
            # the live layer holds store-backed files without the
            # owner-write bit, and shutil.copy2 propagates the mode of
            # its source: the copy of the first spawn of a branch lands
            # read-only, and every later spawn of the branch dies on
            # PermissionError at this line (issue 607). Remove the
            # destination first, whatever mode it holds, and copy the
            # content alone, so the copy lands writable on every spawn.
            destination.unlink(missing_ok=True)
            shutil.copyfile(source, destination)
    onboarding = Path.home() / ".claude.json"
    if onboarding.is_file() and not (config / ".claude.json").exists():
        # the onboarding state of the user as the base of a fresh leg
        # config, copied once and kept after, so the state that the
        # harness writes itself survives the release. The file sits
        # beside the config directory of the user, not inside it: the
        # harness reads <config>/.claude.json under CLAUDE_CONFIG_DIR
        # and ~/.claude.json without it (issue 607, the record of
        # 2026-11-21 14:10: the copy read ~/.claude/.claude.json, a
        # path that never exists, so no leg config ever gained the
        # onboarding state of the user)
        shutil.copy2(onboarding, config / ".claude.json")
    seed_workspace_trust(config, leg_worktree(branch))
    skills = live / "skills"
    if skills.is_dir() and not (config / "skills").exists():
        (config / "skills").symlink_to(skills)
    prepare_daemon_socket(str(config))
    return {
        "base": str(base),
        "config_dir": str(config),
        "agent_socket": str(base / "agent.sock"),
    }


def leg_worktree(branch: str) -> str:
    """The working directory of the session of one branch, as the harness
    canonicalizes it. The claim of the project tool builds the worktree at
    the branch with every slash as a hyphen under the project root, the
    spawn runs the session there, and the trust gate of the harness reads
    the record of exactly that path, so the dispatcher derives it the same
    way. The harness resolves the directory through the real path before it
    reads the record; a worktree that the first spawn of a branch has not
    created yet resolves through its deepest existing ancestor, which the
    created worktree then matches, because no symlink sits under the
    project root."""
    worktree = Path.home() / "projects" / PROJECT_DIR / branch.replace("/", "-")
    return os.path.realpath(worktree)


def seed_workspace_trust(config: Path, worktree: str) -> None:
    """Seed the workspace trust of one worktree into the harness state of
    the leg config, before the spawn (issue 607, the records of 2026-11-21
    14:10 and 14:44). A session of the tier answers no trust dialog, and
    the harness refuses an untrusted working directory in that mode, so
    the dispatcher writes the record that an accepted dialog would write:
    projects[worktree].hasTrustDialogAccepted, merged into the state the
    config holds, the same merge the harness applies itself. The seed runs
    on every spawn, because the harness rewrites the file beside a leg and
    a rewrite that predates the trust of the worktree leaves it untrusted
    again. It also covers the backup directory: the harness names the
    newest backup of a lost config file as the restore source, so a
    restore must land on a state that already holds the trust. A backup
    that holds no JSON object keeps its bytes, because the config file
    beside it carries the seed. The socket directory of the supervisor is
    the last piece of the runtime: the prepare rebuilds it and links it
    into the daemon root of the harness, so the attach of the view window
    reaches the supervisor across the namespace of the unit (see
    prepare_daemon_socket)."""
    paths = [config / ".claude.json"]
    paths += sorted((config / "backups").glob(".claude.json.backup.*"))
    for path in paths:
        state: dict = {}
        try:
            with open(path, encoding="utf-8") as handle:
                loaded = json.load(handle)
        except (OSError, ValueError):
            loaded = None
        if isinstance(loaded, dict):
            state = loaded
        elif path != paths[0]:
            continue
        projects = state.get("projects")
        if not isinstance(projects, dict):
            projects = {}
            state["projects"] = projects
        entry = projects.get(worktree)
        if not isinstance(entry, dict):
            entry = {}
            projects[worktree] = entry
        entry["hasTrustDialogAccepted"] = True
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2)
            handle.write("\n")


def agent_unit_properties(runtime: dict) -> list:
    """The -p entries of the agent unit of one leg (the review of pull
    request 615): the agent holds the push key alone, touches nothing but
    its socket, and answers no network address, so it runs under the same
    bounds as the leg unit wherever they bite — the whole tree read-only,
    every home hidden beside the leg state that carries its socket, no
    privileges, no syscalls beyond the service set, and no address at all.
    The agent never reads a file, so the leg state bind serves the socket
    alone."""
    return [
        "ProtectSystem=strict",
        "ProtectHome=tmpfs",
        "PrivateTmp=yes",
        "NoNewPrivileges=yes",
        "CapabilityBoundingSet=",
        "SystemCallFilter=@system-service",
        "IPAddressDeny=any",
        f"BindPaths={runtime['base']}",
        f"ReadWritePaths={runtime['base']}",
    ]


def start_leg_agent(unit: str, runtime: dict) -> bool:
    """Start the ssh agent of one leg and load the push key into it. The
    agent runs in its own transient unit under the bounds of
    agent_unit_properties, so the release stops it with one systemctl call
    and no pid bookkeeping. The key load retries, because the unit start
    returns before the agent binds its socket."""
    if not PUSH_KEY or not Path(PUSH_KEY).is_file():
        log.error("push key %s is missing, so a sandboxed leg cannot push", PUSH_KEY)
        return False
    command = [
        SYSTEMD_RUN,
        "--user",
        "--unit",
        unit,
        "--collect",
        "--quiet",
    ]
    for prop in agent_unit_properties(runtime):
        command += ["-p", prop]
    command += [SSH_AGENT_BIN, "-D", "-a", runtime["agent_socket"]]
    try:
        subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("agent unit of %s did not start: %s", unit, err)
        return False
    env = dict(os.environ)
    env["SSH_AUTH_SOCK"] = runtime["agent_socket"]
    for _ in range(20):
        try:
            result = subprocess.run(
                [SSH_ADD_BIN, PUSH_KEY],
                capture_output=True,
                text=True,
                timeout=10,
                env=env,
            )
        except (OSError, subprocess.SubprocessError) as err:
            log.error("ssh-add of the push key failed: %s", err)
            return False
        if result.returncode == 0:
            return True
        time.sleep(0.2)
    log.error("ssh-add of the push key never answered: the agent did not come up")
    return False


def git_ssh_command() -> str:
    """The ssh command of a sandboxed leg: no config file (-F /dev/null, so
    nothing of ~/.ssh applies), the user and port of the forge, the tailnet
    name of this host as the address (the rewrite of the remote URL names
    it), the host key pinned under the forge name through HostKeyAlias, and
    batch mode, so no prompt can hang a headless fetch."""
    return (
        f"ssh -F /dev/null -p {FORGE_SSH_PORT} -o User=git "
        f"-o HostKeyAlias={FORGE_HOST} -o StrictHostKeyChecking=yes "
        f"-o BatchMode=yes -o UserKnownHostsFile={FORGE_KNOWN_HOSTS}"
    )


def leg_unit_environment(runtime: dict) -> list:
    """The -E entries of the transient unit of a leg: the per-leg harness
    config directory, the agent socket with the ssh command and the remote
    rewrite that carry the git transport, and the PATH and TMUX_TMPDIR of
    the dispatcher, which a service unit does not inherit from its caller
    (systemd-run(1), --pipe): without them the spawn finds neither its
    tools nor the tmux socket of the view window."""
    environment = [
        f"CLAUDE_CONFIG_DIR={runtime['config_dir']}",
        f"SSH_AUTH_SOCK={runtime['agent_socket']}",
        f"GIT_SSH_COMMAND={git_ssh_command()}",
        "GIT_CONFIG_COUNT=1",
        f"GIT_CONFIG_KEY_0=url.ssh://git@{FORGE_SSH_HOST}/{REPO}.git.insteadOf",
        f"GIT_CONFIG_VALUE_0=ssh://git@{FORGE_HOST}/{REPO}.git",
    ]
    for name in ("PATH", "TMUX_TMPDIR"):
        value = os.environ.get(name, "")
        if value:
            environment.append(f"{name}={value}")
    return environment


def teardown_leg_runtime(entry, branch: str) -> None:
    """End the sandbox half of one leg after its session stopped: the
    supervisor of the leg (one instance per config directory) stops, so the
    cgroup of the transient unit empties and --collect removes the unit, and
    the agent unit stops with one systemctl call. The daemon stop speaks to
    the supervisor through the host-side link of the socket placement
    (issue 633), so the link goes after the stop, and the stop of the units
    follows the removal. An entry of the code before the tier holds none of
    the keys, so each step is optional."""
    config_dir = str((entry or {}).get("config_dir") or "")
    if config_dir:
        env = dict(os.environ)
        env["CLAUDE_CONFIG_DIR"] = config_dir
        try:
            subprocess.run(
                [CLAUDE, "daemon", "stop"],
                capture_output=True,
                text=True,
                timeout=60,
                env=env,
            )
        except (OSError, subprocess.SubprocessError) as err:
            log.warning("daemon stop of branch %s failed: %s", branch, err)
        remove_daemon_socket_link(config_dir)
    for unit in (entry or {}).get("units") or []:
        try:
            subprocess.run(
                [SYSTEMCTL_BIN, "--user", "stop", unit],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except (OSError, subprocess.SubprocessError) as err:
            log.warning("unit stop of %s failed: %s", unit, err)


def claude_env(entry) -> dict:
    """The environment that reaches the harness of one leg from outside its
    unit: every claude call of the dispatcher — the stop of a release, the
    liveness listing, the fallback session listing — must speak to the
    supervisor of that leg, and the config directory names it."""
    config_dir = str((entry or {}).get("config_dir") or "")
    env = dict(os.environ)
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    return env


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
    os.environ.get(
        "DISPATCHER_STATE_DIR", os.path.expanduser("~/.local/state/dispatcher")
    )
)

# a leg that started longer ago than this is treated as crashed, so a new
# event may start a fresh leg on the same branch (recovery after a crash)
INFLIGHT_TTL = int(os.environ.get("DISPATCHER_INFLIGHT_TTL", str(2 * 3600)))
# a red gate starts a nudge leg with a bound (issue #110): at most this many
# red-gate nudge legs per pull request while the gate stays red. The next red
# gate after the bound comments on the pull request and names the owner, and
# no further leg starts on its own. The bound stops a loop of push and fail.
REDGATE_LIMIT = int(os.environ.get("DISPATCHER_REDGATE_LIMIT", "2"))
# the wake command of the loop (issue #525): the first word of the final
# comment of a leg, the comment that releases the in-flight entries of its
# entity. The command takes no arguments and names no target: the released
# entry carries the routing. A released reviewer branch wakes the worker
# nudge of the same pull request; a released worker or nudge branch wakes
# the issue that the Refs keyword of the branch's open pull request names.
# The self-trigger rule narrows to this word: every other agent comment
# still starts nothing
WAKE_COMMAND = os.environ.get("DISPATCHER_WAKE_COMMAND", "/wake")
# the bound of the wake, the red-gate rule as the template (issue #525): at
# most this many agent wakes per entity pair, waker entity to woken entity,
# until a human act resets. A wake past the bound comments on the entity
# that carried the command, names the owner, sets the needs-owner label,
# and starts no leg. A human comment on either entity of the pair, or the
# closure of its pull request, clears the pair and removes the label. The
# count records a queued wake, not a spawned one
WAKE_LIMIT = int(os.environ.get("DISPATCHER_WAKE_LIMIT", "2"))
# the label of a thread that the loop stopped and a person must act on
# (issue #525): the dispatcher sets it when a wake bound trips, and the
# human act that resets the bound removes it
NEEDS_OWNER_LABEL = os.environ.get("DISPATCHER_NEEDS_OWNER_LABEL", "needs-owner")
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
# the answer of a list verb to an empty set (issue #421): tea prints this
# sentence with exit 0, not JSON, for a comments read of an entity that holds
# no comment, while review-comments answers an empty JSON array for the same
# empty set. The first reviewer leg always meets the sentence, because the
# first comment of a factory pull request is the verdict of its reviewer
EMPTY_SET_SENTENCE = "No comments found"
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

# the Refs keyword alone (issue #525): the wake target of a released worker
# or nudge branch is the issue that a Refs keyword names, never the issue of
# a closing keyword. A closing keyword names the work of the same branch,
# while Refs names the next stage of a composition flow
REFS_KEYWORD = re.compile(r"\brefs?\s+#(\d+)", re.IGNORECASE)

# the readiness gate (issue #356, L2): a worker leg starts only on an issue
# whose brief answers each ambiguity class of the readiness protocol of the
# factory skill, or marks the class not applicable with its answerer named.
# The answers live in the body of the issue, one plain line per class:
#     Readiness A: <answer>
#     Readiness C: not applicable by <login>
# A not-applicable that names no answerer counts as unanswered, because the
# record must hold who dismissed the class (issue #356, L12)
# Every whitespace run of the pattern stops at the line end (issue #409), so
# a match never reaches into the line below: an empty Readiness line holds
# no match, and it counts as its own unanswered class
READINESS_LINE = re.compile(
    r"^[^\S\n]*readiness[^\S\n]+([a-f])[^\S\n]*:[^\S\n]*(\S.*?)[^\S\n]*$",
    re.IGNORECASE | re.MULTILINE,
)
# A whole answer of the word seeded counts as no answer (issue #566): the
# word names the seeded empty line of the protocol, so the gate reads the
# form of that one word and no other content of an answer
SEEDED_ANSWER = re.compile(r"^seeded$", re.IGNORECASE)
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


def is_loop_command(body: str) -> bool:
    """True when the first word of the body is the loop command. The prose of
    the answer may sit on the same line, on later lines, or nowhere: every
    whitespace run separates words, so a newline after the command separates
    like a space (the silent delivery of issue #387). A word that only starts
    with the command, for example /loopnow, is no command."""
    words = body.split()
    return bool(words) and words[0].lower() == COMMAND_PREFIX.lower()


def is_watch_command(body: str) -> bool:
    """True when the first word of the body is the watch command (issue
    #470, option C; the split into its own command is issue #525): the
    comment starts one watched leg, and the ruling prose may sit on the same
    line or on later lines, the same grammar as the loop command. A word
    that only starts with it, for example /watching, is prose. The word
    window behind the loop command is prose since the split: /loop window
    starts a plain leg."""
    words = body.split()
    return bool(words) and words[0].lower() == WATCH_COMMAND.lower()


def is_wake_command(body: str) -> bool:
    """True when the first word of the body is the wake command (issue #525).
    The word rides the final comment of a leg, the comment that releases the
    in-flight entries of its entity, and the prose of the comment may sit on
    the same line or on later lines, the same grammar as the loop command.
    A word that only starts with it, for example /wakeup, is prose, and no
    wake fires."""
    words = body.split()
    return bool(words) and words[0].lower() == WAKE_COMMAND.lower()


def refs_issue(body: str):
    """Return the issue number that a Refs keyword names, or None. The wake
    of a released worker or nudge branch reads the Refs keyword of the open
    pull request of its branch (issue #525), never a closing keyword."""
    if not body:
        return None
    match = REFS_KEYWORD.search(body)
    return int(match.group(1)) if match else None


def as_int(value):
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- events


def enqueue(
    delivery: str,
    kind: str,
    entity: int,
    branch: str,
    issue,
    reason: str,
    head: str = "",
    cause: str = "",
    windowed: bool = False,
) -> bool:
    """Write one event file, named after the delivery ID. The file is the
    delivery record: while it sits in events/, processed/, or failed/, the
    same delivery is skipped. A delivery for a branch that already has a
    pending event is recorded as superseded and spawns nothing: one pending
    event per branch is enough, because a leg reads its entity fresh. The
    cause is the opening sentence of the prompt of a nudge leg: it says what
    started the leg. The windowed flag (issue #470) reaches the spawn: the
    leg waits at its permission prompts, and the owner answers them."""
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
        "windowed": windowed,
    }
    with state_lock:
        for pending in state_path("events").glob("*.json"):
            if load_json(pending, {}).get("branch") == branch:
                event["superseded"] = True
                store_json(state_path("processed", name + ".json"), event)
                log.info(
                    "branch %s already has a pending event, delivery %s superseded",
                    branch,
                    delivery,
                )
                return False
        store_json(state_path("events", name + ".json"), event)
    log.info("queued %s leg for entity %s branch %s (%s)", kind, entity, branch, reason)
    return True


def run_named_ref(run: dict):
    """The pull request number and the branch name that a workflow run
    delivery names in run.prettyref, as (number, branch). The field holds
    #<number> for a run of a pull request and the short branch name for a
    run of a branch (the PrettyRef rule of the forge family source; the
    recorded delivery of issue #228 shows the field of this forge). A
    payload that holds no field, or a malformed reference, names nothing,
    and its delivery falls back to the sha scan."""
    ref = str(run.get("prettyref") or "")
    if not ref.startswith("#"):
        return None, ref
    number = as_int(ref[1:])
    return (number, "") if number is not None else (None, "")


def handle_payload(event_type: str, payload: dict, delivery: str) -> None:
    """Turn one forge event into zero or one queued event. The self-trigger
    rule lives here: a comment of the agent login never spawns a leg, but
    it releases the in-flight entries of its entity, because the prompts
    make the final comment the declared end of a leg."""
    # the workflow run delivery carries its repository inside the run
    # object, and nothing at the top level besides the action word (the
    # recorded delivery of issue #228)
    payload_run = payload.get("run")
    run = payload_run if isinstance(payload_run, dict) else {}
    repository = payload.get("repository") or run.get("repository") or {}
    if repository.get("full_name") != REPO:
        log.info("event of repository %s, ignore", repository.get("full_name"))
        return
    sender = ((payload.get("sender") or {}).get("login") or "").lower()

    if event_type == "issue_comment":
        issue = payload.get("issue") or {}
        number = as_int(issue.get("number"))
        comment = (payload.get("comment") or {}).get("body") or ""
        if sender == AGENT_LOGIN:
            # the self-trigger rule narrows here (issue #525): every comment
            # of the agent login still starts nothing, but the one comment
            # that releases the in-flight entries of its entity is the final
            # comment of a leg, and its first word may be the wake command
            if number is not None:
                freed = release_entity(number)
                if freed and is_wake_command(comment):
                    wake_released(number, freed, delivery)
            return
        if number is None or issue.get("state") != "open":
            return
        # a human comment on an entity is the human act that resets every
        # wake bound of a pair which names the entity (issue #525). The
        # delivery carries the label state of the entity, so the reset
        # writes no label removal when the entity holds none (issue #582)
        wake_reset(number, NEEDS_OWNER_LABEL in label_names(issue.get("labels")))
        if issue.get("pull_request") is not None:
            # a human comment on a pull request: a command continues the
            # work on the branch of that pull request, as a nudge leg. The
            # watch command rules the watched variant of the start (issues
            # #516 and #525). A plain comment is prose and starts nothing,
            # unless the pull request holds the needs-owner label: the loop
            # stopped that thread, and the prose of a person continues it
            # (issue #525)
            head = pr_head(number)
            if not head.startswith(AI_PREFIX):
                return
            if is_loop_command(comment) or is_watch_command(comment):
                enqueue(
                    delivery,
                    "nudge",
                    number,
                    head,
                    None,
                    "command comment on the pull request",
                    head,
                    windowed=is_watch_command(comment),
                )
                return
            if NEEDS_OWNER_LABEL in label_names(issue.get("labels")):
                cause = (
                    f"A person answered on pull request {number}, which a bound of the "
                    "loop had stopped. Address the cause that the bound comment named."
                )
                enqueue(
                    delivery,
                    "nudge",
                    number,
                    head,
                    None,
                    "plain comment on a needs-owner pull request",
                    head,
                    cause,
                )
            return
        if is_loop_command(comment) or is_watch_command(comment):
            queue_gated_issue(delivery, number, comment)
            return
        if NEEDS_OWNER_LABEL in label_names(issue.get("labels")):
            queue_held_issue(delivery, number)
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
            # the closed pull request is the human act that ends the wake
            # bounds of every pair which names it (issue #525). The closure
            # reads the label state of the pull request, because this
            # receiver reads no label field of a pull_request delivery, and
            # the reset writes the removal only when it holds the label
            # (issue #582)
            wake_reset(number, NEEDS_OWNER_LABEL in pull_labels(number))
            return
        if payload.get("action") not in ("opened", "synchronized"):
            return
        link = linked_issue(pull.get("body") or "")
        record_link(number, link)
        enqueue(
            delivery,
            "reviewer",
            number,
            REVIEWER_BRANCH.format(n=number),
            link,
            "pull request " + str(payload.get("action")),
            head,
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
        # recorded delivery of issue #228 holds the body only. The run
        # object also names its pull request or its branch, so the gate
        # mapping resolves from the payload itself (issue #583).
        number, branch = run_named_ref(run)
        gate_delivery(
            str(run.get("status") or "").lower(),
            str(run.get("commit_sha") or ""),
            delivery,
            number,
            branch,
        )
        return


def pr_head(number: int) -> str:
    """Read the head branch of a pull request with tea. Used only for a
    human comment on a pull request, where the payload carries no head."""
    try:
        out = subprocess.run(
            [TEA, "pulls", str(number), "--output", "json", "--repo", REPO],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
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
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
        ).stdout
        return str(json.loads(out).get("headSha") or "")
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s: %s", number, err)
        return ""


def open_pulls() -> list:
    """The open pull requests of the repository, as (number, head) pairs."""
    try:
        out = subprocess.run(
            [
                TEA,
                "pulls",
                "list",
                "--state",
                "open",
                "--fields",
                "index,head",
                "--output",
                "json",
                "--repo",
                REPO,
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
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
    commit of a branch match nothing here. This scan is the fallback of the
    gate mapping (issue #583): it pays one head-sha read per open ai/ pull
    request, because the list view of the pull requests carries no sha, so
    a delivery that names its pull request or its branch resolves through
    open_ai_pull_by_ref instead."""
    for number, head in open_pulls():
        if not head.startswith(AI_PREFIX):
            continue
        if pull_head_sha(number) == sha:
            return number, head
    return None, ""


def open_ai_pull_by_ref(number, branch: str):
    """The open ai/ pull request that a gate delivery names, as (number,
    head), or (None, ""). A workflow run delivery names its pull request or
    its branch (issue #583), so the mapping resolves through the listing of
    the open pull requests alone: one tea call, whatever the count of open
    ai/ pull requests is, and no per-pull head-sha read. A named pull
    request or branch that no open ai/ pull request holds matches nothing
    here, so the daily run of main concludes from the listing alone."""
    if number is None and not branch:
        return None, ""
    for found, head in open_pulls():
        if not head.startswith(AI_PREFIX):
            continue
        if (number is not None and found == number) or (branch and head == branch):
            return found, head
    return None, ""


def open_ai_pull_on_branch(branch: str):
    """The open pull request whose head branch is branch, as (number, head),
    or (None, "")."""
    for number, head in open_pulls():
        if head == branch:
            return number, head
    return None, ""


def pull_labels(number: int) -> list:
    """The label names of a pull request, or the empty list. The needs-owner
    continuation of the poll path needs them (issue #525): the webhook
    payload carries the labels of the issue object, and the poll reads them
    from the pull request before the reset of the same comment removes the
    label."""
    try:
        pull = tea_read("pulls", str(number))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s for its labels: %s", number, err)
        return []
    return label_names(pull.get("labels") if isinstance(pull, dict) else None)


def issue_body(number: int):
    """The body of an issue, read with tea, or None when the read fails. The
    readiness gate needs the body before a worker leg starts. A failed read
    fails open, like every tea read of the receiver: the gate then runs on
    the next trigger, and a payload fetch that fails too sends the leg to
    read the issue itself."""
    try:
        issue = tea_read("issues", str(number))
        return str((issue if isinstance(issue, dict) else {}).get("body") or "")
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read issue %s for the readiness gate: %s", number, err)
        return None


def readiness_report(body: str) -> tuple[list[str], list[str]]:
    """The unanswered classes of a brief, as (missing, anonymous). A class
    counts as answered when one line of the body names it with a non-empty
    answer. A whole answer of the word seeded counts as no answer, because
    the word names the seeded empty line of the protocol (issue #566). The
    first answered line of a class counts. An empty Readiness line holds no
    match, so it counts as its own unanswered class, and it captures no
    text of the line below it (issue #409). A not-applicable that names no
    answerer counts as anonymous, because the record must hold who
    dismissed the class (issue #356, L12)."""
    answered = {}
    for letter, value in READINESS_LINE.findall(body or ""):
        if SEEDED_ANSWER.match(value):
            continue
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


def post_comment(entity: int, body: str) -> None:
    """One comment on an entity, through the only write path of the
    dispatcher that talks to a thread. A failure logs and returns: the loop
    keeps running, and the next event carries the state again."""
    log.info("comment on entity %s: %s", entity, body[:200])
    try:
        subprocess.run(
            [TEA, "comments", "add", str(entity), body, "--repo", REPO],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.error("could not comment on entity %s: %s", entity, err)


def label_write(entity: int, flag: str, label: str) -> None:
    """One label change on an entity (issue #525), through tea issues edit.
    A pull request shares the index space of the issues, so the verb serves
    both shapes. A failure logs and returns: the label is a visibility mark,
    the comment beside it is the record, so a failed write never blocks the
    loop."""
    try:
        result = subprocess.run(
            [TEA, "issues", "edit", str(entity), flag, label, "--repo", REPO],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("label change on entity %s failed: %s", entity, err)
        return
    if result.returncode != 0:
        log.warning(
            "label change on entity %s answered %s: %s",
            entity,
            result.returncode,
            (result.stderr or "").strip()[:200],
        )


def set_needs_owner(entity: int) -> None:
    label_write(entity, "--add-labels", NEEDS_OWNER_LABEL)


def clear_needs_owner(entity: int) -> None:
    label_write(entity, "--remove-labels", NEEDS_OWNER_LABEL)


def park_readiness(number: int, missing: list[str], anonymous: list[str]) -> None:
    """Park an issue whose brief is not ready (issue #356, L2, decision D10
    of issue #350): one comment on the issue names each unanswered class,
    asks one question, and names the blocked step. No leg starts. The park
    comment is the answer of the loop, and the body of the issue stays the
    record: the gate writes no state of its own (decision D13)."""
    findings = [
        f"{letter.upper()} ({READINESS_CLASSES[letter]}): no Readiness answer in the body of this issue"
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
        "starts when every class A to F holds an answer or a named not-applicable. A new /loop "
        "comment on this issue requeues the leg."
    )
    log.error("issue %s parked, unanswered classes: %s", number, " ".join(findings))
    post_comment(number, body)


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


def queue_gated_issue(delivery: str, number: int, comment: str = "") -> None:
    """Queue the leg for one command comment on an issue, by the state of
    the branch (issue #110). The watch command rules the watched variant of
    the start (issues #470 and #525): the leg of this start waits at its
    permission prompts, whatever its kind."""
    windowed = is_watch_command(comment)

    def cause(issue_number: int, linked: int) -> str:
        return (
            f"A person asked for more work in a comment on issue {issue_number}, "
            f"and the branch of that issue already holds pull request {linked}."
        )

    queue_issue_leg(
        delivery,
        number,
        "gated issue comment",
        cause,
        windowed,
    )


def queue_held_issue(delivery: str, number: int) -> None:
    """Queue the leg for one plain human comment on an issue that holds the
    needs-owner label (issue #525). The loop stopped the thread, the label
    marks the stop, and the prose of a person continues it: the human
    surface stays a conversation where the loop waits for one. The wake
    reset of the same comment clears the bound and removes the label
    before this queue runs."""

    def cause(issue_number: int, linked: int) -> str:
        return (
            f"A person answered on issue {issue_number}, which a bound of the loop "
            f"had stopped, and the branch of that issue already holds pull request "
            f"{linked}."
        )

    queue_issue_leg(delivery, number, "plain comment on a needs-owner issue", cause)


def queue_issue_leg(
    delivery: str,
    number: int,
    reason: str,
    nudge_cause,
    windowed: bool = False,
) -> bool:
    """Queue the leg for one start on an issue, by the state of the branch
    (issue #110). The worker leg serves a branch that holds no open pull
    request: the worker prompt tells the leg to open one, and the readiness
    gate runs first, so an issue whose brief answers no class is parked and
    queues nothing. The nudge leg continues the open pull request of the
    branch, because the forge refuses a second pull request on one branch.
    nudge_cause builds the opening sentence of the nudge prompt from the
    issue number and the pull request number. Returns True when a leg was
    queued, and False when the start parked the issue or superseded."""
    branch = WORKER_BRANCH.format(n=number)
    linked, head = open_ai_pull_on_branch(branch)
    if linked is None:
        if not readiness_gate(number):
            return False
        return enqueue(
            delivery,
            "worker",
            number,
            branch,
            None,
            reason,
            windowed=windowed,
        )
    return enqueue(
        delivery,
        "nudge",
        linked,
        branch,
        None,
        reason,
        head,
        nudge_cause(number, linked),
        windowed,
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

    def __exit__(self, *_exc) -> None:
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
    # show current against the origin of the serving trunk (issue #100)
    if not refresh_clone():
        move_event(path, "failed")
        report_stale_base(kind, entity, branch)
        return True
    if kind == "reviewer":
        prepare_review_branch(branch, str(event.get("head_branch") or ""))
    code, envelope, runtime = spawn_leg(
        kind,
        entity,
        branch,
        event.get("issue"),
        event.get("cause"),
        bool(event.get("windowed")),
    )
    if code == 0:
        data = (envelope or {}).get("data") or {}
        take_slot(
            branch,
            str(data.get("session") or ""),
            str(data.get("session_id") or ""),
            entity,
            bool(event.get("windowed")),
            runtime,
        )
        # the session record of the branch (issue #524): the envelope of the
        # latest spawn names the transcript UUID that a later worker or
        # nudge leg of the branch resumes, and the worktree its transcript
        # sits under. The record survives the release of the in-flight
        # entry below, so it lands before the event leaves the spool. The
        # config directory of the tier rides the same record, so the resume
        # of a branch finds the transcript in its own harness instance.
        record_session(
            branch,
            str(data.get("session_uuid") or ""),
            str(data.get("worktree") or ""),
            bool(event.get("windowed")),
            runtime,
        )
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
    TTL blocks the spawn while its session lives: the sweep asks the harness
    for the state of the recorded session, and a session that the harness
    reports ended releases its entry at once, before the TTL (issue #605).
    A listing that fails, names no state, or names no matching session
    changes nothing, so the TTL stays the backstop. An older entry is a
    crashed leg and is dropped."""
    with state_lock:
        entry = inflight().get(branch)
        if entry is None:
            return True
        expired = time.time() - float(entry.get("since", 0)) >= INFLIGHT_TTL
    if not expired and not leg_is_dead(entry):
        return False
    if not expired:
        log.info(
            "the session of branch %s ended with no comment, release it",
            branch,
        )
    release_inflight(branch)
    return True


def leg_is_dead(entry: dict) -> bool:
    """True when the harness reports the session of one in-flight entry
    ended (issue #605). A plain leg ends with the turn, so `done`, `failed`,
    and `stopped` all name a leg that will post no comment. A windowed leg
    holds on `done`: its park question waits for the answer of the owner,
    and a session at that wait reads `done` (issue #505). An entry with no
    windowed mark predates the mark and names no kind, so `done` holds it
    too: a windowed leg of the code before the mark parks at a wait that
    reads `done`, and the first sweep of the new code must not release it.
    `failed` and `stopped` name a session that ended of either kind, so
    they release every entry. An entry without a session id predates the
    envelope change, and a read that answers no state word is unknown:
    both keep the entry, and the TTL stays their backstop."""
    session_id = str(entry.get("session_id") or "")
    if not session_id:
        return False
    state = session_state(session_id, entry)
    if not state:
        return False
    windowed = entry.get("windowed")
    if windowed is None or windowed:
        # a windowed leg, or an entry with no mark: done holds both, the
        # park wait of the first and the unknown kind of the second
        return state in ("failed", "stopped")
    return state in ("done", "failed", "stopped")


def take_slot(
    branch: str,
    session: str,
    session_id: str,
    entity: int,
    windowed: bool = False,
    runtime=None,
) -> None:
    with state_lock:
        state = inflight()
        state[branch] = {
            "entity": entity,
            "session": session,
            "session_id": session_id,
            "windowed": windowed,
            "since": int(time.time()),
        }
        if isinstance(runtime, dict):
            state[branch]["config_dir"] = runtime.get("config_dir") or ""
            state[branch]["units"] = runtime.get("units") or []
        store_json(state_path("inflight.json"), state)


def release_inflight(branch: str) -> None:
    with state_lock:
        state = inflight()
        entry = state.pop(branch, None)
        if entry is not None:
            store_json(state_path("inflight.json"), state)
    if entry is not None:
        stop_session(entry.get("session"), entry.get("session_id"), branch, entry)


def release_entity(entity: int) -> list:
    """Free every in-flight entry whose entity matches, and return the freed
    entries as (branch, entry) pairs. A comment of the agent login on an
    entity is the declared end of its leg, so the entry no longer blocks the
    next event of that entity. The TTL stays the backstop for a leg that
    crashed without a comment. The caller reads the freed entries for the
    wake rule (issue #525): only the comment that releases an entry is the
    final comment of a leg, so only that comment may wake the next leg."""
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
        stop_session(entry.get("session"), entry.get("session_id"), branch, entry)
    return free


def background_sessions(entry=None) -> list[tuple[str, str]]:
    """The background sessions of the user, as (id, name) pairs, read with
    `claude agents --json`. The stop of a release names the recorded id of
    its session (issue #208), so this read serves only the fallback for an
    in-flight entry that predates the id: it bridges the session name that
    an old spawn envelope recorded and the stop call that ends the session
    (issue #144). An entry of the tier names the config directory of its
    leg, and the listing runs against that harness instance (claude_env)."""
    try:
        result = subprocess.run(
            [CLAUDE, "agents", "--json"],
            capture_output=True,
            text=True,
            timeout=60,
            env=claude_env(entry),
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("could not list the background sessions: %s", err)
        return []
    if result.returncode != 0:
        log.info(
            "claude agents --json answered %s: %s",
            result.returncode,
            (result.stderr or "").strip()[:200],
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


def session_state(session_id: str, entry=None) -> str:
    """The state word of one background session, read with
    `claude agents --json --all`. The listing of the harness names one state
    word per background session — `working`, `blocked`, `done`, `failed`, or
    `stopped` — and the harness docs name this listing the supported way to
    read the state of a session from a script (code.claude.com/docs, agent
    view, List sessions as JSON). The `--all` form keeps sessions whose task
    ended in the listing, so a dead leg stays readable. A call that fails,
    prints no JSON list, or names no matching entry answers "", and the
    caller treats "" as unknown: a failed read must not release a live leg.
    The entry names the config directory of its leg under the tier, and the
    listing runs against that harness instance (claude_env)."""
    try:
        result = subprocess.run(
            [CLAUDE, "agents", "--json", "--all"],
            capture_output=True,
            text=True,
            timeout=60,
            env=claude_env(entry),
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("could not list the sessions for the liveness read: %s", err)
        return ""
    if result.returncode != 0:
        log.info(
            "claude agents --json --all answered %s: %s",
            result.returncode,
            (result.stderr or "").strip()[:200],
        )
        return ""
    try:
        listed = json.loads(result.stdout or "")
    except ValueError:
        log.warning("claude agents --json --all printed no json")
        return ""
    if not isinstance(listed, list):
        log.warning("claude agents --json --all printed no list")
        return ""
    for item in listed:
        if isinstance(item, dict) and str(item.get("id") or "") == session_id:
            return str(item.get("state") or "")
    return ""


def stop_session(session, session_id, branch: str, entry=None) -> None:
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
    session ended already. The entry of the tier names the harness instance
    of the leg, so both the stop and the fallback listing reach it, and the
    release ends the sandbox half of the leg after the session stopped
    (teardown_leg_runtime)."""
    if session_id:
        ids = [str(session_id)]
    elif session:
        ids = [
            listed_id
            for listed_id, name in background_sessions(entry)
            if name == str(session)
        ]
        if not ids:
            log.info(
                "no background session named %s for branch %s, nothing to stop",
                session,
                branch,
            )
            teardown_leg_runtime(entry, branch)
            return
    else:
        teardown_leg_runtime(entry, branch)
        return
    for listed_id in ids:
        stop_by_id(listed_id, branch, entry)
    teardown_leg_runtime(entry, branch)


def stop_by_id(session_id: str, branch: str, entry=None) -> None:
    try:
        result = subprocess.run(
            [CLAUDE, "stop", session_id],
            capture_output=True,
            text=True,
            timeout=60,
            env=claude_env(entry),
        )
    except (OSError, subprocess.SubprocessError) as err:
        log.warning("could not stop the session of branch %s: %s", branch, err)
        return
    if result.returncode != 0:
        log.info(
            "claude stop of session %s (branch %s) answered %s: %s",
            session_id,
            branch,
            result.returncode,
            (result.stderr or "").strip()[:200],
        )


def record_link(pr: int, issue) -> None:
    with state_lock:
        links = load_json(state_path("links.json"), {})
        links[str(pr)] = issue
        store_json(state_path("links.json"), links)


# -------------------------------------------------------- the session record


def branch_sessions() -> dict:
    return load_json(state_path("sessions.json"), {})


def record_session(
    branch: str, uuid: str, worktree: str, windowed: bool, runtime=None
) -> None:
    """Write the session record of one branch (issue #524): the latest
    transcript UUID of the branch, the worktree it runs in, and whether a
    windowed leg holds it. The record is loop mechanics state in the family
    of inflight.json and redgate.json, beside links.json, and it survives
    the release of the in-flight entry, so a later leg of the branch can
    resume the session. An envelope without a uuid answers no resume handle:
    the entry of the branch ends, because the record names the latest
    transcript alone and a stale entry would resume a session that a whole
    leg of work predates. The config directory of the tier rides the record,
    so a resume reads the transcript from the harness instance of the leg."""
    with state_lock:
        state = branch_sessions()
        if uuid:
            state[branch] = {
                "uuid": uuid,
                "windowed": windowed,
                "worktree": worktree,
            }
            if isinstance(runtime, dict) and runtime.get("config_dir"):
                state[branch]["config_dir"] = runtime["config_dir"]
            else:
                state[branch].pop("config_dir", None)
        else:
            state.pop(branch, None)
        store_json(state_path("sessions.json"), state)


def transcript_exists(worktree: str, uuid: str, config_dir: str = "") -> bool:
    """True when the harness holds the transcript of one session. The
    transcripts of a working directory sit at
    ~/.claude/projects/<name>/<session-id>.jsonl, where <name> is the path
    with every non-alphanumeric character as a hyphen (the harness docs,
    Where transcripts are stored; the same rule as TranscriptExists of the
    project tool). A leg of the tier holds its transcripts under the config
    directory of its branch, so that root replaces the home of the user. A
    name over 200 characters takes a truncated form with a hash suffix that
    this function does not derive: it answers False, and the caller starts a
    fresh leg. A transcript that the 30-day cleanup removed answers False
    the same way."""
    if not worktree or not uuid:
        return False
    name = re.sub(r"[^A-Za-z0-9]", "-", worktree)
    if not 0 < len(name) <= 200:
        return False
    root = Path(config_dir) if config_dir else Path.home() / ".claude"
    try:
        return (root / "projects" / name / (uuid + ".jsonl")).is_file()
    except OSError:
        return False


def resume_uuid(branch: str) -> str:
    """The UUID that a worker or nudge leg of this branch resumes, or "". A
    record exists only after a spawn of the branch answered its envelope
    (issue #524). A record of a windowed leg resumes nothing: a resumed
    session keeps its launch flags, so the waiting mode of a windowed launch
    would hang an unattended leg that the owner does not watch. A record
    whose transcript is gone resumes nothing, so the leg starts fresh with
    the full brief."""
    entry = branch_sessions().get(branch)
    if not isinstance(entry, dict):
        return ""
    uuid = str(entry.get("uuid") or "")
    if entry.get("windowed") or not transcript_exists(
        str(entry.get("worktree") or ""), uuid, str(entry.get("config_dir") or "")
    ):
        return ""
    return uuid


# ------------------------------------------------------------- red gate


def redgate() -> dict:
    return load_json(state_path("redgate.json"), {})


def gate_delivery(
    state: str, sha: str, delivery: str, number=None, branch: str = ""
) -> None:
    """The shared rule of every gate delivery, today the status event and
    the workflow run event. A red gate on the head of an open ai/ pull
    request starts one nudge leg, with the bound of gate_red (issue #110).
    A green gate on the head ends the red episode. A conclusion of any
    other state, or a delivery that no open ai/ pull request answers, is
    ignored, so the daily run of main spawns nothing. The mapping first
    uses the fields of the delivery itself (issue #583): a delivery that
    names its pull request or its branch resolves through one listing of
    the open pull requests, and a delivery that names neither keeps the sha
    scan, which pays one head-sha read per open ai/ pull request. The
    named form trusts the name over the commit, so a stale conclusion of an
    older commit of the named pull request reaches gate_red, and its bound
    limits what it starts (machine decision 31 of the README)."""
    if not sha or state not in (RED_STATE, GREEN_STATE):
        return
    if number is not None or branch:
        pull, head = open_ai_pull_by_ref(number, branch)
    else:
        pull, head = open_ai_pull_by_sha(sha)
    if pull is None:
        return
    if state == GREEN_STATE:
        gate_green(pull)
        return
    gate_red(pull, head, sha, delivery)


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
    if enqueue(
        delivery,
        "nudge",
        number,
        head,
        None,
        "red gate on the pull request head",
        head,
        cause,
    ):
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
    post_comment(number, body)
    # the same mark as a wake trip (issue #525): the thread waits for a
    # person, and the plain prose of that person continues it
    set_needs_owner(number)


# ------------------------------------------------------------------ wake


def wakegate() -> dict:
    return load_json(state_path("wakegate.json"), {})


def pull_body(number: int) -> str:
    """The body of a pull request, or the empty string when the read fails.
    The Refs reader of the wake needs it (issue #525). A failed read makes
    the wake find no target, and the no-target comment names the pull
    request, so the failure stays visible."""
    try:
        pull = tea_read("pulls", str(number))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("could not read pull request %s for the wake: %s", number, err)
        return ""
    return str(pull.get("body") or "") if isinstance(pull, dict) else ""


def wake_released(entity: int, freed: list, delivery: str) -> None:
    """Derive the wake target from the entries that the final comment
    released (issue #525). A released reviewer branch names the worker nudge
    of the same pull request: the verdict continuation. A released worker or
    nudge branch names the issue of the Refs keyword of the branch's open
    pull request: the composition handoff. A release that freed a reviewer
    entry beside a worker entry rules by the reviewer entry, because the
    worker entry of the same release is the debris of a crashed leg. One
    wake per comment: no path here queues a second event."""
    if any(branch.startswith(REVIEWER_PREFIX) for branch, _ in freed):
        wake_verdict(entity, delivery)
        return
    branches = [branch for branch, _ in freed if not branch.startswith(REVIEWER_PREFIX)]
    if branches:
        wake_handoff(entity, branches[0], delivery)


def wake_verdict(pr: int, delivery: str) -> None:
    """The verdict continuation (issue #525): wake the worker nudge of the
    pull request whose reviewer verdict released its branch. The pair of the
    bound is the pull request on both sides, so a verdict-and-fix cycle on
    one pull request spends one bound."""
    head = pr_head(pr)
    if not head.startswith(AI_PREFIX):
        report_no_wake(
            pr, f"the pull request names no head branch that starts with {AI_PREFIX}"
        )
        return
    if not wake_allowed(pr, pr):
        return
    cause = (
        f"The reviewer verdict on pull request {pr} holds blocking findings, and its "
        "final comment woke this leg. Address each blocking finding by name."
    )
    if enqueue(
        delivery,
        "nudge",
        pr,
        head,
        None,
        "wake of a reviewer verdict",
        head,
        cause,
    ):
        wake_count(pr, pr)


def wake_handoff(entity: int, branch: str, delivery: str) -> None:
    """The composition handoff (issue #525): wake the issue that the Refs
    keyword of the open pull request of the released branch names. A closing
    keyword names the work of the same branch, so it wakes nothing (issue
    #356, L7). The target queues through the branch-state rule of a human
    comment on an issue, readiness gate included."""
    linked, _head = open_ai_pull_on_branch(branch)
    if linked is None:
        report_no_wake(entity, f"branch {branch} holds no open pull request")
        return
    target = refs_issue(pull_body(linked))
    if target is None:
        report_no_wake(
            entity,
            f"the body of pull request {linked} names no issue with a Refs keyword",
        )
        return

    def cause(issue_number: int, pull: int) -> str:
        return (
            f"The final comment of the leg on entity {entity} woke this leg: "
            f"pull request {pull} names issue {issue_number} with a Refs keyword."
        )

    if not wake_allowed(entity, target):
        return
    if queue_issue_leg(delivery, target, "wake of a composition handoff", cause):
        wake_count(entity, target)


def wake_allowed(waker: int, target: int) -> bool:
    """True when the pair of waker and target holds an unspent wake
    (issue #525), the red-gate rule as the template: at most WAKE_LIMIT
    agent wakes per entity pair until a human act resets. A wake past the
    bound escalates once, with one comment that names the owner and one
    needs-owner label, and every later wake of the pair stays quiet."""
    key = f"{waker}-{target}"
    with state_lock:
        state = wakegate()
        entry = state.get(key) or {}
        if int(entry.get("wakes") or 0) < WAKE_LIMIT:
            return True
        if entry.get("escalated"):
            return False
        entry["escalated"] = True
        state[key] = entry
        store_json(state_path("wakegate.json"), state)
        escalate = True
    if escalate:
        report_wake_bound(waker, target)
    return False


def wake_count(waker: int, target: int) -> None:
    """Record one queued wake of the pair (issue #525). The count records
    the queue, not the spawn, so the bound stays honest about how often the
    loop tried, the same rule as the red gate."""
    with state_lock:
        state = wakegate()
        key = f"{waker}-{target}"
        entry = state.get(key) or {}
        entry["wakes"] = int(entry.get("wakes") or 0) + 1
        state[key] = entry
        store_json(state_path("wakegate.json"), state)


def wake_reset(entity: int, held: bool) -> None:
    """The human act that resets (issue #525): a human comment on an entity,
    or the closure of its pull request, clears the bound of every pair that
    names the entity and removes the needs-owner label of each waker, so the
    next wake of each cleared pair gets a fresh bound and no thread shows an
    open stop after the person acted. The entity itself loses its label only
    when it holds one: the caller passes the label state from the delivery
    or the listing that carried the comment, so a human comment on an entity
    that never stopped writes no label change (issue #582). The removal of
    each waker stays unconditional, because the wakegate state cannot see a
    label that a red-gate trip set on a waker, and a pair names the entity
    only after a wake spent it."""
    with state_lock:
        state = wakegate()
        keys = [key for key in state if str(entity) in key.split("-")]
        wakers = [int(key.split("-")[0]) for key in keys]
        for key in keys:
            state.pop(key)
        if keys:
            store_json(state_path("wakegate.json"), state)
    for waker in wakers:
        clear_needs_owner(waker)
    if held:
        clear_needs_owner(entity)


def report_wake_bound(waker: int, target: int) -> None:
    body = (
        f"dispatcher: the wake from entity {waker} to entity {target} passed its "
        f"bound of {WAKE_LIMIT} agent wakes without a human act, so no further leg "
        "starts on its own. jracon: this needs your decision."
    )
    log.error("wake past the bound: %s", body)
    post_comment(waker, body)
    set_needs_owner(waker)


def report_no_wake(entity: int, reason: str) -> None:
    body = (
        f"dispatcher: the final comment of the leg on entity {entity} began with "
        f"{WAKE_COMMAND}, but no wake target derives from it: {reason}. No leg woke. "
        f"The word {WAKE_COMMAND} belongs on the final comment of a leg whose "
        "continuation the loop can derive: a reviewer verdict on a pull request "
        "wakes its worker, and a final comment wakes the issue that the Refs keyword "
        "of the open pull request of its branch names."
    )
    log.error("wake without a target: %s", body)
    post_comment(entity, body)


# ------------------------------------------------------------- spawning


def refresh_clone() -> bool:
    """Fetch origin in the project clone before any spawn (issue #100). A
    leg that starts while no fetch answers works on a base that may be
    older than the origin of the serving trunk, and nothing reported it, so
    the sweep verifies the base itself: no fetch, no spawn. The fetch also
    gives the reviewer branch the fresh tip it points at. The retries
    follow the spawn schedule, so a short outage costs no leg; an outage
    that outlasts them fails the event loudly instead."""
    main = Path.home() / "projects" / PROJECT_DIR / "main"
    if not main.is_dir():
        log.error("no project clone at %s, so no base can be verified", main)
        return False
    attempts = len(RETRY_DELAYS) + 1
    for attempt in range(attempts):
        try:
            result = subprocess.run(
                [GIT, "fetch", "origin"],
                cwd=main,
                capture_output=True,
                text=True,
                timeout=FETCH_TIMEOUT,
            )
        except (OSError, subprocess.SubprocessError) as err:
            log.warning("fetch of the project clone failed: %s", err)
        else:
            if result.returncode == 0:
                return True
            log.warning(
                "fetch of the project clone answered %s: %s",
                result.returncode,
                (result.stderr or "").strip()[:200],
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
        "against the origin of the serving trunk. No spawn happened. jracon: check that "
        "this host reaches the "
        "forge over ssh, then comment or push again to requeue the leg."
    )
    log.error("leg did not start: %s", body)
    post_comment(entity, body)


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
    the leg to its own read of the entity. The sentence of the empty set is
    no failure (issue #421): a list verb answers it with exit 0, and the
    read treats it as the empty list, so the payload of an empty comment
    set stays a payload."""
    out = subprocess.run(
        [TEA, *args, "--output", "json", "--repo", REPO],
        capture_output=True,
        text=True,
        timeout=60,
        check=True,
    ).stdout
    try:
        return json.loads(out)
    except ValueError:
        if out.strip() == EMPTY_SET_SENTENCE:
            return []
        raise


def entity_payload(kind: str, entity: int, issue) -> dict:
    """Fetch the entity of a leg at spawn time, after the fetch of the clone
    and before the spawn command (issue #311). A worker leg reads its issue
    with its comments. A nudge or reviewer leg reads the pull request, its
    comments, its review comments, and the linked issue with its comments
    when the number resolves: the event carries it, or the closing keyword
    of the pull request body names it. The stamp precedes the first read, so
    the payload is never older than the named time. The answer carries the
    read time, the rendered reads, the linked issue, and the cut reason:
    an empty reason fits, "unavailable" names a failed fetch or an answer
    that holds no JSON, and "cap" names a payload past PAYLOAD_LIMIT. A cut
    answer carries no reads, and the prompt names the cut instead."""
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    reads = []
    linked = None
    try:
        if kind == "worker":
            reads.append(
                (
                    f"tea issues {entity} --comments",
                    tea_read("issues", str(entity), "--comments"),
                )
            )
        else:
            pull = tea_read("pulls", str(entity))
            reads.append((f"tea pulls {entity}", pull))
            reads.append(
                (
                    f"tea comments list {entity}",
                    tea_read("comments", "list", str(entity)),
                )
            )
            reads.append(
                (
                    f"tea pulls review-comments {entity}",
                    tea_read("pulls", "review-comments", str(entity)),
                )
            )
            body = pull.get("body") if isinstance(pull, dict) else ""
            linked = as_int(issue) or linked_issue(str(body or ""))
            if linked:
                reads.append(
                    (
                        f"tea issues {linked} --comments",
                        tea_read("issues", str(linked), "--comments"),
                    )
                )
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
        reason = "the fetch at spawn time failed or its answer held no JSON"
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


def prompt_stop(windowed: bool, entity_word: str) -> str:
    """The closing rule of a worker-shaped prompt. A plain leg runs
    unattended: a prompt that no rule answers is a block, and the leg reports
    it. A windowed leg runs watched (issue #470): the owner answers each
    prompt in the view window of the session, so the leg waits for the
    answer, and only a denial blocks it. The windowed variant also rules the
    park (issue #505): the leg asks its park question in the session, it
    posts no park comment while it waits, and a session that ends with no
    answer falls back to the park comment of the factory skill."""
    if windowed:
        return (
            "This leg runs windowed: a person watches the view window of this session "
            "and answers each permission prompt. When a command stops at a permission "
            "prompt, wait for the answer of the person, then continue. "
            "When a command is denied, comment on the "
            + entity_word
            + " that you are blocked, and stop. "
            "When you meet a decision of a class that always parks, ask your "
            "question in this session. Wait for the typed answer of the person. "
            "Post no park comment on the " + entity_word + " while you wait. "
            "The typed answer continues this leg on the same branch, with no new "
            "loop start. "
            "The park comment holds the three parts of the park discipline. "
            "When the person ends the session with no answer, post the park comment "
            "on the " + entity_word + ", and stop."
        )
    return (
        "When a command stops at a permission prompt, comment on the "
        + entity_word
        + " that you are blocked, and stop."
    )


def resume_note(resume: str, changed: str) -> str:
    """The sentences of a resumed leg (issue #524). A resumed session keeps
    its context, so the leg needs no fresh read of what the prior leg
    already read, and it must know that its denial history came with it: a
    command that the prior leg saw denied may be allowed now, because the
    permission rules may have changed since it ran. changed names where the
    delta since the prior leg sits."""
    if not resume:
        return ""
    return (
        "This leg resumes the recorded session of the prior leg of this branch, so its context "
        "holds the entity, the tree, and the work as the prior leg left them. "
        + changed
        + " Re-read the entity only when you need a state newer than the payload time. "
        "The session keeps the denial history of the prior leg, and the permission rules may have "
        "changed since it ran: a command that it saw denied may be allowed now, so try such a "
        "command again before you report it as blocked. "
    )


def trunk_sentences() -> str:
    """The sentences that name a serving trunk which differs from the default
    branch of the repository (issue #571). The catch-up merge of the worker
    role pulls the serving trunk, so a leg of such an instance must know the
    name. An instance that serves the default branch names no trunk, so its
    prompts keep the single-trunk shape of the skill."""
    if not TRUNK:
        return ""
    return (
        f"The serving trunk of this dispatcher instance is {TRUNK}, not the default branch "
        "of the repository. "
        f"The catch-up merge of step 4 of the worker role pulls origin/{TRUNK}. "
    )


def worker_prompt(
    entity: int, branch: str, payload: dict, windowed: bool = False, resume: str = ""
) -> str:
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
    resumed = resume_note(
        resume,
        "What changed since that leg ended sits in the payload: read the comments of the issue "
        "that the prior leg has not seen.",
    )
    pull_base = (
        f"Open the pull request against the serving trunk {TRUNK} with "
        f"tea pulls create --base {TRUNK}. "
        if TRUNK
        else "Open the pull request against the default branch with tea pulls create. "
    )
    return (
        f"You are a worker leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        f"Work issue {entity} of this repository. "
        + source
        + resumed
        + "Follow the factory skill, role worker. "
        "Run one plain command in each shell call: no pipe, no chain, no loop, no command "
        "substitution, no shell variable. "
        "Make one topic per commit, run nix fmt before each commit, and follow Conventional Commits. "
        + trunk_sentences()
        + f"Push the branch with: git push -u origin {branch}. "
        + pull_base
        + "The body must hold "
        f"the owner brief of the factory skill, one Closes line for issue {entity}, and the test evidence. "
        "Stop after you comment on the issue with the pull request number and what you verified. "
        + prompt_stop(windowed, "issue")
        + payload_tail(payload)
    )


def nudge_prompt(
    entity: int,
    branch: str,
    cause: str,
    payload: dict,
    windowed: bool = False,
    resume: str = "",
) -> str:
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
        source += "Re-read an entity with its command when you need a state newer than that time. "
    resumed = resume_note(
        resume,
        "What changed since that leg ended names the cause above and the comments of the "
        "pull request in the payload.",
    )
    return (
        f"You are a worker leg of the factory loop on branch {branch} of project {PROJECT_DIR}. "
        f"{cause}"
        + source
        + resumed
        + "Follow the factory skill, role worker. Address the blocking findings by name. "
        "Run one plain command in each shell call: no pipe, no chain, no loop, no command "
        "substitution, no shell variable. "
        "Make one topic per commit, run nix fmt before each commit, and follow Conventional Commits. "
        + trunk_sentences()
        + f"Push the branch with: git push -u origin {branch}. "
        "A pull request for this branch already exists: do not open a second one. "
        "Stop after you comment on the pull request with what you changed and what you verified. "
        + prompt_stop(windowed, "pull request")
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
        "Hold the tip of the pull request in your worktree before you read the entity: "
        "run git fetch origin, then compare git rev-parse HEAD with git rev-parse @{u}. "
        "Run git pull --ff-only only when the two commands print different commits. "
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
        "the pull request that you are blocked, and stop." + payload_tail(payload)
    )


def print_prompt(kind: str, entity: int, windowed: bool = False) -> int:
    """Print the prompt of one role for one entity, with the entity payload
    rendered and its read time named, and start no leg (issue #388). A hand
    spawner passes the printed text to project spawn, so a hand-spawned leg
    and a looped leg receive the same brief shape. The worker role takes an
    issue number, and its payload fetch owns the cut fallback of the looped
    path. The windowed variant of the worker role prints the brief of a
    watched leg (issue #470): the hand spawner then passes a permission mode
    that waits, and answers the prompts of the session. The nudge and
    reviewer roles take a pull request number. One pull read resolves the
    linked issue of both and the nudge branch, the same fields the event
    path records at enqueue time. A pull read that fails fails the command,
    because the nudge prompt would name no branch. The hand spawner must see
    the failure, not paste a broken brief."""
    if kind == "worker":
        payload = entity_payload(kind, entity, None)
        sys.stdout.write(
            worker_prompt(entity, WORKER_BRANCH.format(n=entity), payload, windowed)
        )
        return 0
    try:
        pull = tea_read("pulls", str(entity))
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.error("could not read pull request %s for the prompt: %s", entity, err)
        return 1
    body = str(pull.get("body") or "") if isinstance(pull, dict) else ""
    issue = linked_issue(body)
    payload = entity_payload(kind, entity, issue)
    if kind == "nudge":
        branch = ref_name(pull.get("head")) if isinstance(pull, dict) else ""
        if not branch:
            log.error("pull request %s names no head branch", entity)
            return 1
        sys.stdout.write(nudge_prompt(entity, branch, "", payload))
        return 0
    sys.stdout.write(
        reviewer_prompt(entity, REVIEWER_BRANCH.format(n=entity), issue, payload)
    )
    return 0


def spawn_leg(kind: str, entity: int, branch: str, issue, cause=None, windowed=False):
    """Run project spawn --headless and parse the phase 3 envelope, and
    answer (code, envelope, runtime). Exit codes 11 and 12 are retried with
    a delay; every other failure goes back to the caller, which comments on
    the entity. The cause opens the prompt of a nudge leg: it says what
    started the leg. The payload fetch (issue #311) runs once here, before
    the retry loop, so every retry of one spawn speaks of the same read. A
    windowed event (issue #470) swaps the permission mode: the session
    waits at its prompts, and the owner answers them in the view window.
    The reviewer leg is never windowed, because it edits nothing.

    A worker or nudge leg of a branch with a recorded session resumes it
    (issue #524): the prompt carries the sentences of a resumed leg, and
    the command carries --resume with the transcript UUID. A reviewer leg
    and a windowed leg resume nothing — the reviewer reads independently,
    and a resumed session keeps its launch flags, so the waiting mode of a
    windowed launch may never reach a session that a plain leg started
    under dontAsk (machine decision 29 of the README).

    Under the sandbox tier (issue 607) the runtime names the per-leg state
    of the branch — the harness config directory, the agent socket, the
    transient units — and None answers a spawn of the code before the tier,
    so the caller records only what exists."""
    payload = entity_payload(kind, entity, issue)
    resume = ""
    if kind in ("worker", "nudge") and not windowed:
        resume = resume_uuid(branch)
    if kind == "reviewer":
        prompt, plan = reviewer_prompt(entity, branch, issue, payload), REVIEWER_PLAN
    else:
        cause = str(cause or "")
        if kind == "nudge":
            prompt, plan = (
                nudge_prompt(entity, branch, cause, payload, windowed, resume),
                WORKER_PLAN,
            )
        else:
            prompt, plan = (
                worker_prompt(entity, branch, payload, windowed, resume),
                WORKER_PLAN,
            )
    runtime = prepare_leg_runtime(branch)
    spawn_args = [
        PROJECT_BIN,
        "spawn",
        PROJECT_DIR,
        branch,
        "--plan",
        plan,
        "--headless",
        "--permission-mode",
        WINDOWED_PERMISSION_MODE if windowed else PERMISSION_MODE,
    ]
    if kind == "worker" and TRUNK:
        # the serving trunk (issue #571): the worker branch starts at the
        # tip of the trunk. --from is the interface of the project tool for
        # a named base, and the projectBase it records is the trunk itself,
        # the same branch that the pull request of the leg opens against. A
        # nudge branch exists already, and the reviewer branch is prepared
        # with plain git, so neither names a base
        spawn_args += ["--from", TRUNK]
    if resume:
        spawn_args += ["--resume", resume]
    spawn_args.append(prompt)
    if runtime is None:
        # the code before the tier: the plain scope keeps the envelope on
        # the pipe and the exit code of the spawn itself
        command = [*SCOPE_PREFIX, *spawn_args]
        attempts = len(RETRY_DELAYS) + 1
        for attempt in range(attempts):
            code, envelope = run_spawn(command, branch)
            if code not in RETRY_CODES:
                return code, envelope, None
            if attempt + 1 < attempts:
                delay = RETRY_DELAYS[attempt]
                log.warning(
                    "spawn of %s answered %s (%s), retry in %ss",
                    branch,
                    code,
                    ((envelope or {}).get("error") or {}).get("code"),
                    delay,
                )
                time.sleep(delay)
        return code, envelope, None
    # the sandbox tier (issue 607): the spawn runs as a transient forking
    # service with the properties of the spec. The forking type makes the
    # unit outlive the spawn: the initial process exits after the envelope,
    # the supervisor of the leg and its sessions stay in the cgroup, and the
    # unit ends when the last process leaves it (systemd.service(5), Type=forking).
    # The stdout of the spawn goes to a file of the leg state, because
    # --pipe would wait for the whole unit, and the envelope carries the
    # exit code in meta, so the file replaces the pipe for both
    stamp = time.strftime("%Y%m%dT%H%M%S")
    units = []
    if not start_leg_agent(f"leg-agent-{leg_slug(branch)}-{stamp}", runtime):
        return 1, None, None
    units.append(f"leg-agent-{leg_slug(branch)}-{stamp}")
    attempts = len(RETRY_DELAYS) + 1
    code, envelope = 1, None
    for attempt in range(attempts):
        unit = f"leg-{leg_slug(branch)}-{stamp}-a{attempt}"
        prefix = [
            SYSTEMD_RUN,
            "--user",
            "--unit",
            unit,
            "--service-type=forking",
            "--collect",
            "--quiet",
            "--expand-environment=no",
        ]
        for prop in SANDBOX["properties"]:
            prefix += ["-p", prop]
        # the socket placement of the leg (issue 633): the unit mounts the
        # socket directory of the leg state over the hardcoded daemon root
        # of the harness, so the supervisor socket lands in the leg state
        # and the attach of the view window reaches it from outside the
        # unit, while PrivateTmp keeps the rest of /tmp private
        prefix += ["-p", daemon_socket_bind_property(runtime["config_dir"])]
        prefix += [
            "-p",
            f"StandardOutput=append:{runtime['base']}/spawn.out",
            "-p",
            f"StandardError=append:{runtime['base']}/spawn.err",
        ]
        for key, value in SANDBOX["environment"].items():
            prefix += ["-E", f"{key}={value}"]
        for entry_env in leg_unit_environment(runtime):
            prefix += ["-E", entry_env]
        runtime["units"] = [unit] + units
        code, envelope = run_spawn(
            [*prefix, *spawn_args],
            branch,
            stdout_file=f"{runtime['base']}/spawn.out",
            stderr_file=f"{runtime['base']}/spawn.err",
        )
        if code not in RETRY_CODES:
            break
        if attempt + 1 < attempts:
            delay = RETRY_DELAYS[attempt]
            log.warning(
                "spawn of %s answered %s (%s), retry in %ss",
                branch,
                code,
                ((envelope or {}).get("error") or {}).get("code"),
                delay,
            )
            time.sleep(delay)
    if code != 0:
        # a spawn that never answered leaves no session: end the agent unit
        # and the supervisor before the failure comment
        teardown_leg_runtime(runtime, branch)
        return code, envelope, None
    return code, envelope, runtime


def run_spawn(
    command: list[str], branch: str, stdout_file: str = "", stderr_file: str = ""
):
    """Run one spawn command and parse its envelope. The plain scope pipes
    the envelope and the exit code of the spawn back; the sandboxed unit of
    the tier (issue 607) writes both to files of the leg state, because the
    systemd-run of a forking service returns at the start job and the
    envelope carries the true exit code in meta.exit_code, exactly for
    consumers that lose the code to a wrapper (the response envelope schema,
    modules/programs/cli/project/internal/spec/fixtures/response-envelope.json)."""
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
    stderr_text = result.stderr or ""
    if stderr_file:
        try:
            with open(stderr_file, encoding="utf-8", errors="replace") as handle:
                stderr_text = handle.read()
        except OSError:
            stderr_text = ""
    stderr_line = " ".join(stderr_text.split())[:500]
    if stderr_line:
        log.info("spawn of %s stderr: %s", branch, stderr_line)
    stdout_text = result.stdout or ""
    if stdout_file:
        try:
            with open(stdout_file, encoding="utf-8", errors="replace") as handle:
                stdout_text = handle.read()
        except OSError:
            stdout_text = ""
    envelope = None
    for line in reversed(stdout_text.splitlines()):
        try:
            envelope = json.loads(line)
            break
        except ValueError:
            continue
    if stdout_file:
        # the exit code of the spawn lives in the envelope; a lost envelope
        # names no code, so the caller reads a plain failure
        meta = (envelope or {}).get("meta") or {}
        if isinstance(meta, dict) and isinstance(meta.get("exit_code"), int):
            return int(meta["exit_code"]), envelope
        return 1, envelope
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
        body = f"dispatcher: the {kind} leg on {branch} failed with exit code {code} and stopped.{detail}"
    log.error("leg failed: %s", body)
    post_comment(entity, body)


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
                self.address_string(),
                err,
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
            given = given[len("sha256=") :]
        if hmac.compare_digest(given.strip().lower(), expected):
            return "ok"
    return "mismatch"


def serve() -> None:
    if not SECRET_FILE:
        log.error("DISPATCHER_WEBHOOK_SECRET_FILE is not set")
        sys.exit(2)
    init_state()
    server = ThreadingHTTPServer((BIND, PORT), Receiver)
    log.info(
        "receiver on %s:%s, project %s, repository %s", BIND, PORT, PROJECT_DIR, REPO
    )
    server.serve_forever()


# ------------------------------------------------------------- fallback


def poll() -> None:
    """The fallback of the bridge receiver: read the open issues with tea,
    queue a worker event for each new command comment, read the newest CI
    status of each open ai/ pull request, then sweep. The cursor file holds
    the newest comment id of each issue and of each open ai/ pull request,
    the pull requests it already queued for review, and the last CI status
    with its head sha that it saw on each of them. A first poll without a
    usable cursor records the baseline and queues nothing, so the fallback
    never replays the whole comment or CI history of the repository. A
    cursor without the prc map is no usable baseline (issue #525): it
    predates the pull request comments, and its issue entries cover the
    gated issues of the old listing only, so the widened surface would read
    the whole history as new once."""
    init_state()
    cursor_path = state_path("poll-cursor.json")
    cursor = load_json(cursor_path, {"issues": {}, "prs": [], "ci": {}})
    # a cursor without the prc map is pre-upgrade, and the default of
    # load_json answers a missing or unreadable cursor file the same way:
    # both record the baseline, or the first poll after the upgrade would
    # replay every comment that the widened surface newly reads
    baseline = "prc" not in cursor
    cursor.setdefault("ci", {})
    cursor.setdefault("prc", {})
    if baseline:
        log.info("no usable poll cursor: record the baseline, queue nothing")
    try:
        listing = subprocess.run(
            [
                TEA,
                "issues",
                "list",
                "--state",
                "open",
                "--output",
                "json",
                "--repo",
                REPO,
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=True,
        ).stdout
        for issue in json.loads(listing):
            number = as_int(issue.get("index"))
            if number is None:
                continue
            detail = subprocess.run(
                [
                    TEA,
                    "issues",
                    str(number),
                    "--comments",
                    "--output",
                    "json",
                    "--repo",
                    REPO,
                ],
                capture_output=True,
                text=True,
                timeout=120,
                check=True,
            ).stdout
            comments = json.loads(detail).get("comments") or []
            seen = as_int(cursor["issues"].get(str(number))) or 0
            for comment in comments:
                comment_id = as_int(comment.get("id")) or 0
                if comment_id <= seen:
                    continue
                body = str(comment.get("body") or "")
                if str(comment.get("author", "")).lower() == AGENT_LOGIN:
                    freed = release_entity(number)
                    if freed and is_wake_command(body):
                        wake_released(number, freed, f"poll-{comment_id}")
                    continue
                # the same human surface as the webhook path (issue #525):
                # the comment resets the wake bounds, a command queues the
                # leg, and plain prose continues a thread that the loop
                # stopped under the needs-owner label. The listing entry
                # carries the label state, so the reset writes no label
                # removal when the issue holds none (issue #582)
                held = NEEDS_OWNER_LABEL in label_names(issue.get("labels"))
                wake_reset(number, held)
                if not baseline:
                    if is_loop_command(body) or is_watch_command(body):
                        queue_gated_issue(f"poll-{comment_id}", number, body)
                    elif held:
                        queue_held_issue(f"poll-{comment_id}", number)
            if comments:
                cursor["issues"][str(number)] = max(
                    seen, max(as_int(c.get("id")) or 0 for c in comments)
                )
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        log.warning("poll of the issues failed: %s", err)
    try:
        pulls = subprocess.run(
            [
                TEA,
                "pulls",
                "list",
                "--state",
                "open",
                "--output",
                "json",
                "--fields",
                "ci,index,head,body",
                "--repo",
                REPO,
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=True,
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
                        f"poll-pr-{number}",
                        "reviewer",
                        number,
                        REVIEWER_BRANCH.format(n=number),
                        linked_issue(pull.get("body") or ""),
                        "poll: new pull request",
                        head,
                    )
                cursor["prs"].append(str(number))
            # the comments of the pull request (issue #525): the poll reads
            # them for the same surface as the webhook. The final comment of
            # a released leg wakes through the same rule, a command comment
            # of a person continues the work, and plain prose continues a
            # thread that the loop stopped under the needs-owner label
            try:
                listed = tea_read("comments", "list", str(number))
            except (OSError, ValueError, subprocess.SubprocessError) as err:
                log.warning(
                    "could not read the comments of pull request %s: %s", number, err
                )
                listed = []
            comments = listed if isinstance(listed, list) else []
            seen_prc = as_int(cursor["prc"].get(str(number))) or 0
            for comment in comments:
                comment_id = as_int(comment.get("id")) or 0
                if comment_id <= seen_prc:
                    continue
                body = str(comment.get("body") or "")
                if str(comment.get("author", "")).lower() == AGENT_LOGIN:
                    freed = release_entity(number)
                    if freed and is_wake_command(body):
                        wake_released(number, freed, f"poll-prc-{comment_id}")
                    continue
                # the continuation decides on the label state before the
                # reset (issue #525), the state that the payload of a webhook
                # delivery carries: the reset below removes the label of this
                # entity when it holds one, so a read after it finds no
                # label, and no plain comment would ever continue a stopped
                # thread. The same state rules the label write of the reset
                # (issue #582)
                held = NEEDS_OWNER_LABEL in pull_labels(number)
                wake_reset(number, held)
                if baseline:
                    continue
                if is_loop_command(body) or is_watch_command(body):
                    enqueue(
                        f"poll-prc-{comment_id}",
                        "nudge",
                        number,
                        head,
                        None,
                        "poll: command comment on the pull request",
                        head,
                        windowed=is_watch_command(body),
                    )
                elif held:
                    cause = (
                        f"A person answered on pull request {number}, which a bound of "
                        "the loop had stopped. Address the cause that the bound comment "
                        "named."
                    )
                    enqueue(
                        f"poll-prc-{comment_id}",
                        "nudge",
                        number,
                        head,
                        None,
                        "poll: plain comment on a needs-owner pull request",
                        head,
                        cause,
                    )
            if comments:
                cursor["prc"][str(number)] = max(
                    seen_prc, max(as_int(c.get("id")) or 0 for c in comments)
                )
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


def release_branch(branch: str) -> int:
    """Free the in-flight entry of one branch at once (issue #605): the
    owner step for an entry that a crashed or a misbehaving leg holds. The
    release drops the entry and stops the session of the leg, the same
    machinery as every other release, and it wakes nothing: the wake rule
    reads only the comment of the agent login. A queued event of the branch
    runs on the next sweep pass. The command starts no leg and reads no
    forge entity, so it works whatever the harness and the forge answer."""
    entry = inflight().get(branch)
    if not isinstance(entry, dict):
        print(f"no in-flight entry holds the branch {branch}")
        return 1
    release_inflight(branch)
    print(
        f"released the entry of {branch}: the session "
        f"{entry.get('session_id') or entry.get('session')} stopped, and a "
        "queued event of the branch runs on the next sweep pass"
    )
    return 0


def main(argv: list[str]) -> int:
    logging.basicConfig(
        level=os.environ.get("DISPATCHER_LOG", "INFO"),
        format="%(levelname)s %(name)s %(message)s",
    )
    if len(argv) == 2 and argv[1] in ("serve", "run", "poll"):
        {"serve": serve, "run": sweep, "poll": poll}[argv[1]]()
        return 0
    if len(argv) == 3 and argv[1] == "release" and argv[2]:
        return release_branch(argv[2])
    if (
        len(argv) in (4, 5)
        and argv[1] == "prompt"
        and argv[2]
        in (
            "worker",
            "nudge",
            "reviewer",
        )
        and (len(argv) == 4 or (argv[2] == "worker" and argv[4] == WATCH_WORD))
    ):
        entity = as_int(argv[3])
        if entity is not None and entity > 0:
            return print_prompt(argv[2], entity, len(argv) == 5)
    print(
        "usage: dispatcher.py serve|run|poll\n"
        "       dispatcher.py release <branch>\n"
        f"       dispatcher.py prompt worker <issue> [{WATCH_WORD}]\n"
        "       dispatcher.py prompt nudge|reviewer <pull request>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
