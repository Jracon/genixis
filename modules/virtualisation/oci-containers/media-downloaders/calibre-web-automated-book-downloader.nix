{
  networking.firewall = {
    allowedTCPPorts = [
      8084
    ];
    allowedUDPPorts = [
      8084
    ];
  };

  system.activationScripts.create_calibre-web-automated-book-downloader_directory.text = ''
    mkdir -p /mnt/media/downloads/cwabd
  '';

  virtualisation.oci-containers.containers = {
    calibre-web-automated-book-downloader = {
      image = "ghcr.io/calibrain/calibre-web-automated-book-downloader:latest";

      hostname = "calibre-web-automated-book-downloader";
      pull = "newer";

      environment = {
        BOOK_LANGUAGE = "en";
        CLOUDFLARE_PROXY_URL = "http://cloudflarebypassforscraping:8000";
        FLASK_PORT = "8084";
        INGEST_DIR = "/cwa-book-ingest";
      };
      ports = [
        "8084:8084"
      ];
      volumes = [
        "/mnt/media/downloads/cwabd:/cwa-book-ingest"
      ];
    };
    cloudflarebypassforscraping = {
      image = "ghcr.io/sarperavci/cloudflarebypassforscraping:latest";

      hostname = "cloudflarebypassforscraping";
      pull = "newer";
    };
  };
}
