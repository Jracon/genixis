{
  ...
}:

{
  environment.shellAliases = {
    cat = "bat";
    ls = "eza -lha"
  };

  programs = {
    bat.enable = true;

    eza = {
      enable = true;

      icons = "auto";
      colors = "auto";
      git = true;
      extraOptions = [
        "--group-directories-first"
        "--group"
        "--all"
      ];
    };

    neovim = {
      enable = true;
    };

    starship = {
      enable = true;
    };

    tmux = {
      enable = true;
    };
  };
}
