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
      # set vscode as the default editor
      set -x EDITOR "code -w"

      function local-rebuild
        ${
          if pkgs.stdenv.isDarwin then
            "sudo darwin-rebuild switch --flake .#$argv[1]"
          else
            "nixos-rebuild switch --impure --flake .#$argv[1]"
        }
      end

      function local-rehome
        home-manager switch --impure --flake .#$argv[1]
      end

      function rebuild
        ${
          if pkgs.stdenv.isDarwin then
            "sudo darwin-rebuild switch --flake github:jracon/genixis#$argv[1]"
          else
            "nixos-rebuild switch --impure --flake github:jracon/genixis#$argv[1]"
        }
      end

      function rehome
        home-manager switch --impure --flake github:jracon/genixis#$argv[1]
      end
    ''
    + (
      if !pkgs.stdenv.isDarwin then
        ''
          # automatically start tmux session
          if test -z "$TMUX"; and status is-interactive
            tmux new -As main
          end
        ''
      else
        ''
          # enable pyenv
          set -Ux PYENV_ROOT $HOME/.pyenv
          test -d $PYENV_ROOT/bin; and fish_add_path $PYENV_ROOT/bin
          pyenv init - fish | source
        ''
    );
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
  };
}
