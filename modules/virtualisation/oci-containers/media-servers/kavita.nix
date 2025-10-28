{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    5000
  ];

  system.activationScripts.create_kavita_directories.text = ''
    mkdir -p /mnt/kavita /mnt/media/books /mnt/media/comics /mnt/media/manga
  '';

  virtualisation.oci-containers.containers.kavita = {
    image = "lscr.io/linuxserver/kavita:latest";
    pull = "always";
    hostname = "kavita";

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    volumes = [
      "/mnt/kavita:/config"
      "/mnt/media/books:/books"
      "/mnt/media/comics:/comics"
      "/mnt/media/manga:/manga"
    ];

    ports = [
      "5000:5000"
    ];
  };
}
