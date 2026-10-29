"""PreToolUse hook for the Bash tool: keep forge and push commands inside the working repository.

Claude Code sends the tool call as JSON on stdin. The hook answers allow, deny, or ask as JSON on stdout. It
prints nothing when the command is not a tea, gh, or git push command, so the normal permission rules decide.
See AGENTS.md, "Claude Code context and permissions".
"""

import json
import os
import re
import shlex
import subprocess
import sys

ALLOW, DENY, ASK = "allow", "deny", "ask"

# the one repository that every project may open issues in (see the global CLAUDE.md)
ISSUE_REPO = "jracon/genixis"

# commands that can run another command, so the hook cannot see inside them
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
    "time",
    "timeout",
    "watch",
    "xargs",
    "zsh",
}

MENTION = re.compile(r"\b(tea|gh)\b|\bgit\b.*\bpush\b", re.S)

# options that choose another repository, login, or server
SELECT_LONG = {"--login", "--org", "--owner", "--remote"}
SELECT_SHORT = {"-R", "-l"}
REPO_FLAGS = {"--repo", "-r"}

# `-R` means a repository in gh and a login discovery remote in tea
GH_REPO_FLAGS = {"--repo", "-R"}

TEA_ENTITIES = {
    "c": "comments",
    "comment": "comments",
    "comments": "comments",
    "i": "issues",
    "issue": "issues",
    "issues": "issues",
    "pr": "pulls",
    "pull": "pulls",
    "pulls": "pulls",
    "whoami": "whoami",
}

# every tea or gh word that changes something; a command without a subcommand that holds one is not a plain read
WRITE_VERBS = {
    "a",
    "add",
    "approve",
    "c",
    "clean",
    "close",
    "create",
    "delete",
    "e",
    "edit",
    "m",
    "merge",
    "open",
    "reject",
    "reopen",
    "reply",
    "resolve",
    "review",
    "rm",
    "unresolve",
}

OWNER_REPO = re.compile(r"^[^/\s:]+/[^/\s:]+$")


class Context:
    """The working repository, read from git on first use."""

    def __init__(self, cwd):
        self.cwd = cwd or os.getcwd()
        self._cache = {}

    def git(self, *args):
        key = args
        if key not in self._cache:
            try:
                run = subprocess.run(
                    ["git", *args],
                    cwd=self.cwd,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                self._cache[key] = run.stdout.strip() if run.returncode == 0 else None
            except (OSError, subprocess.SubprocessError):
                self._cache[key] = None
        return self._cache[key]

    @property
    def slug(self):
        url = self.git("remote", "get-url", "origin")
        if not url:
            return None
        parts = [p for p in re.split(r"[:/]", url.removesuffix("/").removesuffix(".git")) if p]
        return "/".join(parts[-2:]) if len(parts) >= 2 else None

    @property
    def branch(self):
        return self.git("branch", "--show-current") or None

    @property
    def remotes(self):
        return (self.git("remote") or "").split()

    @property
    def defaults(self):
        names = {"main", "master"}
        default = self.git("config", "project.defaultBranch")
        if not default:
            head = self.git("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
            default = head.removeprefix("origin/") if head else None
        if default:
            names.add(default)
        return names

    @property
    def bases(self):
        # a branch that another branch started from, through `project open --from`
        lines = self.git("config", "--get-regexp", r"^branch\..*\.projectbase$") or ""
        return {line.split(None, 1)[-1].removeprefix("origin/") for line in lines.splitlines()}

    def is_trunk(self, name):
        return name in self.defaults or name == "trunk" or name.endswith("/trunk")

    def is_base(self, name):
        # an integration branch, for example a composition branch: an orchestrator can push it after a prompt
        return name in self.bases


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


def select_flags(args, repo_flags):
    """Return the values of repo flags and a list of reasons for flags that select a login or a server."""
    repos, reasons = [], []
    i = 0
    while i < len(args):
        arg = args[i]
        name, eq, value = arg.partition("=")
        if arg.startswith("--") and not eq:
            value = None
        if name in repo_flags:
            if eq:
                repos.append(value)
            elif i + 1 < len(args):
                repos.append(args[i + 1])
                i += 1
            else:
                reasons.append(f"{name} has no value")
        elif name in SELECT_LONG or (name in SELECT_SHORT and name not in repo_flags):
            reasons.append(f"{name} selects another login or remote")
        i += 1
    return repos, reasons


def other_repo(args, ctx, repo_flags, allowed_extra=None, check_positional=True):
    """Return a reason when the command names a repository other than the working repository."""
    repos, reasons = select_flags(args, repo_flags)
    if reasons:
        return reasons[0]
    for repo in repos:
        if repo != ctx.slug and repo != allowed_extra:
            return f"names the repository {repo}, not the working repository"
    if check_positional:
        for i, arg in enumerate(args):
            # the value of a repo flag was judged above
            if i and args[i - 1] in repo_flags:
                continue
            if not arg.startswith("-") and ("://" in arg or OWNER_REPO.match(arg)):
                return f"the argument {arg} can name another repository"
    return None


def has_dollar(args):
    return any("$" in a for a in args)


def is_help(args):
    """True when `--help` is the last word and only words stand before it, so no flag can take it as a value."""
    return bool(args) and args[-1] == "--help" and not any(a.startswith("-") or "$" in a for a in args[:-1])


def tea(args, ctx):
    """Judge a tea command. `args` omits the word tea."""
    if is_help(args):
        return ALLOW, "tea help"
    positional = [a for a in args if not a.startswith("-")]
    entity = TEA_ENTITIES.get(positional[0]) if positional else None
    # the verb must stand right after the entity; a flag there hides it, so look for a write word instead
    verb = args[1] if len(args) > 1 and not args[1].startswith("-") and args[0] == positional[0] else None
    if entity and verb is None and args[0:1] == positional[0:1]:
        stray = WRITE_VERBS & set(args[1:])
        if stray:
            return ASK, f"tea {positional[0]} has a flag before the subcommand and a word {sorted(stray)[0]}"

    kind = None
    if entity == "issues":
        if verb in (None, "list", "ls") or (verb or "").isdigit():
            kind = "read"
        elif verb in ("create", "c"):
            kind = "issue-create"
        elif verb in ("edit", "e", "close", "reopen", "open"):
            kind = "ask"
    elif entity == "pulls":
        if verb in (None, "list", "ls", "review-comments", "rc") or (verb or "").isdigit():
            kind = "read"
        elif verb in ("create", "c"):
            kind = "write"
        elif verb in ("merge", "m"):
            return DENY, "tea pulls merge: the user merges pull requests"
        elif verb in ("edit", "e", "close", "reopen", "open"):
            kind = "ask"
    elif entity == "comments":
        if verb in ("list", "ls"):
            kind = "read"
        elif verb in ("delete", "rm"):
            return DENY, "tea comments delete: agents never delete comments"
        elif verb in ("add", "a") or (verb or "").isdigit():
            kind = "write"
        elif verb in ("edit", "e"):
            kind = "ask"
    elif entity == "whoami":
        kind = "read"

    if has_dollar(args):
        return ASK, "the command uses a shell variable"
    extra = ISSUE_REPO if kind == "issue-create" else None
    reason = other_repo(args, ctx, REPO_FLAGS, extra, check_positional=kind in ("read", None))
    if reason:
        return ASK, f"tea {reason}"
    if kind == "ask":
        return ASK, f"tea {positional[0]} {verb} changes something that the user owns"
    if kind in ("read", "write", "issue-create"):
        return ALLOW, f"tea {positional[0]} {verb or ''}".strip() + " in the working repository"
    return None, None


def gh(args, ctx):
    """Judge a gh command. `args` omits the word gh."""
    if is_help(args):
        return ALLOW, "gh help"
    positional = [a for a in args if not a.startswith("-")]
    group = positional[0] if positional else None
    verb = positional[1] if len(positional) > 1 else None
    if group == "pr" and verb == "merge":
        return DENY, "gh pr merge: the user merges pull requests"
    if has_dollar(args):
        return ASK, "the command uses a shell variable"
    reason = other_repo(args, ctx, GH_REPO_FLAGS, check_positional=True)
    if reason:
        return ASK, f"gh {reason}"
    reads = {"issue": {"list", "status", "view"}, "pr": {"checks", "diff", "list", "status", "view"}}
    if group in reads and verb in reads[group]:
        return ALLOW, f"gh {group} {verb} in the working repository"
    return None, None


def push(args, ctx):
    """Judge a git push. `args` starts after the word push."""
    delete = False
    positional = []
    i = 0
    while i < len(args):
        arg = args[i]
        name = arg.split("=", 1)[0]
        if arg == "--":
            positional += args[i + 1 :]
            break
        if name in ("--force", "--force-with-lease", "--force-if-includes", "--all", "--branches", "--mirror", "--prune"):
            return DENY, f"git push {name} can overwrite or remove branches"
        if name == "--delete":
            delete = True
        elif name in ("--repo", "--receive-pack", "--exec"):
            return ASK, f"git push {name} changes the target"
        elif name == "--tags":
            return ASK, "git push --tags pushes tags"
        elif name == "--push-option":
            i += 0 if "=" in arg else 1
        elif arg.startswith("-") and not arg.startswith("--"):
            letters = arg[1:]
            if "f" in letters:
                return DENY, "git push -f can overwrite branches"
            if "d" in letters:
                delete = True
            if "o" in letters:
                i += 1
        elif arg.startswith("-"):
            pass
        else:
            positional.append(arg)
        i += 1

    remote = positional[0] if positional else None
    refspecs = positional[1:]
    # a force mark on a refspec overwrites the target branch
    for spec in refspecs:
        if spec.startswith("+"):
            return DENY, f"git push +{spec[1:]} forces the update"
    if remote and remote not in ctx.remotes:
        return ASK, f"git push to {remote}, which is not a named remote of this repository"

    current = ctx.branch
    targets = []
    if not refspecs:
        mode = ctx.git("config", "push.default")
        if mode in ("matching", "upstream"):
            return ASK, f"git push without a refspec and push.default={mode}"
        if not current:
            return ASK, "git push without a refspec and no current branch"
        targets.append(current)
    for spec in refspecs:
        if re.search(r"[*?\[]", spec):
            return ASK, f"git push {spec} is a pattern"
        src, colon, dst = spec.partition(":")
        if colon and not dst:
            return ASK, f"git push {spec} has no target"
        name = dst if colon else src
        if colon and not src:
            delete = True
        name = name.removeprefix("refs/heads/")
        if name == "HEAD":
            if not current:
                return ASK, "git push HEAD with no current branch"
            name = current
        if name.startswith("refs/"):
            return ASK, f"git push {spec} targets a ref that is not a branch"
        targets.append(name)

    for name in targets:
        if ctx.is_trunk(name):
            return DENY, f"git push to {name}: the default branch and trunk branches take changes by pull request"
    for name in targets:
        if ctx.is_base(name):
            return ASK, f"git push to {name}, which is the projectBase of another branch"
    if delete:
        return ASK, "git push deletes a branch"
    return ALLOW, f"git push to {', '.join(targets)}, which is not a protected branch"


def git(args, ctx):
    """Judge a git command. Only push has a verdict."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2
        else:
            i += 1
    if i >= len(args) or args[i] != "push":
        return None, None
    if any(a in ("-C", "--git-dir", "--work-tree") or a.startswith(("--git-dir=", "--work-tree=")) for a in args[:i]):
        return ASK, "git push in a directory other than the working directory"
    if has_dollar(args):
        return ASK, "the command uses a shell variable"
    return push(args[i + 1 :], ctx)


def segment(words, ctx):
    while words and re.match(r"^[A-Za-z_]\w*=", words[0]):
        words = words[1:]
    if not words:
        return None, None
    name = os.path.basename(words[0])
    if name == "tea":
        return tea(words[1:], ctx)
    if name == "gh":
        return gh(words[1:], ctx)
    if name == "git":
        return git(words[1:], ctx)
    if name in WRAPPERS and MENTION.search(" ".join(words)):
        return ASK, f"{name} runs a command that the hook cannot read"
    return None, None


def decide(raw, ctx):
    if not MENTION.search(raw):
        return None, None
    if "`" in raw or "$(" in raw or "<(" in raw or ">(" in raw:
        return ASK, "the command holds a substitution that the hook cannot read"
    try:
        segments = tokenize(raw)
    except ValueError as error:
        return ASK, f"the hook cannot parse the command ({error})"
    results = [segment(words, ctx) for words in segments]
    for verdict in (DENY, ASK):
        for got, reason in results:
            if got == verdict:
                return got, reason
    if results and all(got == ALLOW for got, _ in results):
        return ALLOW, results[0][1]
    return None, None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if event.get("tool_name") != "Bash":
        return
    raw = (event.get("tool_input") or {}).get("command") or ""
    verdict, reason = decide(raw, Context(event.get("cwd")))
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
