{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets = {
    tailscale_client_secret.file = ./tailscale/client_secret.age;
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  system.activationScripts = {
    tailscale_up.text = ''
      AUTH_KEY=$(cat ${config.age.secrets.tailscale_client_secret.path})
      ${pkgs.tailscale} up --auth-key="$AUTH_KEY?ephemeral=false" --advertise-tags=tag:genixis
  '';
  };
}