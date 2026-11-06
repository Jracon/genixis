{
  config,
  hostname,
  pkgs,
  self,
  user,
  ...
}:

let
  # where targets.darwin.copyApps puts Home Manager apps; Spotlight launches these copies,
  # so the Dock must pin the same bundles (store paths would show as separate apps)
  homeManagerApps = "${config.users.users.${user.name}.home}/${
    config.home-manager.users.${user.name}.targets.darwin.copyApps.directory
  }";
in
{
  environment.shells = [
    pkgs.fish
  ];

  networking.hostName = hostname; # Home Manager's Syncthing module identifies the device by it

  programs.fish.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true; # enable Touch ID for sudo

  system = {
    # the LAN is the primary transport of the forge (issue #166, reversal of 2026-11-06);
    # off the LAN, the Tailscale subnet route carries the address. Append the pin only when
    # the name is absent: an existing pin that maps another address needs a hand edit.
    activationScripts.forgeHostsPin.text = ''
      if ! grep -q 'forgejo.local.jracon.xyz' /etc/hosts; then
        echo '10.0.0.208 forgejo.local.jracon.xyz' >> /etc/hosts
      fi
    '';

    configurationRevision = self.rev or self.dirtyRev or null; # git commit hash for darwin-version.
    defaults = {
      controlcenter = {
        BatteryShowPercentage = true;
        Bluetooth = true;
      };
      dock = {
        appswitcher-all-displays = true;
        autohide = true;
        minimize-to-application = true;
        persistent-apps = [
          {
            app = "/System/Applications/Calendar.app";
          }
          {
            app = "/Applications/Firefox.app";
          }
          {
            app = "/Applications/Infuse.app";
          }
          {
            app = "/System/Applications/Messages.app";
          }
          {
            app = "/System/Applications/Notes.app";
          }
          {
            app = "/Applications/Obsidian.app";
          }
          {
            app = "${homeManagerApps}/VSCodium.app";
          }
          {
            app = "${homeManagerApps}/WezTerm.app";
          }
        ];
        show-recents = false;
        wvous-br-corner = 1;
      };
      finder = {
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXPreferredViewStyle = "Nlsv";
        FXRemoveOldTrashItems = true;
        NewWindowTarget = "iCloud Drive";
        ShowPathbar = true;
      };
      hitoolbox.AppleFnUsageType = "Do Nothing";
      loginwindow.GuestEnabled = false;
      menuExtraClock = {
        Show24Hour = true;
        ShowAMPM = true;
        ShowDate = 1;
        ShowSeconds = true;
      };
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleScrollerPagingBehavior = true;
        AppleShowAllFiles = true;
        AppleShowScrollBars = "WhenScrolling";
        "com.apple.trackpad.forceClick" = true;
        NSAutomaticInlinePredictionEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;
      };
      screensaver = {
        askForPassword = true;
        askForPasswordDelay = 300;
      };
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      WindowManager = {
        EnableStandardClickToShowDesktop = false;
        EnableTiledWindowMargins = false;
        StandardHideDesktopIcons = true;
      };
    };
    primaryUser = user.name;
    stateVersion = 6; # used for backwards compatibility, please read the changelog before changing. (darwin-rebuild changelog)
  };

  users = {
    knownUsers = [
      user.name
    ];
    users.${user.name} = {
      home = "/Users/${user.name}";
      shell = pkgs.fish;
      uid = 501;
    };
  };
}
