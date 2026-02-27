{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    222
    4000
  ];

  system.activationScripts.create_forgejo_directory.text = ''
    mkdir -p /mnt/forgejo/data
  '';

  virtualisation.oci-containers.containers.forgejo = {
    image = "codeberg.org/forgejo/forgejo:14";

    hostname = "forgejo";
    pull = "newer";

    environment = {
      USER_UID = "1000";
      USER_GID = "1000";
    };
    ports = [
      "222:22"
      "4000:3000"
    ];
    volumes = [
      "/mnt/forgejo/data:/data"
      "/etc/localtime:/etc/localtime:ro"
    ];
  };
}
