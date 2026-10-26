# This machine

The Nix flake repository `genixis` configures this machine. Its `AGENTS.md` describes the setup. Do not edit
files in `~/.claude` that it manages. Change the source in `genixis` and rebuild.

- The shell is fish, not bash or zsh. Write fish syntax for shell snippets that the user will run.
- Many projects use direnv with a Nix shell. Start build and test commands from a shell that has loaded the
  environment. To run one command in it, use `direnv exec . <command>`.
- A project can be a directory with `main/` (a clone) and one git worktree for each branch beside it. Use the
  `project` skill before you create, open, or remove a worktree. Never run `git worktree add` by hand in such a
  project.
- `branch.<name>.projectBase` in the git config names the branch that a `project`-made branch started from. Open
  pull requests against that branch, unless the project says otherwise.
- A project can carry its own `AGENTS.md` or `CLAUDE.md`. Its rules take priority over this file.
