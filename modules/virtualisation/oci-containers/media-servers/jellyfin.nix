{
  config,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  networking.firewall = {
    allowedTCPPorts = [
      8096
      8920
    ];
    allowedUDPPorts = [
      1900
      7359
    ];
  };

  system.activationScripts.create_jellyfin_directory.text = ''
    mkdir -p /mnt/jellyfin
  '';

  systemd = {
    services.generate-jellyfin-playlists = {
      path = [
        "/run/current-system/sw"
      ];
      # the store copy of media-scripts.nix, never a file of the writable media tree
      script = ''
        media-playlist-generator /mnt/media/playlists
      '';
      serviceConfig = {
        Type = "oneshot";
        # ruling of #375: no media script runs as root unless a step requires
        # it, and no step does. The id pair is the PUID and PGID of the media
        # containers (lib/oci-containers.nix) and owns the tree the script
        # writes; the host names no such user in this repository.
        User = toString oci.mediaId;
        Group = toString oci.mediaId;
      };
    };

    timers.generate-jellyfin-playlists = {
      timerConfig = {
        OnCalendar = "daily";
        Unit = "generate-jellyfin-playlists.service";
      };
      wantedBy = [
        "timers.target"
      ];
    };
  };

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";

    hostname = "jellyfin";
    pull = "newer";

    devices = [
      "/dev/dri:/dev/dri"
    ];
    environment = oci.mediaEnvironment config.time.timeZone;
    extraOptions = [
      "--network=host"
    ];
    volumes = [
      "/mnt/jellyfin:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
