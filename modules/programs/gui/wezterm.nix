{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    wezterm
  ];

  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };
}
