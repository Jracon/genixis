{
  config,
  pkgs,
  ...
}:

{
  age.secrets.vaultwarden_environment = {
    file = ./environment.age;
    # mode = "600";
  };

  environment.systemPackages = with pkgs; [
    age
  ];

  networking.firewall.allowedTCPPorts = [
    80
  ];

  system.activationScripts = {
    create_vaultwarden_directories.text = ''
      mkdir -p /mnt/vaultwarden /mnt/vaultwarden-backups
    '';
    create_vaultwarden_encryption_key.text = ''
      mkdir -p ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbTP4PprduMEQ4OXorf6mi9hVoFkFDlfqhZftb29GxV" > ~/.ssh/vaultwarden_backups.pub
    '';
  };

  systemd = {
    timers."vaultwarden-backup" = {
      wantedBy = [
        "timers.target"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Unit = "vaultwarden-backup.service";
      };
    };
    services."vaultwarden-backup" = {
      path = [
        "/run/current-system/sw"
      ];
      script = ''
        #!/bin/bash

        DATE=$(date +%Y-%m-%d)
        BACKUP_DIR=/mnt/vaultwarden-backups
        BACKUP_FILE=vaultwarden-$DATE.tar
        CONTAINER_DATA_DIR=/mnt/vaultwarden

        mkdir -p $BACKUP_DIR

        tar -cvf "$BACKUP_DIR/$BACKUP_FILE" -C "$CONTAINER_DATA_DIR" .

        age -R ~/.ssh/vaultwarden_backups.pub "$BACKUP_DIR/$BACKUP_FILE" > "$BACKUP_DIR/$BACKUP_FILE.age"

        rm "$BACKUP_DIR/$BACKUP_FILE"

        # TODO: add rclone
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server:latest";

    hostname = "vaultwarden";
    pull = "newer";

    environmentFiles = [
      config.age.secrets.vaultwarden_environment.path
    ];
    ports = [
      "80:80"
    ];
    volumes = [
      "/mnt/vaultwarden:/data"
    ];
  };
}
