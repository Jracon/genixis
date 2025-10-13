{
  ...
}:

{
  programs.zsh = {
    enable = true;
    autocd = true;
    enableCompletion = true;

    shellAliases = {
      cat = "bat";
      ls = "eza";
    };
  };
}
