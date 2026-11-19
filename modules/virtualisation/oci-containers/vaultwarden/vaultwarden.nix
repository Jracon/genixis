{
  config,
  pkgs,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  age.secrets.vaultwarden_environment.file = ./environment.age;

  environment.systemPackages = [
    pkgs.age
  ];

  networking.firewall.allowedTCPPorts = [
    5555
  ];

  system.activationScripts = {
    create_vaultwarden_directories.text = ''
      mkdir -p /mnt/vaultwarden /mnt/vaultwarden-backups
      chmod 700 /mnt/vaultwarden-backups
    '';
    create_vaultwarden_encryption_key.text = ''
      mkdir -p ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbTP4PprduMEQ4OXorf6mi9hVoFkFDlfqhZftb29GxV" > ~/.ssh/vaultwarden_backups.pub
    '';
  };

  systemd = {
    services.vaultwarden-backup = {
      path = [
        "/run/current-system/sw"
      ];
      script = ''
        set -euo pipefail

        DATE=$(date +%Y-%m-%d)
        BACKUP_DIR=/mnt/vaultwarden-backups
        BACKUP_FILE=vaultwarden-$DATE.tar
        CONTAINER_DATA_DIR=/mnt/vaultwarden

        mkdir -p "$BACKUP_DIR"

        # Sweep the failure path of earlier runs: each run removes every
        # plaintext name before it writes, the same shape as the backups
        # unit (issue 528). The globs end in .tar and in .part, so they
        # never match an encrypted archive.
        rm -f "$BACKUP_DIR"/vaultwarden-*.tar "$BACKUP_DIR"/vaultwarden-*.tar.age.part

        # tar streams into age, so no unencrypted archive lands on the
        # disk. The .part name keeps a partial stream of a failed run out
        # of the archive names, and the move lands the final name only
        # after age wrote the stream whole.
        tar -C "$CONTAINER_DATA_DIR" -cvf - . | age -R ~/.ssh/vaultwarden_backups.pub -o "$BACKUP_DIR/$BACKUP_FILE.age.part"
        mv "$BACKUP_DIR/$BACKUP_FILE.age.part" "$BACKUP_DIR/$BACKUP_FILE.age"

        # TODO: add rclone
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    timers.vaultwarden-backup = oci.dailyTimer "vaultwarden-backup";
  };

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "docker.io/vaultwarden/server:1.37.5";

    hostname = "vaultwarden";
    pull = "newer";

    environmentFiles = [
      config.age.secrets.vaultwarden_environment.path
    ];
    ports = [
      "5555:80"
    ];
    volumes = [
      "/mnt/vaultwarden:/data"
    ];
  };
}
