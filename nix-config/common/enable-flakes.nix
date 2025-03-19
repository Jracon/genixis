{
  pkgs,
  ...
}:

{
  environment = {
    # flakes require git for cloning dependencies
    systemPackages = with pkgs; [
      git
    ];
  };

  # enable the Nix command line tool and flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
