{
  config,
  lib,
  pkgs,
  ...
}:

{
  # default for every program's enableFishIntegration option
  home.shell.enableFishIntegration = true;

  programs.fish = {
    enable = true;

    generateCompletions = true;
    interactiveShellInit = ''
      # disable greeting
      set fish_greeting
    '';
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
    shellInit = ''
      function local-rebuild
        ${
          if pkgs.stdenv.hostPlatform.isDarwin then
            "sudo darwin-rebuild switch --flake .#$argv[1]"
          else
            "sudo nixos-rebuild switch --impure --flake .#$argv[1]"
        }
      end

      function rebuild
        ${
          if pkgs.stdenv.hostPlatform.isDarwin then
            "sudo darwin-rebuild switch --flake github:jracon/genixis#$argv[1]"
          else
            "sudo nixos-rebuild switch --impure --flake github:jracon/genixis#$argv[1]"
        }
      end
    ''
    # NixOS/Darwin hosts apply Home Manager through rebuild; only standalone setups need rehome
    + lib.optionalString (!config.submoduleSupport.enable) ''
      function local-rehome
        home-manager switch -b backup --impure --flake .#$argv[1]
      end

      function rehome
        home-manager switch -b backup --impure --flake github:jracon/genixis#$argv[1]
      end
    ''
    + lib.optionalString (!pkgs.stdenv.hostPlatform.isDarwin) ''
      # automatically start tmux session
      if test -z "$TMUX"; and status is-interactive
        tmux new -As main
      end
    '';
  };
}
