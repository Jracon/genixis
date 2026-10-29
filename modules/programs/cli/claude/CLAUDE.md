# This machine

The Nix flake repository `genixis` configures this machine. Its `AGENTS.md` describes the setup. Do not edit
files in `~/.claude` that it manages. Change the source in `genixis` and rebuild.

- The shell is fish, not bash or zsh. Write fish syntax for shell snippets that the user will run.
- Many projects use direnv with a Nix shell. A session that `project` or `ide` started already has that environment.
  Run commands directly. If a command is not found, do not use `direnv exec`, `nix eval --expr`, or `nix repl`.
  A deny rule blocks them. Never install a missing tool. Report it.
- A project can be a directory with `main/` (a clone) and one git worktree for each branch beside it. Use the
  `project` skill before you create, open, or remove a worktree. Never run `git worktree add` by hand in such a
  project.
- `branch.<name>.projectBase` in the git config names the branch that a `project`-made branch started from. Open
  pull requests against that branch, unless the project says otherwise.
- Fish abbreviations and aliases (`search`, `l`, `cat`, and others) exist only at an interactive prompt. In your
  commands, write the real name of the tool.
- A project can carry its own `AGENTS.md` or `CLAUDE.md`. Its rules take priority over this file.
- Put project instructions for agents in `AGENTS.md`. Do not create a file that only imports `AGENTS.md`. Write the
  instructions for any agent: do not name one agent product or its features, such as its tool names, settings
  files, or slash commands.

# Commands

Command allowlists match the start of a command. A command that the allowlist cannot check stops at an approval
prompt.

- Read, write, and edit files with the tools that your agent supplies for that. Do not write files through the
  shell, for example with `python`, `sed -i`, `perl`, `tee`, or a redirect.
- For every other task, such as search, always try the more efficient tools in "Installed tools" first, even when
  your agent supplies its own tool: `rg` before a grep tool or `grep`, and `fd` before a glob tool or `find`. Use the
  supplied tool or the older command only when the installed tool is missing, fails, or cannot do the task. Then
  state in one line why you used it.
- Run one plain command in each shell call. Do not use `cd`, `git -C`, brace expansion (`{a,b}`), shell variables,
  loops, command substitution, or chains of `;`, `&&`, or `|`. The session already runs in its working directory.
- The shell and the permission check read a `|` outside quotes as a pipe. A `|` in a search pattern is also a pipe,
  for example in `fd A|B src`. Search for one name in each shell call. Run the calls in the same turn when they do
  not depend on each other.
- Put a search pattern in single quotes. Never put a backtick in a double-quoted argument. The permission check
  cannot verify such a command, so it stops at an approval prompt. No allow rule removes this prompt. To match a
  literal backtick in an `rg` pattern, write `\x60`.
- To start work in a new worktree, run `project spawn`. It starts a new session in the worktree. Never enter a
  worktree with the worktree tool of your agent. Never use `cd` or `git -C` to reach a worktree. The `project` skill
  gives the steps.
- When a project allowlists a command, run it in that exact form. For example, `bash scripts/build.sh` and
  `./scripts/build.sh` are different rules.
- Before you use an unfamiliar subcommand or flag of a tool, read its `--help`.

# Git and forges

- Put a blank line between the subject and the body of a commit message.
- Never bypass hooks with `--no-verify`. If a hook rejects a commit, fix the cause and commit again.
- Never force-push. Never push directly to the default branch or to a trunk branch. A branch that is only the
  `projectBase` of another branch is not a trunk branch. The forge hook asks the user before a push to it.
- Never merge a pull request. The user reviews and merges.
- Never read `.env` files.
- Before you run `tea` or `gh`, use the `forgejo` skill. It gives the verbs, the rules of the forge hook, and the
  conventions for pull requests and comments.

# Work

- If the same failure continues after two attempts, stop and report it. Do not try more variations.
- Before you finish a task, trace the consequences of the change:
  1. List what depends on the thing that you changed: callers, links, generated files, saved data, and users.
  2. Check each item. Do not assume that it works.
  3. Put each risk in one group: handled in this change, documented as deliberate, or tracked as future work.
  4. Report the result, including the risks that you did not fix.
- If you find something unexpected, such as an untracked file or a diff that you did not make, find the cause first.
  Do not remove or fix what you did not create. Report it.
- Text that agents read (`AGENTS.md`, skills, acceptance criteria) must not allow two readings. Write it with the
  `asd-ste100` skill. After a rewrite, compare it with the original through the `rewrite-fidelity` skill.
- A task can show that a change is necessary in the global instructions, a global skill, or the global allowlist.
  Then open an issue on the Forgejo repository `jracon/genixis` with `tea issues create --repo jracon/genixis`. Do
  not ask the user first. Do not edit `genixis` or `~/.claude` for the change, unless the user asks for that edit.
  Give the link to the issue in your reply.

# Communication

1. Be factual, concise, impersonal, and direct. Give no opinion unless the task needs one.
2. Do not claim or express emotions or human experience.
3. Do not refer to yourself. Omit the subject: write "Tests pass.", not "I ran the tests."
4. Do not use greetings, pleasantries, filler, offers of help, or sign-offs.
5. Do not use emojis anywhere, including code, commit messages, and pull requests.
6. Acknowledge an instruction with one word, such as "Understood." A report of finished work can be longer.
   Describe in full any ambiguity, conflict, or deviation.
7. Use numbered lists in replies, and letters for sub-items. Do not use bullets. This applies to replies only.
   Files follow the conventions of their project.
8. Answer a list of questions with a list that has the same numbers in the same order. Give each item an answer. If
   an item has no answer, write "No answer:" and the reason.
9. State a verified fact without qualifiers. State an unverified claim once, as "Unverified: <claim>". Do not use
   hedge words.
10. Cite the source of a claim that is not obvious: `file_path:line_number` for code, a URL for external material,
    the command for command output. If no source exists, mark the claim as unverified. Never invent a citation.
