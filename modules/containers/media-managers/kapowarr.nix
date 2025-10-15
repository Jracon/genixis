{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    5656
    5657
  ];

  system.activationScripts.create_kapowaarr_directories.text = ''
    mkdir -p /mnt/kapowarr /mnt/media/downloads/kapowarr/comics /mnt/kapowarr-manga /mnt/media/downloads/kapowarr/manga
  '';

  virtualisation.oci-containers.containers = {
    kapowarr = {
      image = "mrcas/kapowarr:latest";
      pull = "newer";
      hostname = "kapowarr";

      volumes = [
        "/mnt/kapowarr:/app/db"
        "/mnt/media:/mnt/media"
        "/mnt/media/downloads/kapowarr/comics:/app/temp_downloads"
      ];

      ports = [
        "5656:5656"
      ];
    };

    kapowarr-manga = {
      image = "mrcas/kapowarr:latest";
      pull = "newer";
      hostname = "kapowarr-manga";

      volumes = [
        "/mnt/kapowarr-manga:/app/db"
        "/mnt/media:/mnt/media"
        "/mnt/media/downloads/kapowarr/manga:/app/temp_downloads"
      ];
      ports = [
        "5657:5656"
      ];
    };
  };
}
