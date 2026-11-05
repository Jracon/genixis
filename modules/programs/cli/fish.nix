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

  # on Darwin only launchd starts the tmux server (tmux.nix): a server that a WezTerm starts loses the
  # LAN when that WezTerm quits. -N makes a client fail instead of starting one
  tmuxLabel = config.launchd.agents.tmux.config.Label;
  tmuxNoStart = lib.optionalString isDarwin "-N ";
  tmuxServerCheck = lib.optionalString isDarwin "tmux-server; or return";

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
      # in an ide window, edit secrets in its nvim pane (ide-edit blocks until the buffer closes)
      agenix = ''
        if set -q IDE_NVIM_SOCK
          EDITOR=ide-edit command agenix $argv
        else
          command agenix $argv
        end
      '';
      cln = "nh clean all --keep 5 --keep-one";
      # with no file, open nvim's file picker
      e = ''
        if test (count $argv) -eq 0
          nvim +"FzfLua files"
        else
          nvim $argv
        end
      '';
      # fish calls this for the pane title: push the working directory, so the
      # home tab of a host window shows where its shell works and the title
      # follows a cd (issue #135); the tilde keeps the home directory short
      fish_title = ''
        if test "$PWD" = "$HOME"
            echo "~"
        else
            echo (string replace -- "$HOME/" "~/" "$PWD")
        end
      '';
      # the Go binary builds the ide window (`project ide`, see AGENTS.md); this stub adds the one
      # thing a child process cannot do: when a lone-pane window becomes the ide window, the shell
      # of the caller changes into the directory, which the binary writes to PROJECT_CD_FILE and
      # this stub reads after the binary ends
      ide = ''
        set -l cdfile (mktemp)
        set -lx PROJECT_CD_FILE $cdfile
        command project ide $argv
        set -l st $status
        if test -s $cdfile
            cd (cat $cdfile)
        end
        command rm -f $cdfile
        return $st
      '';
      # Nix refuses a git checkout that another user owns (root rebuilding from dev's checkout), so
      # read it as plain files there; a path: flake also takes untracked files and needs the repo root
      local-rebuild = ''
        set -l flake .
        test -O .; or set flake path:$PWD
      ''
      + rebuildFrom "$flake" "";
      rebuild = remoteFlake + rebuildFrom "$flake" "$extra_args";
      # bare `tmux` attaches to (or creates) session main, or ssh over ssh so a remote login doesn't
      # join the local terminal's session; subcommands like `tmux ls` pass through. launchd doesn't own
      # a socket that -L or -S names, so those stay free to start a server on Darwin
      tmux = ''
        if test (count $argv) -eq 0
          ${tmuxServerCheck}
          command tmux ${tmuxNoStart}new -As (set -q SSH_CONNECTION; and echo ssh; or echo main)
        ${lib.optionalString isDarwin ''
          else if not contains -- "$argv[1]" -L -S
            command tmux -N $argv
        ''}
        else
          command tmux $argv
        end
      '';
    }
    // lib.optionalAttrs isDarwin {
      # succeeds when the default socket has a server; `start-server` with -N only asks
      tmux-server = ''
        command tmux -N start-server 2>/dev/null; and return
        echo "tmux: no server; launchd starts it. Run `launchctl kickstart gui/$(id -u)/${tmuxLabel}`, or read ~/Library/Logs/tmux-server.log" >&2
        return 1
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
      # automatically start tmux session; PROJECT_HOME_TAB marks a tab that must
      # keep a plain shell: the attach would redraw the pane and wipe the fastfetch
      # output of the home tab (issue #134), and a detach in a session tab must not
      # start a second attach (issue #142)
      if not set -q TMUX; and not set -q PROJECT_HOME_TAB
        tmux
      end
    '';
    # drop-in replacements keep the familiar name (ls/ll/la/lt come from programs.eza)
    shellAliases.cat = "bat";
  };
}
