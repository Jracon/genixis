{
  config, 
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
    #!/bin/sh

    # Read the decrypted secret from the file
    AUTH_KEY=$(cat ${config.age.secrets.tailscale_client_secret.path})

    # Bring up Tailscale with the key
    /run/wrappers/bin/tailscale up --auth-key="$AUTH_KEY?ephemeral=false" --advertise-tags=tag:genixis
  '';
  };
}