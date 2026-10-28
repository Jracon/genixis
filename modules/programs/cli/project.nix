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

  # main's untracked files that .worktreeinclude lists, through `filter` (copies, @-links or ~-discards)
  included =
    filter:
    "git -C $main ls-files --others --ignored --directory --exclude-from=(string match --invert --regex '^\\s*(#|$)' < $dir/.worktreeinclude | ${filter} | psub) | string trim --right --chars /";
  # evaluate the .envrc once, so the panes that `ide` starts next all hit the nix-direnv cache instead of racing
  # to evaluate it themselves; an .envrc that is not allowed yet fails here and is left for the panes to report,
  # and a slow evaluation (a cold build or fetch) stops after a minute so the window is never held up for long
  warm =
    path:
    "command -q direnv; and test -f ${path}/.envrc; and ${lib.getExe' pkgs.coreutils "timeout"} 60 direnv exec ${path} true >/dev/null 2>&1";
  # a project of its own gets its own tmux session and WezTerm window: from a tmux session of another project,
  # `ide --detach` makes both, where plain `ide` would add a tab to the current session
  ideIn =
    args:
    "if set -q TMUX; and test (command tmux display-message -p '#S') != (string replace --all --regex '[.:\\s]+' _ -- $project); ide --detach $project ${args}; else; ide ${args}; end";
  copies = included "string match --invert --regex '^[@~]'";
  discards = included "string match --regex '^~.*' | string sub --start 2";
  links = included "string match --regex '^@.*' | string sub --start 2";
in
{
  # project layout: <dir>/main is the repo's default branch, <dir>/<branch> a git worktree of it,
  # and <dir>/.worktreeinclude (gitignore syntax, never committed) lists untracked files to copy
  # into new worktrees, symlink with a leading @, or copy but discard unchecked on close with a leading ~
  programs.fish.functions.project = ''
    set -l usage "usage: project open|add|spawn [dir] [branch] [--from base] [--as name] [--headless] | project close|discard [worktree] | project clean [dir] [--dry-run] [--gone] | project convert <repo>"
    switch "$argv[1]"
      case open add spawn
        # `add` makes the worktree and prints its path, for scripts and agents: no window, no pull;
        # `spawn` also starts a Claude session there, with the rest of the arguments as its prompt: in an ide
        # window of its own, or with --headless in the background
        set -l action $argv[1]
        argparse --name "project $action" 'from=' 'as=' 'headless' 'permission-mode=' -- $argv[2..]; or return
        # a bare name is a project under ~/projects, from any directory; ./name is relative to here
        set -l dir $argv[1]
        if test -z "$dir"
          set dir .
        else if not string match --quiet --regex '[/~]|^\.+$' -- $dir
          set dir $HOME/projects/$dir
        end
        set dir (path resolve $dir)
        set -l branch $argv[2]
        if begin; set -q _flag_from; or set -q _flag_as; end; and test -z "$branch"
          echo "project: --from and --as need a branch" >&2
          return 1
        end
        if string match --quiet '*/*' -- "$_flag_as"
          echo "project: --as is a directory name, so it can't contain /" >&2
          return 1
        end
        if test $action != open; and test -z "$branch"
          echo $usage >&2
          return 1
        end
        set -l prompt (string join " " -- $argv[3..])
        if test $action = spawn; and test -z "$prompt"
          echo "project: spawn needs a prompt after the branch" >&2
          return 1
        end
        # the checkout this ran in, if it's a worktree: a new branch then starts from its branch
        set -l here (git rev-parse --show-toplevel 2>/dev/null)
        # pointed at one of a project's checkouts (e.g. `project open` inside one): open that one
        if test -d $dir; and test -d (path dirname $dir)/main/.git; and not test -d $dir/main/.git
          if test (path basename $dir) != main; and test -z "$branch"
            set branch (git -C $dir branch --show-current)
          end
          set dir (path dirname $dir)
        end
        set -l main $dir/main

        if not test -e $dir
          # a git URL clones into main/ (the layout `project convert` makes); y starts an empty repo
          read --local --prompt-str "create project $dir? [git URL to clone/y/N] " answer
          switch (string lower -- "$answer")
            case y yes
              mkdir -p $main
              git -C $main init --quiet --initial-branch main
              # worktrees branch from a commit, so start with an empty one
              and git -C $main commit --quiet --allow-empty --message "initial commit"
              or return
            case "" n no
              return 1
            case '*'
              if not git clone -- $answer $main
                # a failed clone removes main/, but can leave the empty project directory behind
                rmdir $dir 2>/dev/null
                return 1
              end
          end
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
          # catch up with upstream without holding up the window: fast-forward only, so local work is safe
          git -C $main pull --ff-only --quiet >/dev/null 2>&1 &
          disown
          ${warm "$main"}
          ${ideIn "$main main $claude"}
          return
        end

        # an existing worktree of the branch wins; else <dir>/<name>, the branch with / as - unless --as
        set -l tree
        set -l found
        for line in (git -C $main worktree list --porcelain)
          string match --quiet 'worktree *' -- $line; and set found (string sub --start 10 -- $line)
          test "$line" = "branch refs/heads/$branch"; and set tree $found
        end
        if test -z "$tree"
          set tree $dir/(test -n "$_flag_as"; and echo $_flag_as; or string replace --all / - -- $branch)
        end
        if not test -e $tree
          set -l base (__project_default $main)
          test -n "$base"; or set base HEAD
          set -l current (git -C $main branch --show-current)
          if test -n "$current"; and test "$current" != "$base"
            echo "project: main/ is on $current, not the default branch $base; branching from $base" >&2
          end
          # --from branches a new branch off another long-lived branch (e.g. a UI trunk) instead of
          # main; a local branch wins over its remote, which may be behind
          set -l from $_flag_from
          if test -z "$from"; and test -n "$here"; and test "$here" != $main; and test (path dirname $here) = $dir
            set from (git -C $here branch --show-current)
            echo "project: branching from $from, because you are in its worktree (--from overrides)" >&2
          end
          if test -n "$from"
            if git -C $main show-ref --verify --quiet refs/heads/$from
              set base $from
            else if git -C $main show-ref --verify --quiet refs/remotes/origin/$from
              set base origin/$from
            else
              echo "project: no branch $from to start from" >&2
              return 1
            end
          end
          # fetch so a new branch starts from what's been merged upstream since main was last pulled;
          # the timeout covers remotes that are only reachable from some networks
          if git -C $main remote get-url origin >/dev/null 2>&1
            if ${lib.getExe' pkgs.coreutils "timeout"} 10 git -C $main fetch --quiet origin 2>/dev/null
              if test -z "$from"; and git -C $main show-ref --verify --quiet refs/remotes/origin/$base
                set base origin/$base
              end
            else
              echo "project: couldn't fetch origin; branching from local $base" >&2
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
          # remember the parent so `project close` counts a merge into it as merged
          if test -n "$from"; and git -C $main show-ref --verify --quiet refs/heads/$branch
            git -C $main config branch.$branch.projectBase $from
          end

          # an .envrc that matches main's is as trusted as main's: allow it, so the environment loads
          # without a manual `direnv allow` (a branch that edits .envrc still needs one)
          if command -q direnv; and test -f $tree/.envrc; and cmp --silent $main/.envrc $tree/.envrc
            and ${lib.getExe' pkgs.coreutils "env"} --chdir $main direnv status 2>/dev/null | string match --quiet '*Found RC allowed 0*'
            direnv allow $tree 2>/dev/null
          end

          # ls-files can list a directory and then its contents; skip what an earlier entry brought in
          if test -f $dir/.worktreeinclude
            for file in (${copies}) (${discards})
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
        else if test $action = open
          # catch up with upstream without holding up the window: fast-forward only, so local work is safe
          git -C $tree pull --ff-only --quiet >/dev/null 2>&1 &
          disown
        end
        if test $action = add
          echo $tree
          return
        end
        # main/.git is outside the worktree, so the agent's reads of its own git metadata would prompt: allow
        # every entry there (as found now) but other worktrees' metadata, and deny edits. A rule for main/.git
        # itself would match all of it (gitignore semantics), so only an exact ls of it is allowed.
        set -l gitdir (git -C $tree rev-parse --absolute-git-dir); or return
        set -l reads $gitdir
        for entry in $main/.git/*
          test (path basename $entry) = worktrees; or set --append reads $entry
        end
        set claude --settings (${lib.getExe pkgs.jq} --null-input --compact-output --arg dir $dir/.claude/memory --arg git $main/.git --args '{
          autoMemoryDirectory: $dir,
          permissions: {
            allow: ([$ARGS.positional[] | "Read(/\(.))", "Read(/\(.)/**)"] + ["Bash(ls \($git))"]),
            deny: ["Edit(/\($git))", "Edit(/\($git)/**)"]
          }
        }' $reads)
        if test $action = spawn; and not set -q _flag_headless
          # a window of its own, where the user can watch the agent and answer its permission prompts
          set -q _flag_permission_mode; and set --append claude --permission-mode $_flag_permission_mode
          echo "project: ide window \"$branch\" in tmux session \"$project\"" >&2
          ${warm "$tree"}
          ide --detach $project $tree $branch $claude -- "$prompt"
          return
        else if test $action = spawn
          # run from the worktree, and in its direnv environment when that's allowed
          set -l run ${lib.getExe' pkgs.coreutils "env"} --chdir $tree
          if command -q direnv; and test -f $tree/.envrc
            if $run direnv status 2>/dev/null | string match --quiet '*Found RC allowed 0*'
              set --append run direnv exec .
            else
              echo "project: $tree/.envrc isn't allowed, so the agent starts without its environment" >&2
            end
          end
          if set -q _flag_permission_mode
            set --append claude --permission-mode $_flag_permission_mode
          else
            echo "project: no --permission-mode, so the session waits at every permission prompt" >&2
          end
          echo "project: session \"$project: $branch\" (claude attach \"$project: $branch\")" >&2
          $run claude --bg --name "$project: $branch" $claude -- "$prompt"
          return
        end
        ${warm "$tree"}
        ${ideIn "$tree $branch $claude"}

      case close discard
        # discard is close that throws work away, so only a person at a terminal may run it: it refuses
        # inside Claude Code and without a terminal, and asks for a one-time code typed at that terminal
        set -l action $argv[1]
        if test $action = discard; and begin; set -q CLAUDECODE; or not isatty stdin; or not isatty stderr; end
          echo "project: discard runs only from a person's interactive terminal, never from an agent" >&2
          return 1
        end
        # a bare name is a worktree of the project this runs in, from any of its checkouts or its
        # directory; ./name is relative to here
        set -l target $argv[2]
        test -n "$target"; or set target .
        if not string match --quiet --regex '[/~]|^\.+$' -- $target
          set -l top (git rev-parse --show-toplevel 2>/dev/null)
          if test -d main/.git
            set target $PWD/$target
          else if test -n "$top"; and test -d (path dirname $top)/main/.git
            set target (path dirname $top)/$target
          end
        end
        set -l tree (git -C $target rev-parse --show-toplevel)
        or return
        set -l dir (path dirname $tree)
        set -l main $dir/main
        if test $tree = $main; or not test -d $main/.git
          echo "project: $tree is not a project worktree" >&2
          return 1
        end
        set -l branch (git -C $tree branch --show-current)

        # .worktreeinclude files are untracked, so git won't guard them: drop the links, the
        # discards and the copies that still match main, and refuse while any copy differs
        set -l copied
        set -l discarded
        set -l linked
        if test -f $dir/.worktreeinclude
          set copied (${copies})
          set discarded (${discards})
          set linked (${links})
        end
        # change nothing while there's uncommitted work: git worktree remove would refuse, but only
        # after the links and copies below were gone. The links show up as untracked when the ignore
        # pattern only matches directories, so they don't count.
        set -l dirty (git -C $tree status --porcelain)
        for file in $linked
          set dirty (string match --invert --regex -- '^\?\? '(string escape --style=regex -- $file)'/?$' $dirty)
        end
        if set -q dirty[1]; and test $action = close
          echo "project: $tree has uncommitted work; commit or discard it first" >&2
          return 1
        end

        set -l changed
        for file in $copied
          if test -e $tree/$file; and not diff -rq $main/$file $tree/$file >/dev/null 2>&1
            set --append changed $file
          end
        end
        if set -q changed[1]; and test $action = close
          echo "project: these .worktreeinclude files differ from main; copy or delete them first:" >&2
          printf '  %s\n' $changed >&2
          return 1
        end
        # git ignores the discards, so it can't tell they hold work: a project can veto with
        # `git config project.closeCheck <command>`, run in the worktree, non-zero refuses
        set -l vetoed false
        set -l check (git -C $main config --get project.closeCheck)
        if test -n "$check"
          if not ${lib.getExe' pkgs.coreutils "env"} --chdir $tree PROJECT_MAIN=$main PROJECT_TREE=$tree sh -c "$check"
            if test $action = close
              echo "project: project.closeCheck refused to close $tree" >&2
              return 1
            end
            set vetoed true
          end
        end
        # show what is lost, then ask for a code that no script can know in advance
        if test $action = discard; and begin; set -q dirty[1]; or set -q changed[1]; or test $vetoed = true; end
          echo "project: discard deletes this work in $tree for good:" >&2
          set -q dirty[1]; and printf '  %s\n' $dirty >&2
          set -q changed[1]; and printf '  %s (differs from main)\n' $changed >&2
          test $vetoed = true; and echo "  ignored files that project.closeCheck protects" >&2
          set -l code (random 100000 999999)
          read --local --prompt-str "type $code to discard it: " answer </dev/tty
          if test "$answer" != $code
            echo "project: wrong code; nothing discarded" >&2
            return 1
          end
        end
        for file in $copied $discarded
          rm -rf $tree/$file
        end
        for file in $linked
          test -L $tree/$file; and rm $tree/$file
        end

        # a build can leave read-only files (ignored ones), which git can't delete
        chmod -R u+w $tree
        # refuses while there's uncommitted work, unless discard confirmed it above
        git -C $main worktree remove (test $action = discard; and echo --force) $tree; or return
        # background agents that were started in the worktree have nothing left to work in
        if command -q claude
          for id in (claude agents --json --cwd $tree 2>/dev/null | ${lib.getExe pkgs.jq} --raw-output '.[] | select(.kind == "background") | .id')
            claude stop $id >/dev/null 2>&1
          end
        end
        if test $PWD = $tree; or string match --quiet -- "$tree/*" $PWD
          cd $main
        end
        # keep the branch unless it is merged
        if test -n "$branch"
          set -l base (__project_default $main)
          set -l parent (git -C $main config --get branch.$branch.projectBase)
          if __project_merged $main $branch
            git -C $main branch --quiet --delete --force $branch
            git -C $main config --unset branch.$branch.projectBase 2>/dev/null
          else
            echo "project: kept branch $branch, which isn't merged into $base$(test -n "$parent"; and echo " or $parent")" >&2
          end
        end
        # last: run from inside the worktree's own window, this ends the shell running it
        for window in (command tmux list-windows -a -F '#{window_id} #{@ide_dir}' 2>/dev/null)
          set -l parts (string split --max 1 ' ' -- $window)
          test "$parts[2]" = $tree; and command tmux kill-window -t $parts[1]
        end
        return 0

      case clean
        argparse --name "project clean" n/dry-run gone -- $argv[2..]; or return
        set -l target (path resolve (test -n "$argv[1]"; and echo $argv[1]; or echo .))
        set -l dir
        if test -d $target/main/.git
          set dir $target
        else
          set -l top (git -C $target rev-parse --show-toplevel 2>/dev/null)
          test -n "$top"; and test -d (path dirname $top)/main/.git; and set dir (path dirname $top)
        end
        if test -z "$dir"
          echo "project: $target is not in a project" >&2
          return 1
        end
        set -l main $dir/main
        set -l base (__project_default $main)

        # the upstream tips from before the fetch drops the branches the remote deleted: --gone deletes
        # a branch only if it has nothing beyond its old upstream
        set -l preBranches
        set -l preTips
        if set -q _flag_gone
          for row in (git -C $main for-each-ref --format='%(refname:short) %(upstream)' refs/heads)
            set -l parts (string split ' ' -- $row)
            test -n "$parts[2]"; or continue
            set --append preBranches $parts[1]
            set --append preTips (git -C $main rev-parse --quiet --verify $parts[2] 2>/dev/null; or echo none)
          end
        end

        # catch up: fetch (dropping branches the remote deleted), then fast-forward the default branch
        if git -C $main remote get-url origin >/dev/null 2>&1
          ${lib.getExe' pkgs.coreutils "timeout"} 10 git -C $main fetch --quiet --prune origin 2>/dev/null
          or echo "project: couldn't fetch origin; cleaning with what is local" >&2
          if test -n "$base"; and test "$(git -C $main branch --show-current)" != "$base"
            echo "project: main/ is on $(git -C $main branch --show-current), not the default branch $base; not fast-forwarding" >&2
          else if test -n "$base"; and git -C $main show-ref --verify --quiet refs/remotes/origin/$base
            if set -q _flag_dry_run
              echo "would fast-forward $base"
            else
              git -C $main merge --ff-only --quiet origin/$base 2>/dev/null
              or echo "project: couldn't fast-forward $base to origin/$base" >&2
            end
          end
        end

        # which branch each worktree has
        set -l wtPaths
        set -l wtBranches
        set -l found
        for line in (git -C $main worktree list --porcelain)
          string match --quiet 'worktree *' -- $line; and set found (string sub --start 10 -- $line)
          if string match --quiet 'branch refs/heads/*' -- $line
            set --append wtPaths $found
            set --append wtBranches (string replace 'branch refs/heads/' "" -- $line)
          end
        end
        # --gone: branches whose remote branch was deleted, which is how a squash merge shows
        set -l gone
        if set -q _flag_gone
          for name in (git -C $main for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | string replace --filter --regex ' \[gone\]$' "")
            set -l i (contains --index -- $name $preBranches)
            if test -n "$i"; and test "$preTips[$i]" = "$(git -C $main rev-parse refs/heads/$name)"
              set --append gone $name
            else
              echo "project: kept $name: its remote branch is gone, but it may hold unpushed work" >&2
            end
          end
        end

        set -l loose
        set -l trees
        for branch in (git -C $main for-each-ref --format='%(refname:short)' refs/heads)
          test "$branch" = "$base"; and continue
          test "$branch" = "$(git -C $main branch --show-current)"; and continue
          # a branch with only its creation in the reflog has no work yet; it merely looks merged
          set -l log (git -C $main reflog show --format=%gs $branch 2>/dev/null)
          if test (count $log) = 1; and string match --quiet 'branch: Created*' -- $log[1]
            continue
          end
          __project_merged $main $branch; or contains -- $branch $gone; or continue
          set -l i (contains --index -- $branch $wtBranches)
          if test -n "$i"
            set --append trees $wtPaths[$i]
          else
            set --append loose $branch
          end
        end

        for branch in $loose
          if set -q _flag_dry_run
            echo "would delete branch $branch"
          else
            git -C $main branch --quiet --delete --force $branch; and echo "deleted branch $branch"
          end
        end
        # the worktree this runs in goes last: closing it ends the shell
        set -l here (git rev-parse --show-toplevel 2>/dev/null)
        if set -l i (contains --index -- "$here" $trees)
          set --erase trees[$i]
          set --append trees $here
        end
        for tree in $trees
          set -l branch $wtBranches[(contains --index -- $tree $wtPaths)]
          if set -q _flag_dry_run
            echo "would close $tree and delete branch $branch"
            continue
          end
          project close $tree
          if test -e $tree
            echo "project: kept $tree" >&2
          else
            echo "closed $tree"
            # a gone branch need not be an ancestor of anything, so close keeps it
            if contains -- $branch $gone; and git -C $main show-ref --verify --quiet refs/heads/$branch
              git -C $main branch --quiet -D $branch; and echo "deleted branch $branch"
            end
          end
        end

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

  # the function above exists only in fish; this makes it callable from bash and other programs (agents)
  home.packages = [
    (pkgs.writeShellScriptBin "project" ''
      exec ${lib.getExe pkgs.fish} -c 'project $argv' -- "$@"
    '')
  ];

  # the project's default branch: git config project.defaultBranch, else what origin/HEAD names (if that
  # branch exists), else the branch main/ has checked out
  programs.fish.functions.__project_default = ''
    set -l main $argv[1]
    set -l name (git -C $main config --get project.defaultBranch)
    if test -z "$name"
      set name (git -C $main symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | string replace --regex '^origin/' "")
      if test -n "$name"; and not git -C $main show-ref --verify --quiet refs/heads/$name
        and not git -C $main show-ref --verify --quiet refs/remotes/origin/$name
        set name ""
      end
    end
    test -n "$name"; or set name (git -C $main branch --show-current)
    echo $name
  '';

  # exit status 0 when the branch is merged into main, locally or (often first, after a PR) upstream,
  # or into the branch it was started from with --from
  programs.fish.functions.__project_merged = ''
    set -l main $argv[1]
    set -l branch $argv[2]
    set -l base (__project_default $main)
    set -l parent (git -C $main config --get branch.$branch.projectBase)
    set -l refs refs/heads/$base refs/remotes/origin/$base
    test -n "$parent"; and set --append refs refs/heads/$parent refs/remotes/origin/$parent
    for ref in $refs
      git -C $main merge-base --is-ancestor $branch $ref 2>/dev/null; and return 0
    end
    return 1
  '';

  # what the argument at the cursor can be, by subcommand and position: projects, then the worktrees and
  # branches of the project named before it; `__project_complete from` lists the bases that --from takes
  programs.fish.functions.__project_complete = ''
    set -l tokens (commandline --tokens-expanded --cut-at-cursor)
    set -l action $tokens[2]
    set -l current (commandline --current-token)
    # the positional arguments before the cursor: options, and the values of those that take one, don't count
    set -l args
    set -l value false
    for token in $tokens[3..]
      if test $value = true
        set value false
      else if contains -- $token --from --as --permission-mode
        set value true
      else if not string match --quiet -- '-*' $token
        set --append args $token
      end
    end
    set -l position (math (count $args) + 1)
    # ./name, ~/name and a/b are paths, not names
    set -l pathlike false
    string match --quiet --regex '^[.~]|/' -- $current; and set pathlike true

    switch $action
      case open add spawn
        if test "$argv[1]" != from; and test $position -eq 1
          if test $pathlike = true
            __fish_complete_directories $current
            return
          end
          for entry in $HOME/projects/*/
            if test -d $entry/main/.git
              printf '%s\tproject\n' (path basename $entry)
            else if test -e $entry/.git
              printf '%s\tplain repo\n' (path basename $entry)
            end
          end
          return
        end
        test "$argv[1]" = from; or test $position -eq 2; or return
        # the project, resolved as `project` resolves it
        set -l dir $args[1]
        if test -z "$dir"
          set dir .
        else if not string match --quiet --regex '[/~]|^\.+$' -- $dir
          set dir $HOME/projects/$dir
        end
        set dir (path resolve $dir)
        if test -d (path dirname $dir)/main/.git; and not test -d $dir/main/.git
          set dir (path dirname $dir)
        end
        set -l main $dir/main
        test -d $main/.git; or return
        # worktrees first, then local branches, then remote ones; the branch of main/ is the bare
        # `project open <dir>`, so only --from lists it
        set -l seen
        test "$argv[1]" = from; or set seen (git -C $main branch --show-current 2>/dev/null)
        set -l found
        for line in (git -C $main worktree list --porcelain 2>/dev/null)
          string match --quiet 'worktree *' -- $line; and set found (string sub --start 10 -- $line)
          string match --quiet 'branch refs/heads/*' -- $line; or continue
          set -l branch (string sub --start 19 -- $line)
          contains -- $branch $seen; and continue
          set --append seen $branch
          printf '%s\tworktree %s\n' $branch (path basename $found)
        end
        for branch in (git -C $main for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
          contains -- $branch $seen; and continue
          set --append seen $branch
          printf '%s\tbranch\n' $branch
        end
        for branch in (git -C $main for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin 2>/dev/null)
          test $branch = HEAD; and continue
          contains -- $branch $seen; and continue
          printf '%s\tremote branch\n' $branch
        end

      case close discard
        test $position -eq 1; or return
        # the project this runs in, found as `project close` finds it; outside one, only paths work
        set -l dir
        if test -d main/.git
          set dir $PWD
        else
          set -l top (git rev-parse --show-toplevel 2>/dev/null)
          test -n "$top"; and test -d (path dirname $top)/main/.git; and set dir (path dirname $top)
        end
        if test $pathlike = true; or test -z "$dir"
          __fish_complete_directories $current
          return
        end
        set -l found
        for line in (git -C $dir/main worktree list --porcelain 2>/dev/null)
          string match --quiet 'worktree *' -- $line; and set found (string sub --start 10 -- $line)
          string match --quiet 'branch refs/heads/*' -- $line; or continue
          test $found != $dir/main; and test (path dirname $found) = $dir; or continue
          printf '%s\tbranch %s\n' (path basename $found) (string sub --start 19 -- $line)
        end

      case clean convert
        test $position -eq 1; and __fish_complete_directories $current
    end
  '';

  xdg.configFile."fish/completions/project.fish".text = ''
    complete -c project -f
    complete -c project -n __fish_use_subcommand -a open -d "open a project, or a branch of it as a worktree"
    complete -c project -n __fish_use_subcommand -a add -d "make a worktree and print its path, without opening it"
    complete -c project -n __fish_use_subcommand -a close -d "remove a worktree and its merged branch"
    complete -c project -n __fish_use_subcommand -a discard -d "close a worktree and throw away its uncommitted work (interactive only)"
    complete -c project -n __fish_use_subcommand -a spawn -d "make a worktree and start a Claude session in an ide window of its own"
    complete -c project -n __fish_use_subcommand -a clean -d "fast-forward main, close merged worktrees, delete merged branches"
    complete -c project -n __fish_use_subcommand -a convert -d "move a plain repo into <repo>/main"
    complete -c project -n "not __fish_use_subcommand" -k -a "(__project_complete)"
    complete -c project -n "__fish_seen_subcommand_from clean" -s n -l dry-run -d "only list what would happen"
    complete -c project -n "__fish_seen_subcommand_from clean" -l gone -d "also clean branches whose remote branch is deleted (squash merges)"
    complete -c project -n "__fish_seen_subcommand_from spawn" -l headless -d "start the session in the background, with no window"
    complete -c project -n "__fish_seen_subcommand_from spawn" -l permission-mode -x -a "acceptEdits auto bypassPermissions dontAsk manual plan" -d "permission mode of the session"
    complete -c project -n "__fish_seen_subcommand_from open add spawn" -l as -x -d "directory name of the worktree, instead of the branch name"
    complete -c project -n "__fish_seen_subcommand_from open add spawn" -l from -x -k -a "(__project_complete from)"
  '';
}
