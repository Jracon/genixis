{
  config, 
  ...
}:

{
  age.secrets = {
    vaultwarden_environment = {
      file = ./environment.age;
      mode = "600";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
    ];
  };

  system.activationScripts = {
    create_vaultwarden_directories.text = ''
      mkdir -p /mnt/vaultwarden /mnt/vaultwarden-backups
    '';

    create_vaultwarden_encryption_key.text = ''
      mkdir ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbTP4PprduMEQ4OXorf6mi9hVoFkFDlfqhZftb29GxV" > ~/.ssh/vaultwarden_backups.pub
    '';
  };

  systemd = {
    timers."vaultwarden-backup" = {
      wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Unit = "vaultwarden-backup.service";
        };
    };

    services."vaultwarden-backup" = {
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

        # TODO: add rsync.net scp
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };

  virtualisation.oci-containers.containers = {
    vaultwarden = {
      hostname = "vaultwarden";
      image = "vaultwarden/server:latest";

      environmentFiles = [
        config.age.secrets.vaultwarden_environment.path
      ];
      ports = [
        "80:80"
      ];
      pull = "always";
      volumes = [
        "/mnt/vaultwarden:/data"
      ];
    };
  };
}
