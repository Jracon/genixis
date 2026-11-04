{
  pkgs,
  ...
}:

{
  # fastfetch prints the OS logo and the system information in the home tab
  # of the host WezTerm window (wezterm-attach of the project tool starts
  # it); no shell of this configuration runs it anywhere else
  home.packages = [
    pkgs.fastfetch
  ];
}
