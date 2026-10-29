"""Test forge-hook.py. Run: python3 modules/programs/cli/claude/forge-hook-test.py

The script builds a throwaway repository with the origin `https://forgejo.example/jracon/genixis.git`, the
branch `feat/x`, and the trunk branch `ui/trunk`. It feeds each command to the hook and compares the answer.
"""

import json
import os
import subprocess
import sys
import tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forge-hook.py")

# (command, expected answer, branch that is checked out); an answer of None means no answer
CASES = [
    # not a forge command: no answer
    ("ls -la", None, "feat/x"),
    ("git status", None, "feat/x"),
    ("git commit -m 'push the tea'", None, "feat/x"),
    ("echo tea", None, "feat/x"),
    ("tea api /user", None, "feat/x"),
    # reads in the working repository: allow
    ("tea issues list", "allow", "feat/x"),
    ("tea issues ls --state all", "allow", "feat/x"),
    ("tea issues 35", "allow", "feat/x"),
    ("tea pulls list --repo jracon/genixis", "allow", "feat/x"),
    ("tea pulls 34 --comments", "allow", "feat/x"),
    ("tea comments list 35", "allow", "feat/x"),
    ("gh pr list", "allow", "feat/x"),
    ("gh pr view 3 --json title", "allow", "feat/x"),
    ("gh issue view 3 --repo jracon/genixis", "allow", "feat/x"),
    ("FOO=1 tea issues list", "allow", "feat/x"),
    ("tea issues list 2>&1", "allow", "feat/x"),
    # reads of another repository or login: ask
    ("tea issues list --repo other/repo", "ask", "feat/x"),
    ("tea issues list -r other/repo", "ask", "feat/x"),
    ("tea issues list --repo=other/repo", "ask", "feat/x"),
    ("tea issues list --login work", "ask", "feat/x"),
    ("tea issues list --remote upstream", "ask", "feat/x"),
    ("tea issues list --owner someone", "ask", "feat/x"),
    ("tea pulls list --repo other/repo", "ask", "feat/x"),
    ("tea issues other/repo#3", "ask", "feat/x"),
    ("gh pr list --repo other/repo", "ask", "feat/x"),
    ("gh pr list -R other/repo", "ask", "feat/x"),
    ("gh pr view https://github.com/other/repo/pull/3", "ask", "feat/x"),
    ("tea issues list --repo $REPO", "ask", "feat/x"),
    # writes in the working repository: allow
    ("tea pulls create --title 'feat: x' --description 'see https://a.example/b'", "allow", "feat/x"),
    ("tea pulls create --repo jracon/genixis --title t", "allow", "feat/x"),
    ("tea comment 35 'done'", "allow", "feat/x"),
    ("tea comments add 35 'done'", "allow", "feat/x"),
    ("tea issues create --title t --description d", "allow", "feat/x"),
    # the one exception: issue creation in jracon/genixis from any project
    ("tea issues create --repo jracon/genixis --title t", "allow", "feat/x"),
    ("tea issues create --repo other/repo --title t", "ask", "feat/x"),
    ("tea pulls create --repo other/repo --title t", "ask", "feat/x"),
    ("tea comment --repo other/repo 3 hi", "ask", "feat/x"),
    # writes that the user owns: ask
    ("tea issues edit 35 --title t", "ask", "feat/x"),
    ("tea issues close 35", "ask", "feat/x"),
    ("tea issues reopen 35", "ask", "feat/x"),
    ("tea pulls edit 34 --title t", "ask", "feat/x"),
    ("tea pulls close 34", "ask", "feat/x"),
    ("tea comments edit 5 hi", "ask", "feat/x"),
    ("tea issues --state all close 35", "ask", "feat/x"),
    # merge and comment deletion: deny
    ("tea pulls merge 34", "deny", "feat/x"),
    ("tea pr m 34", "deny", "feat/x"),
    ("tea pulls merge 34 --repo other/repo", "deny", "feat/x"),
    ("gh pr merge 34", "deny", "feat/x"),
    ("gh pr merge 34 --repo other/repo", "deny", "feat/x"),
    ("tea comments delete 5", "deny", "feat/x"),
    ("tea comments rm 5", "deny", "feat/x"),
    ("tea issues list && tea pulls merge 34", "deny", "feat/x"),
    # git push to a feature branch: allow
    ("git push -u origin feat/x", "allow", "feat/x"),
    ("git push origin feat/x", "allow", "feat/x"),
    ("git push origin HEAD", "allow", "feat/x"),
    ("git push --set-upstream origin HEAD:feat/x", "allow", "feat/x"),
    ("git push origin refs/heads/feat/x", "allow", "feat/x"),
    ("git push", "allow", "feat/x"),
    ("git push -u origin feat/x && tea issues list", "allow", "feat/x"),
    # git push to the default branch or a trunk branch: deny, whatever the flag order
    ("git push origin HEAD:main", "deny", "feat/x"),
    ("git push -u origin main", "deny", "feat/x"),
    ("git push origin main -u", "deny", "feat/x"),
    ("git push origin -u main", "deny", "feat/x"),
    ("git push origin feat/x:main", "deny", "feat/x"),
    ("git push origin HEAD:refs/heads/main", "deny", "feat/x"),
    ("git push origin master", "deny", "feat/x"),
    ("git push origin ui/trunk", "deny", "feat/x"),
    ("git push origin HEAD:ui/trunk", "deny", "feat/x"),
    ("git push", "deny", "main"),
    ("git push origin HEAD", "deny", "main"),
    ("git push origin :main", "deny", "feat/x"),
    ("git push origin --delete main", "deny", "feat/x"),
    ("git push -d origin main", "deny", "feat/x"),
    # git push that overwrites or removes: deny
    ("git push --force origin feat/x", "deny", "feat/x"),
    ("git push origin feat/x --force", "deny", "feat/x"),
    ("git push -f origin feat/x", "deny", "feat/x"),
    ("git push -uf origin feat/x", "deny", "feat/x"),
    ("git push --force-with-lease origin feat/x", "deny", "feat/x"),
    ("git push --force-with-lease=feat/x origin feat/x", "deny", "feat/x"),
    ("git push origin +feat/x", "deny", "feat/x"),
    ("git push --all origin", "deny", "feat/x"),
    ("git push --mirror origin", "deny", "feat/x"),
    # git push that the hook cannot judge: ask
    ("git push origin --delete feat/y", "ask", "feat/x"),
    ("git push origin :feat/y", "ask", "feat/x"),
    ("git push https://example.com/a/b.git feat/x", "ask", "feat/x"),
    ("git push elsewhere feat/x", "ask", "feat/x"),
    ("git push origin 'refs/heads/*:refs/heads/*'", "ask", "feat/x"),
    ("git push origin refs/tags/v1", "ask", "feat/x"),
    ("git push --tags origin", "ask", "feat/x"),
    ("git push -C /elsewhere origin feat/x", "ask", "feat/x"),
    ("git -C /elsewhere push origin feat/x", "ask", "feat/x"),
    ("git push origin $BRANCH", "ask", "feat/x"),
    # commands that the hook cannot parse: ask
    ("bash -c 'tea issues list --repo other/repo'", "ask", "feat/x"),
    ("sh -c 'git push origin main'", "ask", "feat/x"),
    ("eval 'tea issues list'", "ask", "feat/x"),
    ("env FOO=1 tea issues list", "ask", "feat/x"),
    ("xargs -I{} tea issues {}", "ask", "feat/x"),
    ("echo $(tea issues list --repo other/repo)", "ask", "feat/x"),
    ("echo `tea issues list`", "ask", "feat/x"),
    ("tea issues list 'unbalanced", "ask", "feat/x"),
    ("(tea issues list)", "ask", "feat/x"),
    ("cat <<EOF\ntea issues list\nEOF", "ask", "feat/x"),
    ("diff <(tea issues list) /dev/null", "ask", "feat/x"),
    # a compound command is allowed only when every part is
    ("tea issues list | head", None, "feat/x"),
    ("tea issues list; tea issues list --repo other/repo", "ask", "feat/x"),
    ("tea issues list\ntea issues list --login work", "ask", "feat/x"),
]


def git(cwd, *args):
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
    )


def main():
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        git(tmp, "init", "-q", "-b", "main")
        git(tmp, "commit", "-q", "--allow-empty", "-m", "first")
        git(tmp, "remote", "add", "origin", "https://forgejo.example/jracon/genixis.git")
        git(tmp, "config", "project.defaultBranch", "main")
        git(tmp, "branch", "feat/x")
        git(tmp, "branch", "ui/nav")
        git(tmp, "config", "branch.ui/nav.projectBase", "ui/trunk")
        current = None
        for command, expected, branch in CASES:
            if branch != current:
                git(tmp, "switch", "-q", branch)
                current = branch
            event = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": tmp}
            run = subprocess.run(
                [sys.executable, HOOK], input=json.dumps(event), capture_output=True, text=True, check=False
            )
            got = None
            if run.stdout.strip():
                got = json.loads(run.stdout)["hookSpecificOutput"]["permissionDecision"]
            if run.returncode != 0 or got != expected:
                failures += 1
                print(f"FAIL: {command!r}: expected {expected}, got {got} {run.stderr.strip()}")
        other = subprocess.run(
            [sys.executable, HOOK],
            input=json.dumps({"tool_name": "Read", "tool_input": {"command": "git push origin main"}}),
            capture_output=True,
            text=True,
            check=False,
        )
        if other.stdout.strip():
            failures += 1
            print("FAIL: the hook answered for a tool that is not Bash")
    print(f"{len(CASES) + 1 - failures} of {len(CASES) + 1} cases pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
