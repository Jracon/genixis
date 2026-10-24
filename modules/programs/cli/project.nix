{
  lib,
  pkgs,
  ...
}:

let
  # copy-on-write clones where the filesystem supports them (APFS, btrfs, XFS), plain copies otherwise
  copy =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "cp -Rc $main/$file $tree/$file 2>/dev/null; or cp -R $main/$file $tree/$file"
    else
      "cp -R --reflink=auto $main/$file $tree/$file";

  # main's untracked files that .worktreeinclude lists, through `filter` (copies or @-links)
  included =
    filter:
    "git -C $main ls-files --others --ignored --directory --exclude-from=(string match --invert --regex '^\\s*(#|$)' < $dir/.worktreeinclude | ${filter} | psub) | string trim --right --chars /";
  copies = included "string match --invert --regex '^@'";
  links = included "string match --regex '^@.*' | string sub --start 2";
in
{
  # project layout: <dir>/main is the repo's default branch, <dir>/<branch> a git worktree of it,
  # and <dir>/.worktreeinclude (gitignore syntax, never committed) lists untracked files to copy
  # into new worktrees, or symlink with a leading @
  programs.fish.functions.project = ''
    set -l usage "usage: project open [dir] [branch] | project close [worktree] | project convert <repo>"
    switch "$argv[1]"
      case open
        set -l dir (path resolve (test -n "$argv[2]"; and echo $argv[2]; or echo .))
        set -l branch $argv[3]
        # pointed at one of a project's checkouts (e.g. `project open` inside one): open that one
        if test -d $dir; and test -d (path dirname $dir)/main/.git; and not test -d $dir/main/.git
          if test (path basename $dir) != main; and test -z "$branch"
            set branch (git -C $dir branch --show-current)
          end
          set dir (path dirname $dir)
        end
        set -l main $dir/main

        if not test -e $dir
          read --local --prompt-str "create project $dir? [y/N] " answer
          string match --quiet --ignore-case --regex '^y(es)?$' -- "$answer"; or return 1
          mkdir -p $main
          git -C $main init --quiet --initial-branch main
          # worktrees branch from a commit, so start with an empty one
          and git -C $main commit --quiet --allow-empty --message "initial commit"
          or return
        else if not test -d $main/.git
          if not test -e $dir/.git
            echo "project: $dir is not a project (no main/ checkout)" >&2
            return 1
          end
          # a plain repo: offer to convert it, unless that was declined for good
          if test "$(git -C $dir config --get project.convert)" != false
            read --local --prompt-str "$dir is a plain repo; convert it to a project? [y/N/never] " answer
            switch (string lower -- "$answer")
              case y yes
                project convert $dir; or return
              case never
                git -C $dir config --local project.convert false
                echo "project: won't ask again; undo with `git -C $dir config --unset project.convert`" >&2
            end
          end
          # still plain: open it as it is, but branches need the project layout
          if not test -d $main/.git
            if test -n "$branch"
              echo "project: $dir is a plain repo, so it can't open branches as worktrees" >&2
              return 1
            end
            ide $dir
            return
          end
        end

        set -l project (path basename $dir)
        # one Claude memory for the whole project, shared by main and its worktrees and kept after
        # `project close` (transcripts stay per path in ~/.claude)
        mkdir -p $dir/.claude/memory
        set -l claude --settings (${lib.getExe pkgs.jq} --null-input --compact-output --arg dir $dir/.claude/memory '{autoMemoryDirectory: $dir}')
        if test -z "$branch"
          ide $main $project $claude
          return
        end

        set -l tree $dir/(string replace --all / - -- $branch)
        if not test -e $tree
          set -l base (git -C $main branch --show-current)
          test -n "$base"; or set base HEAD
          # fetch so a new branch starts from what's been merged upstream since main was last pulled;
          # the timeout covers remotes that are only reachable from some networks
          if git -C $main remote get-url origin >/dev/null 2>&1
            if ${lib.getExe' pkgs.coreutils "timeout"} 10 git -C $main fetch --quiet origin 2>/dev/null
              and git -C $main show-ref --verify --quiet refs/remotes/origin/$base
              set base origin/$base
            else
              echo "project: couldn't fetch origin/$base; branching from local $base" >&2
            end
          end

          if git -C $main show-ref --verify --quiet refs/heads/$branch
            git -C $main worktree add --quiet $tree $branch
          else if git -C $main show-ref --verify --quiet refs/remotes/origin/$branch
            git -C $main worktree add --quiet --track -b $branch $tree origin/$branch
          else
            git -C $main worktree add --quiet --no-track -b $branch $tree $base
          end
          or return

          # ls-files can list a directory and then its contents; skip what an earlier entry brought in
          if test -f $dir/.worktreeinclude
            for file in (${copies})
              test -e $tree/$file; and continue
              mkdir -p (path dirname $tree/$file)
              ${copy}
            end
            for file in (${links})
              test -e $tree/$file; and continue
              mkdir -p (path dirname $tree/$file)
              ln -s $main/$file $tree/$file
            end
          end
        end
        ide $tree "$project: $branch" $claude

      case close
        set -l tree (git -C (test -n "$argv[2]"; and echo $argv[2]; or echo .) rev-parse --show-toplevel)
        or return
        set -l dir (path dirname $tree)
        set -l main $dir/main
        if test $tree = $main; or not test -d $main/.git
          echo "project: $tree is not a project worktree" >&2
          return 1
        end
        set -l branch (git -C $tree branch --show-current)

        # .worktreeinclude files are untracked, so git won't guard them: drop the links and the
        # copies that still match main, and refuse while any copy differs
        set -l copied
        set -l linked
        if test -f $dir/.worktreeinclude
          set copied (${copies})
          set linked (${links})
        end
        set -l changed
        for file in $copied
          if test -e $tree/$file; and not diff -rq $main/$file $tree/$file >/dev/null 2>&1
            set --append changed $file
          end
        end
        if set -q changed[1]
          echo "project: these .worktreeinclude files differ from main; copy or delete them first:" >&2
          printf '  %s\n' $changed >&2
          return 1
        end
        for file in $copied
          rm -rf $tree/$file
        end
        for file in $linked
          test -L $tree/$file; and rm $tree/$file
        end

        # refuses while there's uncommitted work
        git -C $main worktree remove $tree; or return
        if test $PWD = $tree; or string match --quiet -- "$tree/*" $PWD
          cd $main
        end
        set -l kept 0
        # keep the branch unless it's merged into main, locally or (often first, after a PR) upstream
        if test -n "$branch"
          set -l base (git -C $main branch --show-current)
          if git -C $main merge-base --is-ancestor $branch HEAD
            or git -C $main merge-base --is-ancestor $branch refs/remotes/origin/$base 2>/dev/null
            git -C $main branch --quiet --delete --force $branch
          else
            echo "project: kept branch $branch, which isn't merged into $base" >&2
            set kept 1
          end
        end
        # last: run from inside the worktree's own window, this ends the shell running it
        for window in (command tmux list-windows -a -F '#{window_id} #{@ide_dir}' 2>/dev/null)
          set -l parts (string split --max 1 ' ' -- $window)
          test "$parts[2]" = $tree; and command tmux kill-window -t $parts[1]
        end
        return $kept

      case convert
        if test -z "$argv[2]"
          echo $usage >&2
          return 1
        end
        set -l repo (path resolve $argv[2])
        if not test -d $repo/.git
          echo "project: $repo is not a plain git repo" >&2
          return 1
        end
        set -l main $repo/main

        # linked worktrees, which keep pointing at the old path until repaired
        set -l worktrees (git -C $repo worktree list --porcelain | string replace --filter --regex '^worktree ' "")[2..]
        set -l tmp (mktemp -d (path dirname $repo)/.project-convert.XXXXXX); or return
        mv $repo $tmp/main; and mv $tmp $repo; or return
        git -C $main worktree repair $worktrees
        git -C $main config --unset project.convert
        if test $PWD = $repo; or string match --quiet -- "$repo/*" $PWD
          cd $main(string sub --start (math (string length $repo) + 1) -- $PWD)
        end
        for window in (command tmux list-windows -a -F '#{window_id} #{@ide_dir}' 2>/dev/null)
          set -l parts (string split --max 1 ' ' -- $window)
          test "$parts[2]" = $repo; and command tmux set-option -w -t $parts[1] @ide_dir $main
        end

        # Claude Code keeps transcripts per path, every non-alphanumeric character as -; memory
        # moves into the project, where `project open` points Claude at it
        set -l claude (set -q CLAUDE_CONFIG_DIR; and echo $CLAUDE_CONFIG_DIR; or echo ~/.claude)/projects
        set -l old $claude/(string replace --all --regex '[^A-Za-z0-9]' - -- $repo)
        set -l new $claude/(string replace --all --regex '[^A-Za-z0-9]' - -- $main)
        if test -d $old/memory; and not test -e $repo/.claude/memory
          mkdir -p $repo/.claude
          mv $old/memory $repo/.claude/memory
        end
        if test -d $old; and not test -e $new
          mv $old $new
        end

      case '*'
        echo $usage >&2
        return 1
    end
  '';

  xdg.configFile."fish/completions/project.fish".text = ''
    complete -c project -f
    complete -c project -n __fish_use_subcommand -a open -d "open a project, or a branch of it as a worktree"
    complete -c project -n __fish_use_subcommand -a close -d "remove a worktree and its merged branch"
    complete -c project -n __fish_use_subcommand -a convert -d "move a plain repo into <repo>/main"
    complete -c project -n "__fish_seen_subcommand_from open close convert" -a "(__fish_complete_directories)"
  '';
}
