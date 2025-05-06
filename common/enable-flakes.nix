{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    git
  ];

  # enable the Nix command line tool and flakes
  nix = {
    optimise.automatic = true;

    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
