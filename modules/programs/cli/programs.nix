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

    git.enable = true;

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
