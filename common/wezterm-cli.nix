{
  pkgs,
  ...
}:

{
  # the cli of wezterm serves the socket forward of a window of a remote login
  # (issue #141): with WEZTERM_UNIX_SOCKET set, project open on this host opens
  # tabs in the window of the login. See "The host window" in AGENTS.md.
  environment.systemPackages = [
    pkgs.wezterm
  ];
}
