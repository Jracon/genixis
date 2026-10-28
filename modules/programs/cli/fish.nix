{
  config,
  lib,
  osConfig ? null, # the NixOS/nix-darwin config; absent in standalone homeConfigurations
  pkgs,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  os = if osConfig == null then { } else osConfig;

  # plain-word commands are gated on the tool actually being there, not just the platform
  hasGraphicalDesktop = !isDarwin && (os.services.graphical-desktop.enable or false);
  hasPodman = os.virtualisation.podman.enable or false;

  # nh shows a package diff before switching and elevates with sudo itself; `nh os` refuses to
  # run as root (servers log in as root), so skip elevation there instead
  rebuildFrom = flake: extraArgs: ''
    ${
      if isDarwin then
        "nh darwin switch ${flake} --hostname $argv[1] --impure ${extraArgs}"
      else
        ''
          set -l elevation
          fish_is_root_user; and set elevation --elevation-strategy none
          nh os switch ${flake} --hostname $argv[1] --impure $elevation ${extraArgs}''
    }
  '';
  rehomeFrom = flake: extraArgs: ''
    nh home switch ${flake} --configuration $argv[1] --backup-extension backup --impure ${extraArgs}
  '';

  # Forgejo is the origin but LAN-only (unreachable from WSL behind the work VPN), so fall back to
  # the GitHub mirrors, over git+https since github: refs go through the rate-limited GitHub API.
  # The lock still points themes at Forgejo, so redirect it to its mirror at the locked revision.
  # Nix caches which commit a branch URL points to for an hour (tarball-ttl), so --refresh makes a
  # rebuild right after a push build that push, not the commit an earlier rebuild saw
  remoteFlake = ''
    set -l flake git+https://forgejo.local.jracon.xyz/jracon/genixis
    set -l extra_args --refresh
    if not ${lib.getExe pkgs.curl} --head --max-time 3 --silent https://forgejo.local.jracon.xyz >/dev/null
      echo "Forgejo is unreachable; using the GitHub mirror" >&2
      set flake git+https://github.com/jracon/genixis
      set -l themes_rev (nix flake metadata --refresh $flake --json | ${lib.getExe pkgs.jq} --exit-status --raw-output .locks.nodes.themes.locked.rev)
      or return
      set extra_args --refresh -- --override-input themes "git+https://github.com/jracon/themes?rev=$themes_rev"
    end
  '';
in
{
  # default for every program's enableFishIntegration option
  home.shell.enableFishIntegration = true;

  programs.fish = {
    enable = true;

    functions = {
      cln = "nh clean all --keep 5 --keep-one";
      # with no file, open nvim's file picker
      e = ''
        if test (count $argv) -eq 0
          nvim +"FzfLua files"
        else
          nvim $argv
        end
      '';
      # IDE-style tmux window for a project: yazi | nvim over a shell | claude; prefix+g is lazygit.
      # Inside tmux it's a tab of the current session (this one, if it's a lone pane); outside, a session of its own.
      # `ide [--detach <session>] [dir] [title] [claude args...]`: the title defaults to the directory's name; `ide close` closes the ide window it runs in,
      # `ide reload` picks up a rebuild in it (tmux config, nvim with its tabs, yazi), `ide pop` moves the current tmux window
      # into a new WezTerm window (a session of its own)
      ide = ''
        if test "$argv[1]" = pop
          if not set -q TMUX_PANE
            echo "ide: pop runs inside tmux" >&2
            return 1
          end
          if not command -q wezterm
            echo "ide: wezterm isn't installed" >&2
            return 1
          end
          # moving a session's only window would destroy the session, and this client with it
          if test (command tmux display-message -p -t "$TMUX_PANE" '#{session_windows}') -eq 1
            echo "ide: this is the only window of its session; open a second WezTerm window with `tmux new -s <name>`" >&2
            return 1
          end
          set -l window (command tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
          set -l name (command tmux display-message -p -t "$TMUX_PANE" '#{window_name}' | string replace --all --regex '[.:]' -)
          set -l session "pop-$name-"(string replace @ "" $window)
          # `sleep` keeps the new session's first window away from fish, which would attach tmux inside it
          set -l placeholder (command tmux new-session -dP -F '#{window_id}' -s $session 'sleep 60')
          command tmux move-window -s $window -t "$session:"
          command tmux kill-window -t $placeholder
          command wezterm start -- tmux attach -t $session >/dev/null 2>&1 &
          disown
          return
        end

        if contains -- "$argv[1]" close reload
          set -l editor (command tmux show-option -wqv -t "$TMUX_PANE" @ide_editor 2>/dev/null)
          if test -z "$editor"
            echo "ide: $argv[1] runs inside an ide window" >&2
            return 1
          end
          set -l sock (command tmux show-option -wqv -t $editor @ide_sock)
          if test -S "$sock"
            set -l unsaved (nvim --headless --server $sock --remote-expr "luaeval('#vim.fn.getbufinfo({bufmodified = 1})')")
            if test "$unsaved" -gt 0 2>/dev/null
              echo "ide: nvim has $unsaved unsaved buffer(s); write or discard them first" >&2
              command tmux select-pane -t $editor
              return 1
            end
          end
          # a viewer standing in for nvim (ide-view) has nvim's pane in a throwaway session: swap it back
          set -l viewer (command tmux show-option -pqv -t $editor @ide_viewer)
          if test -n "$viewer"; and command tmux swap-pane -s $viewer -t $editor 2>/dev/null
            command tmux kill-pane -t $viewer
          end
          if test "$argv[1]" = close
            # last: this ends the shell running it, and the session if it was the only window
            command tmux kill-window -t $editor
            return
          end

          # tmux: new options and bindings apply at once; removed ones linger until the server restarts
          command tmux source-file -q (command tmux display-message -p '#{config_files}' | string split ,)

          # nvim: save its tabs and windows, quit, and start the new one on the same socket. The session
          # leaves out options, which would bring back the old runtimepath (and so the old config)
          set -l session (string replace --regex '\.sock$' .vim -- $sock)
          rm -f $session
          if test -S "$sock"
            nvim --headless --server $sock --remote-expr "execute('set sessionoptions-=blank sessionoptions-=options | mksession! $session')" >/dev/null
            nvim --headless --server $sock --remote-send '<C-\><C-N>:qa<CR>'
            for i in (seq 50)
              test -S $sock; or break
              sleep 0.1
            end
            if test -S $sock
              echo "ide: nvim didn't quit; reload it by hand" >&2
              command tmux select-pane -t $editor
              return 1
            end
          end
          set -l nvim nvim --listen $sock
          test -f $session; and set -a nvim -S $session -c "call delete(v:this_session)"
          command tmux send-keys -t $editor (string join -- " " (string escape -- $nvim)) Enter

          # yazi: a fresh shell in its pane, in the directory it was showing
          set -l files (command tmux show-option -wqv -t $editor @ide_files)
          command tmux respawn-pane -k -t $files -c (command tmux display-message -p -t $files '#{pane_current_path}') \
            -e IDE_EDITOR_PANE=$editor -e IDE_NVIM_SOCK=$sock
          command tmux send-keys -t $files y Enter

          ide-layout $editor
          # claude is left running (it may be the one reloading); /exit and `claude --continue` restarts it
          echo "ide: reloaded tmux, nvim and yazi; restart claude with /exit and `claude --continue`, and shells with `exec fish`"
          return
        end

        # `--detach <session>` is for scripts and agents (`project spawn`): it never attaches or switches windows
        # here; the window goes into that session (one per project, so a project's worktrees share a WezTerm window)
        set -l detach false
        set -l session
        if test "$argv[1]" = --detach
          set detach true
          set session $argv[2]
          set argv $argv[3..]
        end
        set -l dir (path resolve (test (count $argv) -gt 0; and echo $argv[1]; or echo .))
        set -l name (test -n "$argv[2]"; and echo $argv[2]; or path basename $dir)
        # tmux session names can't hold . or :
        set session (string replace --all --regex '[.:\s]+' _ -- (test -n "$session"; and echo $session; or echo $name))
        set -l editor

        if $detach
          for window in (command tmux list-windows -a -F '#{window_id} #{@ide_dir}' 2>/dev/null)
            set -l parts (string split --max 1 ' ' -- $window)
            if test "$parts[2]" = $dir
              echo "ide: $dir already has an ide window" >&2
              return 1
            end
          end
          if command tmux has-session -t =$session 2>/dev/null
            set editor (command tmux new-window -d -P -F '#{pane_id}' -t "=$session:" -n $name -c $dir); or return
          else
            # size it like the current window, if any; the client-attached hook re-proportions the panes anyway
            set -l size
            set -q TMUX; and set size -x (command tmux display-message -p '#{window_width}') -y (command tmux display-message -p '#{window_height}')
            set editor (command tmux new-session -d -P -F '#{pane_id}' -s $session -c $dir -n $name $size); or return
          end
        else if set -q TMUX
          for window in (command tmux list-windows -F '#{window_id} #{@ide_dir}')
            set -l parts (string split --max 1 ' ' -- $window)
            if test "$parts[2]" = $dir
              command tmux select-window -t $parts[1]
              return
            end
          end
          if test (command tmux display-message -p -t $TMUX_PANE '#{window_panes}') -eq 1
            set editor $TMUX_PANE
            cd $dir
            command tmux rename-window -t $editor $name
          else
            set editor (command tmux new-window -P -F '#{pane_id}' -n $name -c $dir)
          end
        else if command tmux has-session -t =$session 2>/dev/null
          command tmux attach -t =$session
          return
        else
          # size the detached session like this terminal; at the 80x24 default, attaching would scale 30 columns up proportionally
          set editor (command tmux new-session -d -P -F '#{pane_id}' -s $session -c $dir -n $name -x (tput cols) -y (tput lines))
        end

        # per pane, not per session, so several ide windows can share a session
        set -l sock (set -q TMPDIR; and echo $TMPDIR; or echo /tmp)/nvim-ide-(command tmux display-message -p -t $editor '#{pid}-#{pane_id}' | string replace % "").sock
        rm -f $sock
        set -l env -e IDE_EDITOR_PANE=$editor -e IDE_NVIM_SOCK=$sock
        set -l files (command tmux split-window $env -P -F '#{pane_id}' -h -b -l 30 -t $editor -c $dir)
        set -l agent (command tmux split-window $env -P -F '#{pane_id}' -h -l 30% -t $editor -c $dir)
        set -l shell (command tmux split-window $env -P -F '#{pane_id}' -v -l 20% -t $editor -c $dir)
        command tmux set-option -w -t $editor @ide_agent $agent
        command tmux set-option -w -t $editor @ide_dir $dir
        command tmux set-option -w -t $editor @ide_editor $editor
        command tmux set-option -w -t $editor @ide_files $files
        command tmux set-option -w -t $editor @ide_shell $shell
        command tmux set-option -w -t $editor @ide_sock $sock
        command tmux send-keys -t $files y Enter
        # typed-ahead input waits in the tty's line buffer until fish starts, and macOS drops what passes ~1 KiB
        # (the Enter with it), so a long claude command goes through a script that removes itself; the leading
        # space keeps that line out of the history
        set -l start (string replace --regex -- '\.sock$' -claude.fish $sock)
        printf '%s\n' "command rm -f $(string escape -- $start)" (string join -- " " claude (string escape -- $argv[3..])) >$start
        command tmux send-keys -t $agent " source $(string escape -- $start)" Enter
        command tmux select-pane -t $editor

        if $detach
          command tmux send-keys -t $editor "nvim --listen $sock" Enter
          ide-layout $editor
          # a session that a terminal already shows lists the new window in its status bar; otherwise it gets a
          # WezTerm window of its own (no GUI over ssh: the session waits for `tmux attach`)
          if test (command tmux display-message -p -t "=$session:" '#{session_attached}') -gt 0
            return
          else if command -q wezterm; and not set -q SSH_CONNECTION
            command env -u TMUX -u TMUX_PANE wezterm start -- tmux attach -t =$session >/dev/null 2>&1 &
            disown
          else
            echo "ide: no WezTerm here; attach with `tmux attach -t =$session`" >&2
          end
        else if not set -q TMUX
          command tmux send-keys -t $editor "nvim --listen $sock" Enter
          command tmux attach -t =$session
        else
          ide-layout $editor
          if test $editor = $TMUX_PANE
            nvim --listen $sock
          else
            command tmux send-keys -t $editor "nvim --listen $sock" Enter
          end
        end
      '';
      local-rebuild = rebuildFrom "." "";
      rebuild = remoteFlake + rebuildFrom "$flake" "$extra_args";
      # bare `tmux` attaches to (or creates) session main, or ssh over ssh so a remote login doesn't
      # join the local terminal's session; subcommands like `tmux ls` pass through
      tmux = ''
        if test (count $argv) -eq 0
          command tmux new -As (set -q SSH_CONNECTION; and echo ssh; or echo main)
        else
          command tmux $argv
        end
      '';
    }
    // lib.optionalAttrs hasPodman {
      lgs = "journalctl --follow --unit podman-$argv[1]";
    }
    # NixOS/Darwin hosts apply Home Manager through rebuild; only standalone setups need rehome
    // lib.optionalAttrs (!config.submoduleSupport.enable) {
      local-rehome = rehomeFrom "." "";
      rehome = remoteFlake + rehomeFrom "$flake" "$extra_args";
    };
    generateCompletions = true;
    # plain-word commands: abbreviations expand to the real command as you type, so you still
    # learn the underlying tool and history records it; they only apply at the start of a command
    shellAbbrs = {
      b = "y"; # yazi
      dl = "delta";
      g = "z"; # zoxide; `zi` for an interactive picker
      iss = "gh issue list";
      json = "jq";
      l = "fd";
      lg = "lazygit";
      monitor = "btm";
      prc = "gh pr checkout";
      prs = "gh pr list";
      r = "bat";
      search = "rg";
    }
    // lib.optionalAttrs config.programs.lazydocker.enable {
      ld = "lazydocker";
    }
    // lib.optionalAttrs hasGraphicalDesktop {
      open = "xdg-open"; # macOS has its own open
    };
    interactiveShellInit = ''
      # disable greeting
      set fish_greeting

      # WezTerm types Enter + Ctrl-D into a pane it closes (Cmd+Q); under tmux the client forwards them
      # to the focused pane, so there Ctrl-D only deletes and never exits the shell (use `exit`)
      if set -q TMUX
        bind ctrl-d delete-char
      end

      # Shift+arrows skip words (WezTerm's CSI-u encoding keeps the modifier through tmux)
      bind shift-left backward-word
      bind shift-right forward-word
    ''
    + lib.optionalString (!isDarwin) ''
      # automatically start tmux session
      if not set -q TMUX
        tmux
      end
    '';
    # drop-in replacements keep the familiar name (ls/ll/la/lt come from programs.eza)
    shellAliases.cat = "bat";
  };
}
