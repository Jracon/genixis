{
  pkgs,
  ...
}:

{
  programs.zsh = {
    enable = true;

    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    sessionVariables.EDITOR = "code -w";
    syntaxHighlighting.enable = true;

    initContent = ''
      function local-rebuild {
        ${if pkgs.stdenv.isDarwin then "sudo darwin" else "nixos"}-rebuild switch ${
          if pkgs.stdenv.isLinux then "--impure" else ""
        } --flake .#$1
      }

      function local-rehome {
        home-manager switch --impure --flake .#$1
      }

      function rebuild {
        ${if pkgs.stdenv.isDarwin then "sudo darwin" else "nixos"}-rebuild switch ${
          if pkgs.stdenv.isLinux then "--impure" else ""
        } --flake github:jracon/genixis#$1
      }

      function rehome {
        home-manager switch --impure --flake github:jracon/genixis#$1
      }''
    + (
      if !pkgs.stdenv.isDarwin then
        ''


          if [ -z "$TMUX" ] && [ -t 1 ] && [ -n "$PS1" ]; then
            tmux new -As main
          fi
        ''
      else
        ""
    );
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
  };
}
