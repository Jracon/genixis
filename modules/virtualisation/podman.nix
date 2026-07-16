{ lib, ... }:

{
  networking.firewall.trustedInterfaces = [
    "podman1"
    "podman2"
    "podman3"
    "podman4"
  ];

  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      dockerCompat = true;
      dockerSocket.enable = true;

      autoPrune = {
        enable = true;
        dates = "daily";

        flags = [
          "--all"
        ];
      };
    };
  };
}
