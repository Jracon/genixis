{
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

    shellAliases = {
      cat = "bat";
      ls = "eza";
    };
  };
}
