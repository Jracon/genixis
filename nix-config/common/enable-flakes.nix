{ 
  pkgs, 
  ... 
}:

{
  # enable the Nix command line tool and flakes
  nix.settings.experimental-features = [ 
    "nix-command" 
    "flakes" 
  ];

  # flakes require git for cloning dependencies
  environment = {
    defaultPackages = [ ];
    systemPackages = with pkgs; [ 
      git 
  ];
  };
}
