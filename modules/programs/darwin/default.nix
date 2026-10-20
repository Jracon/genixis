{
  # copy (not symlink) Home Manager .app bundles into ~/Applications so Spotlight indexes them
  targets.darwin = {
    copyApps.enable = true;
    linkApps.enable = false;
  };
}
