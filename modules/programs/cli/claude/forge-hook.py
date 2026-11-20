"""PreToolUse hook for the Bash tool: keep forge and push commands inside the working repository, keep a
session of `project spawn` to one plain command per call, and make a headless session fail at a prompt.

Claude Code sends the tool call as JSON on stdin. The hook answers allow, deny, or ask as JSON on stdout. It
prints nothing when the command is not a tea, gh, or git push command, so the normal permission rules decide.
The forge policy itself lives in tea-wrapper.py: the verb tables, the ownership rule, and the trunk rules.
The hook delegates each plain tea, gh, and git push command to the wrapper and keeps the session plumbing
alone: the tokenizer, the compound check, the headless conversion, and this answer envelope. See
docs/agent-context.md.
"""

import json
import os
import re
import shlex
import subprocess
import sys

ALLOW, DENY, ASK = "allow", "deny", "ask"

# commands that can run another command, so the hook cannot see inside them; tea-wrapper joined them,
# because it runs a tea command inside it (issue 556)
WRAPPERS = {
    "bash",
    "command",
    "direnv",
    "dash",
    "doas",
    "env",
    "eval",
    "exec",
    "fish",
    "nice",
    "nix",
    "nix-shell",
    "nohup",
    "script",
    "sh",
    "ssh",
    "sudo",
    "tea-wrapper",
    "time",
    "timeout",
    "watch",
    "xargs",
    "zsh",
}

MENTION = re.compile(r"\b(tea|gh)\b|\bgit\b.*\bpush\b", re.S)

# project spawn sets this in the settings env of the sessions it starts (see project.nix); a probe through
# `claude -p` confirmed that a settings env reaches the subprocesses of a session, hooks included
SPAWN_ENV = "PROJECT_SPAWN_SESSION"

# project spawn --headless sets this beside SPAWN_ENV: no person sits behind the prompts of the session, so
# every ask below becomes a deny that tells the session to report on its entity and stop
HEADLESS_ENV = "PROJECT_HEADLESS_SESSION"

# the words that start a loop in the shells that the Bash tool runs; most loop syntax also has a `;` or a
# newline, which the chain rule catches first, but `repeat 3 echo hi` in zsh has neither
LOOPS = {"for", "repeat", "select", "until", "while"}

# the delegation waits this many seconds for one answer of the wrapper
WRAPPER_TIMEOUT = 60


def wrapper_path(argv):
    """Return the path of the tea wrapper.

    The hook command of the settings file passes the store path of the wrapper as its first argument,
    because the store holds the two files apart. A run of the source tree, for example the test harness
    or the sandbox probe, falls back to the file beside the hook.
    """
    if len(argv) > 1:
        return argv[1]
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "tea-wrapper.py")


def tokenize(raw):
    """Split a command into segments of words. Raise ValueError when the shell syntax is not plain."""
    lex = shlex.shlex(raw, posix=True, punctuation_chars=";&|<>()\n")
    lex.whitespace_split = True
    lex.whitespace = " \t\r"
    segments, current, skip = [], [], False
    for token in lex:
        if skip:
            skip = False
        elif token[0] in ";&|\n":
            segments.append(current)
            current = []
        elif token[0] in "<>":
            # a redirection: the next word is a file, not an argument
            if token.startswith("<<"):
                raise ValueError("here document")
            skip = not token.endswith("&")
        elif token[0] in "()":
            raise ValueError("subshell")
        else:
            current.append(token)
    segments.append(current)
    return [s for s in segments if s]


def plain_words(words):
    """Return the words after any leading `NAME=value` assignments."""
    while words and re.match(r"^[A-Za-z_]\w*=", words[0]):
        words = words[1:]
    return words


def has_substitution(raw):
    return "`" in raw or "$(" in raw or "<(" in raw or ">(" in raw


def compound(raw):
    """Return a reason when the command is a pipe, a chain, a loop, or a command substitution, or None.

    A subshell or a here document is none of the four: the tokenizer raises for it, and the forge rules below
    decide, as before. Quoted operators are not operators, so `rg 'a|b'` stays one plain command.
    """
    if has_substitution(raw):
        return "the command holds a command substitution"
    try:
        segments = tokenize(raw)
    except ValueError:
        return None
    if len(segments) > 1:
        return "the command is a pipe or a chain"
    words = plain_words(segments[0]) if segments else []
    if words and words[0] in LOOPS:
        return f"{words[0]} is a loop"
    return None


def delegate(words, cwd, wrapper):
    """Ask the tea wrapper for one plain command. Return its verdict and reason, or (None, None).

    The wrapper answers with the response envelope and the exit-code table of the project tool: 0 for an
    allow and for no opinion, 7 for each refusal. A wrapper that crashes, times out, or answers outside
    its table leaves the hook with no answer, so the permission rules decide: the degradation that Trust
    criterion 13e of docs/agent-context.md names.
    """
    try:
        run = subprocess.run(
            [sys.executable, wrapper, "check-permissions", "--", *words],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=WRAPPER_TIMEOUT,
        )
    except (OSError, subprocess.SubprocessError):
        return None, None
    try:
        data = json.loads(run.stdout)["data"]
        verdict, reason = data["verdict"], data["reason"]
    except (ValueError, KeyError, TypeError):
        return None, None
    if run.returncode not in (0, 7) or verdict not in (ALLOW, ASK, DENY):
        return None, None
    return verdict, reason


def segment(words, cwd, wrapper):
    """Give one plain command to the policy of the wrapper, or to the wrapper-table rule of the hook."""
    words = plain_words(words)
    if not words:
        return None, None
    name = os.path.basename(words[0])
    if name in WRAPPERS and MENTION.search(" ".join(words)):
        return ASK, f"{name} runs a command that the hook cannot read"
    if name not in ("tea", "gh", "git"):
        return None, None
    return delegate(words, cwd, wrapper)


def judge(raw, cwd, wrapper):
    """Return the verdict and reason of the forge rules, or (None, None) when they do not judge the command."""
    if not MENTION.search(raw):
        return None, None
    if has_substitution(raw):
        return ASK, "the command holds a substitution that the hook cannot read"
    try:
        segments = tokenize(raw)
    except ValueError as error:
        return ASK, f"the hook cannot parse the command ({error})"
    results = [segment(words, cwd, wrapper) for words in segments]
    for verdict in (DENY, ASK):
        for got, reason in results:
            if got == verdict:
                return got, reason
    if results and all(got == ALLOW for got, _ in results):
        return ALLOW, results[0][1]
    return None, None


def decide(raw, cwd, wrapper, spawned, headless=False):
    """Return the final verdict and reason, or (None, None) when the hook does not answer.

    A spawned session gets a deny for a compound command, so the session splits it instead of waiting at a
    prompt. A headless session also gets a deny where a windowed one would ask: no person sits behind its
    prompts, so the session reports on its entity and stops.
    """
    if spawned:
        reason = compound(raw)
        if reason:
            return (
                DENY,
                f"{reason}: split it into one plain command for each shell call",
            )
    verdict, reason = judge(raw, cwd, wrapper)
    if verdict == ASK and headless:
        return (
            DENY,
            f"{reason}: a headless session has no person to answer; report on the entity and stop",
        )
    return verdict, reason


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("tool_name") != "Bash":
        return
    raw = (event.get("tool_input") or {}).get("command") or ""
    verdict, reason = decide(
        raw,
        event.get("cwd"),
        wrapper_path(sys.argv),
        os.environ.get(SPAWN_ENV) == "1",
        os.environ.get(HEADLESS_ENV) == "1",
    )
    if verdict:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": verdict,
                        "permissionDecisionReason": f"forge-hook: {reason}",
                    }
                }
            )
        )


if __name__ == "__main__":
    main()
