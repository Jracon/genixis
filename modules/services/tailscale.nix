{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets.tailscale_client_secret.file = ./tailscale/client_secret.age;

  services.tailscale = {
    authKeyFile = config.age.secrets.tailscale_client_secret.path;
    authKeyParameters.ephemeral = true;
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";

    extraUpFlags = [
      "--advertise-tags=tag:genixis"
    ];
  };
}
