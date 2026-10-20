{
  pkgs,
  ...
}:

{
  environment = {
    # remove all default packages for a minimal base system
    defaultPackages = [ ];
    # git is required to use flakes
    systemPackages = [
      pkgs.git
    ];
  };

  nix = {
    # automatically optimise the Nix store and enable automatic garbage collection
    gc.automatic = true;
    optimise.automatic = true;
    # enable the Nix command line tool and flakes
    settings.experimental-features = [
      "flakes"
      "nix-command"
    ];
  };

  time.timeZone = "America/Phoenix";
}
