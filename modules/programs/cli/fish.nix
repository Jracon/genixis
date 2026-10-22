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
  rebuildFrom = flake: ''
    ${
      if isDarwin then
        "nh darwin switch ${flake} --hostname $argv[1]"
      else
        ''
          set -l elevation
          fish_is_root_user; and set elevation --elevation-strategy none
          nh os switch ${flake} --hostname $argv[1] --impure $elevation''
    }
  '';
  rehomeFrom = flake: ''
    nh home switch ${flake} --configuration $argv[1] --backup-extension backup --impure
  '';
in
{
  # default for every program's enableFishIntegration option
  home.shell.enableFishIntegration = true;

  programs.fish = {
    enable = true;

    functions = {
      cln = "nh clean all --keep 5";
      # with no file, open nvim's file picker
      e = ''
        if test (count $argv) -eq 0
          nvim +"FzfLua files"
        else
          nvim $argv
        end
      '';
      # IDE-style tmux session for a project: yazi | nvim over a shell | claude; prefix+g is lazygit
      ide = ''
        set -l dir (path resolve (test (count $argv) -gt 0; and echo $argv[1]; or echo .))
        set -l name (path basename $dir | string replace --all --regex '[.:]' _)
        set -l sock (set -q TMPDIR; and echo $TMPDIR; or echo /tmp)/nvim-ide-$name.sock

        if not command tmux has-session -t =$name 2>/dev/null
          rm -f $sock
          # size the detached session like this terminal; at the 80x24 default, attaching would scale 30 columns up proportionally
          command tmux new-session -d -s $name -c $dir -x (tput cols) -y (tput lines)
          set -l editor (command tmux display-message -p -t $name '#{pane_id}')
          command tmux set-environment -t $name IDE_NVIM_SOCK $sock
          command tmux set-environment -t $name IDE_EDITOR_PANE $editor
          set -l files (command tmux split-window -P -F '#{pane_id}' -h -b -l 30 -t $editor -c $dir)
          set -l agent (command tmux split-window -P -F '#{pane_id}' -h -l 30% -t $editor -c $dir)
          set -l shell (command tmux split-window -P -F '#{pane_id}' -v -l 20% -t $editor -c $dir)
          command tmux set-option -w -t $name @ide_agent $agent
          command tmux set-option -w -t $name @ide_files $files
          command tmux set-option -w -t $name @ide_shell $shell
          command tmux send-keys -t $files y Enter
          command tmux send-keys -t $agent claude Enter
          command tmux send-keys -t $editor "nvim --listen $sock" Enter
          command tmux select-pane -t $editor
        end

        if set -q TMUX
          command tmux switch-client -t =$name
        else
          command tmux attach -t =$name
        end
      '';
      local-rebuild = rebuildFrom ".";
      rebuild = rebuildFrom "github:jracon/genixis";
      # bare `tmux` attaches to (or creates) session main; subcommands like `tmux ls` pass through
      tmux = ''
        if test (count $argv) -eq 0
          command tmux new -As main
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
      local-rehome = rehomeFrom ".";
      rehome = rehomeFrom "github:jracon/genixis";
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
    ''
    + lib.optionalString (!isDarwin) ''
      # automatically start tmux session
      if not set -q TMUX
        tmux new -As main
      end
    '';
    # drop-in replacements keep the familiar name (ls/ll/la/lt come from programs.eza)
    shellAliases.cat = "bat";
  };
}
