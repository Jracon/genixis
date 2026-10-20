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
      cleanup = "nh clean all --keep 5";
      # with no file, open nvim's file picker
      edit = ''
        if test (count $argv) -eq 0
          nvim +"FzfLua files"
        else
          nvim $argv
        end
      '';
      local-rebuild = rebuildFrom ".";
      rebuild = rebuildFrom "github:jracon/genixis";
    }
    // lib.optionalAttrs hasPodman {
      logs = "journalctl --follow --unit podman-$argv[1]";
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
      browse = "y"; # yazi
      changes = "lazygit";
      compare = "delta";
      goto = "z"; # zoxide; `zi` for an interactive picker
      issues = "gh issue list";
      json = "jq";
      locate = "fd"; # shadows /usr/bin/locate interactively; `command locate` still reaches it
      monitor = "btm";
      prs = "gh pr list";
      read = "bat"; # shadows fish's `read` builtin interactively only; scripts are unaffected
      review = "gh pr checkout";
      search = "rg";
    }
    // lib.optionalAttrs config.programs.lazydocker.enable {
      containers = "lazydocker";
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
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
  };
}
