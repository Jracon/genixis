{ config, lib, ... }:

{
  # The agenix module sets KeepAlive with SuccessfulExit = false on its launchd agent. The script exits
  # with 0, and launchd still starts it again every 10 seconds. Each run decrypts every secret and
  # replaces the secrets directory, so a reader can find no token file. KeepAlive off and RunAtLoad on
  # run the script once per login. The agent exists only when the user has a secret (age.enable).
  launchd.agents.activate-agenix.config.KeepAlive = lib.mkIf config.age.enable (lib.mkForce false);

  # copy (not symlink) Home Manager .app bundles into ~/Applications so Spotlight indexes them
  targets.darwin = {
    copyApps.enable = true;
    linkApps.enable = false;
  };
}
