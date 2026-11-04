{
  pkgs,
  ...
}:

{
  # fastfetch prints the OS logo and the system information in the home tab
  # of the host WezTerm window (wezterm-attach of the project tool starts
  # it); no shell of this configuration runs it anywhere else; the cli set
  # loads on every platform, so every host and every standalone home
  # installs the package (issue #131)
  home.packages = [
    pkgs.fastfetch
  ];
}
