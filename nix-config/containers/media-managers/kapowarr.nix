{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      5656
      5657
    ];
  };

  virtualisation.oci-containers.containers = {
    kapowarr = {
      hostname = "kapowarr";
      image = "mrcas/kapowarr:latest";

      ports = [
        "5656:5656"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/completed/comics:/app/temp_downloads"
        "/mnt/media/data/kapowarr:/app/db"
      ];
    };

    kapowarr-manga = {
      hostname = "kapowarr-manga";
      image = "mrcas/kapowarr:latest";

      ports = [
        "5657:5656"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/completed/manga:/app/temp_downloads"
        "/mnt/media/data/kapowarr-manga:/app/db"
      ];
    };
  };
}
