{
  config,
  homebrew-cask,
  homebrew-core,
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
      "discord"
      "firefox"
      "obsidian"
      "opencode-desktop"
      "prismlauncher"
      "private-internet-access"
      "scroll-reverser"
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
