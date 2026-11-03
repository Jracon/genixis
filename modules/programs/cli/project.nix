{
  pkgs,
  ...
}:

{
  # the Go binary does the work; this fish stub adds the one thing a child
  # process cannot do: close and convert change the directory of the
  # caller's shell, so the binary writes the target to PROJECT_CD_FILE and
  # the stub reads it after the binary ends. Scripts and agents that run the
  # PATH executable get the same behavior minus the cd.
  programs.fish.functions.project = ''
    set -l cdfile (mktemp)
    set -lx PROJECT_CD_FILE $cdfile
    command project $argv
    set -l st $status
    if test -s $cdfile
        cd (cat $cdfile)
    end
    command rm -f $cdfile
    return $st
  '';

  home.packages = [
    (pkgs.callPackage ../../../lib/project-package.nix { })
  ];

  # the completion protocol: the binary answers `project __complete` with
  # fish completion lines, so the file here only names the subcommands and
  # the flags and forwards the command line: the completed tokens, then the
  # token under the cursor after --. `command project` skips the cd stub,
  # so a completion press starts no mktemp dance.
  xdg.configFile."fish/completions/project.fish".text = ''
    complete -c project -f
    complete -c project -n __fish_use_subcommand -a open -d "open a project, or a branch of it as a worktree"
    complete -c project -n __fish_use_subcommand -a add -d "make a worktree and print a JSON envelope with its path"
    complete -c project -n __fish_use_subcommand -a close -d "remove a worktree and its merged branch"
    complete -c project -n __fish_use_subcommand -a discard -d "close a worktree and throw away its uncommitted work (interactive only)"
    complete -c project -n __fish_use_subcommand -a list -d "list the worktrees, branches, and merge state of a project as JSON"
    complete -c project -n __fish_use_subcommand -a spawn -d "make a worktree and start a Claude session in an ide window of its own"
    complete -c project -n __fish_use_subcommand -a clean -d "fast-forward main, close merged worktrees, delete merged branches"
    complete -c project -n __fish_use_subcommand -a convert -d "move a plain repo into <repo>/main"
    complete -c project -n "not __fish_use_subcommand" -k -a "(command project __complete (commandline -cop) -- (commandline -ct))"
    complete -c project -n "__fish_seen_subcommand_from clean" -s n -l dry-run -d "only list what would happen"
    complete -c project -n "__fish_seen_subcommand_from clean" -l gone -d "also clean branches whose remote branch is deleted (squash merges)"
    complete -c project -n "__fish_seen_subcommand_from spawn" -l headless -d "start the session in the background, with no window"
    complete -c project -n "__fish_seen_subcommand_from spawn" -l permission-mode -x -a "acceptEdits auto bypassPermissions dontAsk manual plan" -d "permission mode of the session"
    complete -c project -n "__fish_seen_subcommand_from open add spawn" -l as -x -d "directory name of the worktree, instead of the branch name"
    complete -c project -n "__fish_seen_subcommand_from open add spawn" -l from -x -k -a "(command project __complete from)"
    complete -c project -n "__fish_seen_subcommand_from open add spawn" -l identity -x -d "git identity of the leg: agent (default), owner, or a profile of main/.claude/settings.local.json"
    complete -c project -n "__fish_seen_subcommand_from open spawn" -l plan -x -a "(command project __complete plan)" -d "start the session against the endpoint of this plan"
  '';
}
