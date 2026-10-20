{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    bitwarden-cli
    tailscale
  ];

  # programs with no configuration beyond enable
  programs = {
    bottom.enable = true;
    lazygit.enable = true;
    zoxide.enable = true;
  };
}
