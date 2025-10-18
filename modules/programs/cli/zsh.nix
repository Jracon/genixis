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

    shellAliases = {
      cat = "bat";
      ls = "eza";
    };
  };
}
