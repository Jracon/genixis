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

  environment = {
    # remove all default packages for a minimal base system
    defaultPackages = [ ];

    # flakes require git for cloning dependencies
    systemPackages = with pkgs; [ 
      git 
    ];
  };
}
