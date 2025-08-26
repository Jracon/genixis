{
  self,
  ...
}:

{
  # enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    configurationRevision = self.rev or self.dirtyRev or null; # git commit hash for darwin-version.
    stateVersion = 6; # used for backwards compatibility, please read the changelog before changing. (darwin-rebuild changelog)

    defaults = {
      hitoolbox.AppleFnUsageType = "Do Nothing";
      loginwindow.GuestEnabled = false;
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      trackpad.TrackpadThreeFingerDrag = true;

      controlcenter = {
        BatteryShowPercentage = true;
        Bluetooth = true;
      };

      dock = {
        appswitcher-all-displays = true;
        autohide = true;
        minimize-to-application = true;
        show-recents = false;
        wvous-br-corner = 1;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXPreferredViewStyle = "Nlsv";
        FXRemoveOldTrashItems = true;
        NewWindowTarget = "iCloud Drive";
        ShowPathbar = true;
      };

      menuExtraClock = { 
        ShowAMPM = true;
        ShowDate = 1;
        ShowSeconds = true;
      };

      NSGlobalDomain = {
        "com.apple.trackpad.forceClick" = true;
        AppleInterfaceStyle = "Dark";
        AppleScrollerPagingBehavior = true;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        AppleShowScrollBars = "WhenScrolling";
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

      WindowManager = { 
        EnableStandardClickToShowDesktop = false;
        EnableTiledWindowMargins = false;
        StandardHideDesktopIcons = true;
      };
    };
  };
}
