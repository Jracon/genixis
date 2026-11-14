{
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = [
    pkgs.rclone
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
        "/mnt/media/games/saves/"
        "--addr :8080"
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
