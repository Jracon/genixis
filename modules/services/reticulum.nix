{
  services.rnsd = {
    enable = true;

    openMulticastPorts = true;
    settings = {
      interfaces.auto = {
        enabled = true;
        type = "AutoInterface";
      };
      reticulum.enable_transport = false;
    };
  };
}
