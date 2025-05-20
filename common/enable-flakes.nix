{
  pkgs,
  ...
}:

{
  # git is required to use flakes
  environment.systemPackages = with pkgs; [
    git
  ];

  # enable the Nix command line tool and flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
