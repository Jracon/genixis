{
  config,
  lib,
  pkgs,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # extension ID -> addons.mozilla.org slug
  extensions = {
    "languagetool-webextension@languagetool.org" = "languagetool";
    "uBlock0@raymondhill.net" = "ublock-origin";
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
    "{cb31ec5d-c49a-4e5a-b240-16c767444f62}" = "indie-wiki-buddy";
  };
in
{
  programs.firefox = {
    enable = true;

    configPath = lib.mkIf (!isDarwin) "${config.xdg.configHome}/mozilla/firefox";
    # macOS installs Firefox via the Homebrew cask (signed, stable path for the Dock);
    # policies are written to the org.mozilla.firefox defaults domain instead
    package = lib.mkIf isDarwin null;
    policies = {
      # managed storage, read only by extensions that support it
      "3rdparty".Extensions = {
        "languagetool-webextension@languagetool.org".apiServerUrl =
          "https://languagetool.local.jracon.xyz/v2";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}".environment.base = "https://vaultwarden.local.jracon.xyz";
      };
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
      # installed once (and again whenever this list changes), but still removable
      Extensions.Install = lib.mapAttrsToList (
        _: slug: "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi"
      ) extensions;
      ExtensionSettings = lib.mapAttrs (_: _: {
        private_browsing = true;
      }) extensions;
      FirefoxHome = {
        Pocket = false;
        SponsoredPocket = false;
        SponsoredTopSites = false;
      };
      FirefoxSuggest = {
        ImproveSuggest = false;
        SponsoredSuggestions = false;
      };
      HttpsOnlyMode = "enabled";
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false; # Bitwarden handles passwords
      PasswordManagerEnabled = false;
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        MoreFromMozilla = false;
        SkipOnboarding = true;
      };
    };
    profiles.default = {
      search = {
        default = "ddg";
        engines = {
          amazondotcom-us.metaData.hidden = true;
          bing.metaData.hidden = true;
          ebay.metaData.hidden = true;
          google.metaData.hidden = true;
          perplexity.metaData.hidden = true;
          wikipedia.metaData.hidden = true;
        };
        force = true; # Firefox replaces the search.json.mozlz4 symlink on launch otherwise
        privateDefault = "ddg";
      };
      settings = {
        "browser.aboutConfig.showWarning" = false;
        "browser.bookmarks.showMobileBookmarks" = false;
        "browser.discovery.enabled" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSearch" = false;
        "browser.newtabpage.enabled" = false;
        "browser.search.suggest.enabled" = false;
        "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
        "browser.startup.page" = 3; # restore previous session
        "browser.tabs.closeWindowWithLastTab" = true;
        "browser.tabs.groups.smart.userEnabled" = false;
        "browser.theme.toolbar-theme" = 0; # dark
        "browser.toolbars.bookmarks.visibility" = "always";
        # reapplied from user.js on every launch, so changes made in Customize Toolbar don't persist
        "browser.uiCustomization.state" = builtins.toJSON {
          currentVersion = 28;
          dirtyAreaCache = [
            "nav-bar"
            "PersonalToolbar"
            "TabsToolbar"
            "unified-extensions-area"
            "vertical-tabs"
            "widget-overflow-fixed-list"
          ];
          newElementCount = 5;
          placements = {
            nav-bar = [
              "back-button"
              "forward-button"
              "stop-reload-button"
              "vertical-spacer"
              "urlbar-container"
              "downloads-button"
              "unified-extensions-button"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
              "languagetool-webextension_languagetool_org-browser-action"
              "ublock0_raymondhill_net-browser-action"
            ];
            PersonalToolbar = [
              "personal-bookmarks"
            ];
            TabsToolbar = [
              "tabbrowser-tabs"
              "new-tab-button"
              "customizableui-special-spring5"
              "alltabs-button"
              "smartwindow-group-tabs-button"
              "ai-window-toggle"
            ];
            unified-extensions-area = [
              "_cb31ec5d-c49a-4e5a-b240-16c767444f62_-browser-action"
            ];
            vertical-tabs = [ ];
            widget-overflow-fixed-list = [ ];
          };
          seen = [
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
            "_cb31ec5d-c49a-4e5a-b240-16c767444f62_-browser-action"
            "ai-window-toggle"
            "developer-button"
            "languagetool-webextension_languagetool_org-browser-action"
            "reset-pbm-toolbar-button"
            "screenshot-button"
            "smartwindow-group-tabs-button"
            "ublock0_raymondhill_net-browser-action"
          ];
        };
        "browser.urlbar.quicksuggest.online.enabled" = false;
        "browser.urlbar.scotchBonnet.enableOverride" = false;
        "browser.urlbar.showSearchSuggestionsFirst" = false;
        "browser.urlbar.suggest.engines" = false;
        "browser.urlbar.suggest.quicksuggest.all" = false;
        "browser.urlbar.suggest.searches" = false;
        "datareporting.usage.uploadEnabled" = false;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "findbar.highlightAll" = true;
        "general.autoScroll" = false;
        "layout.spellcheckDefault" = 0; # LanguageTool handles spelling
        "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;
        "network.dns.disablePrefetch" = true;
        "network.http.speculative-parallel-limit" = 0;
        "network.prefetch-next" = false;
        "privacy.clearOnShutdown_v2.formdata" = true;
        "privacy.donottrackheader.enabled" = true;
        "privacy.globalprivacycontrol.enabled" = true;
        "sidebar.visibility" = "hide-launcher";
        "signon.autofillForms" = false;
        "signon.generation.enabled" = false;
        "signon.management.page.breach-alerts.enabled" = false;
      };
    };
  };
}
