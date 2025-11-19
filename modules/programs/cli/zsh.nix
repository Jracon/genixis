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

    initContent =
      if !pkgs.stdenv.isDarwin then
        ''
          if [ -z "$TMUX" ] && [ -t 1 ] && [ -n "$PS1" ]; then
            tmux new -As main
          fi
        ''
      else
        "";
    shellAliases = {
      cat = "bat";
      ls = "eza";
      tmux = "tmux new -As main";
    };
  };
}
