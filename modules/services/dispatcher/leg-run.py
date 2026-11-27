"""Run the spawn request of one leg template instance (issue 607).

The transient-unit property path of systemd-run carries the properties of a
unit beside its name in one authorized call, so a polkit delegation scoped
to unit names would still let the caller smuggle any property, above all
User=, into a leg-named unit, and a leg that reaches the system bus could
escape every bound of the tier. The leg units of the tier are therefore
template instances (leg-unit@.service, leg-agent@.service) whose properties
the tier module authored (modules/services/sandbox-tier.nix), and a spawn
reaches them through StartUnit, which carries no properties. The per-spawn
data rides the request file instead: the dispatcher writes it beside the
leg state before it starts the unit, and the ExecStart of the template runs
this file, which execs the argv with the env as the user the template
already names.

The instance name arrives as the single argument. The wrapper accepts only
the instance charset of leg_slug, so an escaped or path-like instance name
cannot steer the request read outside the leg state. The wrapper execs the
argv directly, so no shell quoting touches the prompt, and no expansion of
systemd ever sees the arguments.
"""

import json
import os
import re
import sys
from typing import NoReturn


def fail(message: str) -> NoReturn:
    """Print one failure line on stderr and exit nonzero."""
    print(f"leg-run: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    """Read the request of one instance, check its shape, and exec its argv with its env."""
    if len(sys.argv) != 2:
        fail("the wrapper takes exactly one argument, the instance name")
    base = sys.argv[1]
    instance = os.path.basename(base.rstrip("/"))
    if not re.fullmatch(r"[A-Za-z0-9-]+", instance):
        fail(f"instance name {instance!r} holds characters outside the leg slug set")
    request_path = os.path.join(base, "request.json")
    try:
        with open(request_path, encoding="utf-8") as handle:
            request = json.load(handle)
    except (OSError, ValueError) as err:
        fail(f"the request {request_path} is unreadable: {err}")
    argv = request.get("argv") if isinstance(request, dict) else None
    if (
        not isinstance(argv, list)
        or not argv
        or not all(isinstance(arg, str) and arg for arg in argv)
    ):
        fail("the request holds no argv of non-empty strings")
    env = request.get("env", {})
    if not isinstance(env, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in env.items()
    ):
        fail("the request env is no mapping of strings to strings")
    os.environ.update(env)
    try:
        os.execvp(argv[0], argv)
    except OSError as err:
        fail(f"exec of {argv[0]} failed: {err}")


if __name__ == "__main__":
    main()
