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
        # it, and no step does. uid and gid 1000 are the PUID and PGID of the
        # media containers and own the tree the script writes; the host names
        # no such user in this repository, so the ids stand here directly.
        User = "1000";
        Group = "1000";
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
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    extraOptions = [
      "--network=host"
    ];
    volumes = [
      "/mnt/jellyfin:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
