{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./tailscale/client_secret.age;

  services.tailscale = {
    authKeyFile = config.age.secrets.tailscale_client_secret.path;
    authKeyParameters.ephemeral = false;
    enable = true;
    extraUpFlags = [
      "--advertise-tags=tag:genixis"
    ];
    openFirewall = true;
    useRoutingFeatures = "server";
  };

  # system.activationScripts.tailscale_up.text = ''
  #   ${pkgs.tailscale}/bin/tailscaled -cleanup
  #   TAILSCALE_CLIENT_SECRET=$(cat ${config.age.secrets.tailscale_client_secret.path})
  #   ${pkgs.tailscale}/bin/tailscale up --auth-key="$TAILSCALE_CLIENT_SECRET?ephemeral=false" --advertise-tags=tag:genixis
  # '';
}
