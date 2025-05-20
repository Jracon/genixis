{
  config, 
  pkgs, 
  ...
}:

let
  invidious-source = pkgs.fetchFromGitHub {
    owner = "iv-org";
    repo = "invidious";
    rev = "master";
    hash = "sha256-gk/NKkW+rugvASjycp0HsV5qTyRK5BQA8+Y2U3PMqNo=";
  };
in
  {
    age.secrets = {
      invidious_environment = {
        file = ./invidious/environment.age;
        # mode = "444";
      };

      invidious_companion_environment = {
        file = ./invidious/companion_environment.age;
        # mode = "600";
      };

      invidious-db_environment = {
        file = ./invidious/db_environment.age;
        # mode = "600";
      };
    };

    networking.firewall.allowedTCPPorts = [
      3000
      8282
    ];

    system.activationScripts = {
      create_invidious_directories.text = ''
        mkdir -p /mnt/invidious/config/docker /mnt/invidious/config/sql
      '';

      create_invidious-network.text = ''
        ${pkgs.podman}/bin/podman network create invidious-network --ignore
      '';

      copy_invidious_files.text = ''
        cp -r ${invidious-source}/config/sql/* /mnt/invidious/config/sql/
        cp -r ${invidious-source}/docker/init-invidious-db.sh /mnt/invidious/config/docker/
      '';
    };

    systemd = {
      timers."invidious-restart" = {
        wantedBy = [
          "timers.target"
        ];

        timerConfig = {
          OnCalendar = "daily";
          Unit = "invidious-restart.service";
        };
      };

      services."invidious-restart" = {
        script = ''
          systemctl restart podman-invidious
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    };

    virtualisation.oci-containers.containers = {
      invidious = {
        image = "quay.io/invidious/invidious:master";
        pull = "newer";
        hostname = "invidious";

        environment = {
          INVIDIOUS_CONFIG_FILE = "/config/config.yml";
        };

        volumes = [
          "${config.age.secrets.invidious_environment.path}:/config/config.yml"
        ];

        ports = [
          "3000:3000"
        ];

        dependsOn = [
          "invidious-db"
        ];

        networks = [
          "invidious-network"
        ];
      };

      invidious_companion = {
        image = "quay.io/invidious/invidious-companion:latest";
        pull = "newer";
        hostname = "invidious_companion";

        extraOptions = [
          "--cap-drop=ALL"
          "--read-only"
          "--security-opt=no-new-privileges:true"
        ];

        environmentFiles = [
          config.age.secrets.invidious_companion_environment.path
        ];

        volumes = [
          "companioncache:/var/tmp/youtubei.js:rw"
        ];

        ports = [
          "8282:8282"
        ];

        networks = [
          "invidious-network"
        ];
      };

      invidious-db = {
        image = "docker.io/library/postgres:14";
        pull = "newer";
        hostname = "invidious-db";

        environmentFiles = [
          config.age.secrets.invidious-db_environment.path
        ];

        volumes = [
          "postgresdata:/var/lib/postgresql/data"
          "/mnt/invidious/config/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh"
          "/mnt/invidious/config/sql:/config/sql"
        ];

        networks = [
          "invidious-network"
        ];
      };
    };
  }
