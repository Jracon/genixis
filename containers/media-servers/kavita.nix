{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    5000
  ];

  system.activationScripts.create_kavita_directories.text = ''
    mkdir -p /mnt/media/books /mnt/media/comics /mnt/media/data/kavita /mnt/media/manga
  '';

  virtualisation.oci-containers.containers.kavita = {
    hostname = "kavita";
    image = "lscr.io/linuxserver/kavita:latest";

    environment = {
      PUID = "1000";
      PGID = "1000";

      TZ = "America/Phoenix";
    };
    ports = [
      "5000:5000"
    ];
    pull = "newer";
    volumes = [
      "/mnt/media/books:/books"
      "/mnt/media/comics:/comics"
      "/mnt/media/data/kavita:/config"
      "/mnt/media/manga:/manga"
    ];
  };
}
