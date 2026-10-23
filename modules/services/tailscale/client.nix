{
  ...
}:

{
  # what every tailnet member needs; server.nix adds subnet routing and the OAuth login. A host
  # loading only this file logs in once with `sudo tailscale up`, and accepts no routes (the servers
  # advertise the LAN it's already on, and taking it over the tailnet would detour local traffic)
  services.tailscale = {
    enable = true;

    openFirewall = true;
  };
}
