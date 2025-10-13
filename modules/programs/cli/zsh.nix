{
  ...
}:

{
  programs.zsh = {
    enable = true;

    shellAliases = {
      cat = "bat";
      ls = "eza -lha";
    };
  };
}
