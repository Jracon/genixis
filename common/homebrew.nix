{
  config,
  homebrew-cask,
  homebrew-core,
  nix-homebrew,
  ...
}:

{
  homebrew = {
    enable = true;
    taps = builtins.attrNames config.nix-homebrew.taps;

    brews = [
      "mas"
    ];

    casks = [
      "firefox"
      "obsidian"
      "private-internet-access"
      "spotify"
      "steam"
      "syncthing-app"
    ];

    masApps = {
      "Bitwarden" = 1352778147;
      "Infuse" = 1136220934;
      "Tailscale" = 1475387142;
    };

    onActivation = {
      cleanup = "zap";
      upgrade = true;
    };
  };

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    mutableTaps = false;
    user = "jademeskill";

    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
    };
  };
}
