{
  programs.zsh = {
    enable = true;

    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    sessionVariables.EDITOR = "code -w";
    syntaxHighlighting.enable = true;

    initContent = ''
      if [ -z "$TMUX" ] && [ -t 1 ] && [ -n "$PS1" ]; then
        tmux new -As main
      fi
    '';
    shellAliases = {
      cat = "bat";
      ls = "eza";
    };
  };
}
