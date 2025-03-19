{
  ...
}:

{
  age.secrets = {
    openvpn_user.file = ./gluetun/openvpn_user.age;
    openvpn_password.file = ./gluetun/openvpn_password.age;
  };

  networking.firewall = {
    allowedTCPPorts = [
      8080
      8112
    ];
    allowedUDPPorts = [
      8080
      8112
    ];
  };

  virtualisation.oci-containers.containers = {
    gluetun = {
      hostname = "gluetun";
      image = "qmcgaw/gluetun:latest";

      capabilities = {
        NET_ADMIN = true;
      };
      devices = [
        "/dev/net/tun:/dev/net/tun"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";

        OPENVPN_USER = age.secrets.openvpn_user.path;
        OPENVPN_PASSWORD = age.secrets.openvpn_password.path;
        VPN_SERVICE_PROVIDER = "private internet access";
        VPN_PORT_FORWARDING = "on";
        VPN_PORT_FORWARDING_STATUS_FILE = "/gluetun/forwarded_port";
      };
      ports = [
        "8080:8080"
        "8112:8112"
      ];
      pull = "always";
      volumes = [
        "gluetun:/gluetun"
      ];
    };
  };
}
