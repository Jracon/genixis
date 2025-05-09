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
}
