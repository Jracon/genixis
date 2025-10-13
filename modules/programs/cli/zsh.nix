{
  ...
}:

{
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    shellAliases = {
      cat = "bat";
      ls = "eza";
    };
  };
}
