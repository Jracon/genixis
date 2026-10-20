{
  config,
  homebrew-cask,
  homebrew-core,
  user,
  ...
}:

{
  homebrew = {
    enable = true;

    brews = [
      "mas"
    ];
    casks = [
      "discord"
      "element"
      "firefox"
      "obsidian"
      "prismlauncher"
      "private-internet-access"
      "retroarch"
      "scroll-reverser"
      "spotify"
      "steam"
      "syncthing-app"
    ];
    masApps = {
      Bitwarden = 1352778147;
      Infuse = 1136220934;
      Tailscale = 1475387142;
      TestFlight = 899247664;
    };
    onActivation = {
      cleanup = "zap";
      upgrade = true;
    };
    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  nix-homebrew = {
    enable = true;

    enableRosetta = true;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-cask" = homebrew-cask;
      "homebrew/homebrew-core" = homebrew-core;
    };
    user = user.name;
  };
}
