{
  pkgs,
  ...
}:

{
  # git is required to use flakes
  environment.systemPackages = [
    pkgs.git
  ];

  # enable the Nix command line tool and flakes
  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];
}
