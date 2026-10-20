{
  config,
  lib,
  pkgs,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

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
      local-rebuild = rebuildFrom ".";
      rebuild = rebuildFrom "github:jracon/genixis";
    }
    # NixOS/Darwin hosts apply Home Manager through rebuild; only standalone setups need rehome
    // lib.optionalAttrs (!config.submoduleSupport.enable) {
      local-rehome = rehomeFrom ".";
      rehome = rehomeFrom "github:jracon/genixis";
    };
    generateCompletions = true;
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
