{
  pkgs,
  ...
}:

{
  programs.fish = {
    enable = true;

    generateCompletions = true;

    interactiveShellInit = ''
      # disable greeting
      set fish_greeting
    '';
    shellInit = ''
      function local-rebuild
        ${
          if pkgs.stdenv.hostPlatform.isDarwin then
            "sudo darwin-rebuild switch --flake .#$argv[1]"
          else
            "nixos-rebuild switch --impure --flake .#$argv[1]"
        }
      end

      function local-rehome
        home-manager switch -b backup --impure --flake .#$argv[1]
      end

      function rebuild
        ${
          if pkgs.stdenv.hostPlatform.isDarwin then
            "sudo darwin-rebuild switch --flake github:jracon/genixis#$argv[1]"
          else
            "nixos-rebuild switch --impure --flake github:jracon/genixis#$argv[1]"
        }
      end

      function rehome
        home-manager switch -b backup --impure --flake github:jracon/genixis#$argv[1]
      end
    ''
    + (
      if !pkgs.stdenv.hostPlatform.isDarwin then
        ''
          # automatically start tmux session
          if test -z "$TMUX"; and status is-interactive
            tmux new -As main
          end
        ''
      else
        ''
          # set vscodium as the default editor
          set -x EDITOR "codium -w"
        ''
    );
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
  };
}
