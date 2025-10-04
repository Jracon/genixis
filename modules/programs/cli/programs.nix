{
  pkgs, 
  ...
}:

{
  home.packages = with pkgs; [ 
    bitwarden-cli 
    tailscale 
  ]; 

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

    git = {
      enable = true;

      userName = "Jade Isaiah Meskill";
      userEmail = "jade.isaiah@gmail.com";
    };

    neovim.enable = true;

    starship.enable = true;

    tmux.enable = true;

    zsh = {
      enable = true;

      shellAliases = {
        cat = "bat";
        ls = "eza -lha";
      };
    };
  };
}
