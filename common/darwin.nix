{
  pkgs,
  self,
  user,
  ...
}:

{
  environment = {
    shells = [
      pkgs.fish
    ];
    systemPackages = [
      pkgs.nixd
    ];
  };

  programs.fish.enable = true;

  security.pam.services.sudo_local.touchIdAuth = true; # enable Touch ID for sudo

  system = {
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
            app = "${pkgs.vscodium}/Applications/VSCodium.app";
          }
          {
            app = "${pkgs.wezterm}/Applications/Wezterm.app";
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
      shell = pkgs.fish;
      uid = 501;
    };
  };
}
