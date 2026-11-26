{ config, lib, ... }:

{
  # The agenix Home Manager module decrypts into the per-user temp directory by default: its
  # age.secretsDir and age.secretsMountPoint options read the output of 'getconf
  # DARWIN_USER_TEMP_DIR'. macOS treats that directory as scratch space and deletes files that stay
  # unused, so the decrypted secrets disappeared while the user stayed logged in (issue 698). The
  # state directory of the home persists across days, and no cleanup of the system removes it. The
  # module keeps each decrypted file at mode 0400 and each generation directory at 0751, so the files
  # stay readable by the owner only. The agent exists only when the user has a secret (age.enable).
  age.secretsDir = lib.mkIf config.age.enable "${config.xdg.stateHome}/agenix";
  age.secretsMountPoint = lib.mkIf config.age.enable "${config.xdg.stateHome}/agenix.d";

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
