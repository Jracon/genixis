{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8084
    ];
    allowedUDPPorts = [
      8084
    ];
  };

  system.activationScripts = {
    create_calibre-web-automated-book-downloader_directory.text = ''
      mkdir -p /mnt/media/completed/books
    '';
  };

  virtualisation.oci-containers.containers = {
    cloudflarebypassforscraping = {
      hostname = "cloudflarebypassforscraping";
      image = "ghcr.io/sarperavci/cloudflarebypassforscraping:latest";

      pull = "always";
    };

    calibre-web-automated-book-downloader = {
      hostname = "calibre-web-automated-book-downloader";
      image = "ghcr.io/calibrain/calibre-web-automated-book-downloader:latest";

      environment = {
        BOOK_LANGUAGE = "en";
        CLOUDFLARE_PROXY_URL = "http://cloudflarebypassforscraping:8000";
        FLASK_PORT = "8084";
        INGEST_DIR = "/cwa-book-ingest";
      };
      pull = "always";
      volumes = [
        "/mnt/media/completed/books:/cwa-book-ingest"
      ];
    };
  };
}
