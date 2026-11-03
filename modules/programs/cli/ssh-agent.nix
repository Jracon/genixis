{
  pkgs,
  ...
}:

{
  # a systemd user service starts one agent per user at login. `AddKeysToAgent` in ssh.nix loads the key at its first use.
  # macOS runs its own agent through launchd, so the service stays off there. A second agent would split the environment.
  services.ssh-agent.enable = !pkgs.stdenv.hostPlatform.isDarwin;
}
