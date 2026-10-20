{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = [
    pkgs.rclone
  ];

  networking.firewall.allowedTCPPorts = [
    8080
  ];

  system.activationScripts.create_rclone_webdav_directory.text = ''
    mkdir -p /mnt/media/games/saves/
  '';

  systemd.services.rclone-webdav = {
    after = [
      "network.target"
    ];
    description = "rclone WebDAV server";
    serviceConfig = {
      DynamicUser = true;
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone serve webdav"
        # TODO: set your remote or local path, e.g. "myremote:" or "/mnt/media"
        "/mnt/media/games/saves/"
        "--addr :8080"
        # Uncomment and set after encrypting with agenix:
        # "--config ${config.age.secrets.rclone_config.path}"
        # "--htpasswd ${config.age.secrets.rclone_htpasswd.path}"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
      StateDirectory = "rclone-webdav";
      Type = "simple";
    };
    wantedBy = [
      "multi-user.target"
    ];
  };
}
