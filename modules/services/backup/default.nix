{
  pkgs,
  ...
}:

let
  # The shared timer shape of the daily oneshots (lib/oci-containers.nix).
  oci = import ../../lib/oci-containers.nix;

  # The members of the backup set: the archive entry name and the source
  # path of each member (docs/backups.md).
  members = [
    {
      name = "transcripts";
      path = "/home/dev/.claude/projects";
    }
    {
      name = "dispatcher-state";
      path = "/home/dev/.local/state/dispatcher";
    }
    {
      name = "memory";
      path = "/home/dev/projects/genixis/.claude/memory";
    }
    {
      name = "forgejo-data";
      path = "/mnt/forgejo/data";
    }
  ];

  # The number of daily archives that the timer keeps (docs/backups.md).
  keep = 30;

  # The public half of the age recipient. The private half stays with the
  # owner and sits on no host of this repository (docs/backups.md).
  recipient = ./backups.pub;

  stageLinks = builtins.concatStringsSep "\n" (
    map (member: ''ln -s ${member.path} "$STAGE"/${member.name}'') members
  );

  memberNames = builtins.concatStringsSep " " (map (member: member.name) members);
in
{
  system.activationScripts.create_backups_directories.text = ''
    mkdir -p /mnt/backups
  '';

  systemd = {
    services.backups = {
      description = "Write the daily archive of the backup set (docs/backups.md)";

      path = [
        pkgs.age
        pkgs.coreutils
        pkgs.gnutar
      ];

      script = ''
        set -euo pipefail

        DATE=$(date +%Y-%m-%d)
        BACKUP_DIR=/mnt/backups
        STAGE=$(mktemp -d)
        trap 'rm -rf "$STAGE"' EXIT

        # Stage each member under its archive entry name. The tar step
        # follows each link, so each source lands under its member name.
        ${stageLinks}

        mkdir -p "$BACKUP_DIR"

        # One tar holds the four members. age encrypts it with the pinned
        # recipient key, because the transcripts and the dispatcher state
        # can hold secret text (docs/backups.md). The unencrypted tar
        # leaves the disk at once.
        tar -C "$STAGE" -chf "$BACKUP_DIR/backups-$DATE.tar" ${memberNames}
        age -R ${recipient} "$BACKUP_DIR/backups-$DATE.tar" > "$BACKUP_DIR/backups-$DATE.tar.age"
        rm "$BACKUP_DIR/backups-$DATE.tar"

        # Retention: the archive names sort by date, so the oldest archive
        # sits first in the glob. Keep the newest ${toString keep} archives.
        shopt -s nullglob
        archives=("$BACKUP_DIR"/backups-*.tar.age)
        excess=$(( ''${#archives[@]} - ${toString keep} ))
        if (( excess > 0 )); then
          for (( i = 0; i < excess; i++ )); do
            rm -- "''${archives[$i]}"
          done
        fi
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    timers.backups = oci.dailyTimer "backups";
  };
}
