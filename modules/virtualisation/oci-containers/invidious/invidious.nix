{
  config,
  pkgs,
  ...
}:

let
  invidious-source = pkgs.fetchFromGitHub {
    owner = "iv-org";
    repo = "invidious";
    rev = "df8839d1f018644afecb15e144f228d811708f8f";
    hash = "sha256-HF4kpwHQ4gAvRao7Zql6GYwbrXT2uQvEdRwFQGdWnn0=";
  };
in
{
  age.secrets = {
    invidious_environment = {
      file = ./environment.age;
      mode = "444";
    };
    invidious_companion_environment = {
      file = ./companion_environment.age;
      # mode = "600";
    };
    invidious-db_environment = {
      file = ./db_environment.age;
      # mode = "600";
    };
  };

  networking.firewall.allowedTCPPorts = [
    3000
    8282
  ];

  system.activationScripts = {
    create_invidious-network.text = ''
      ${pkgs.podman}/bin/podman network create invidious-network --ignore
    '';
    copy_invidious_files.text = ''
      mkdir -p /mnt/invidious/config/docker /mnt/invidious/config/sql
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

      hostname = "invidious";
      pull = "newer";

      dependsOn = [
        "invidious-db"
      ];
      environment = {
        INVIDIOUS_CONFIG_FILE = "/config/config.yml";
      };
      networks = [
        "invidious-network"
      ];
      ports = [
        "3000:3000"
      ];
      volumes = [
        "${config.age.secrets.invidious_environment.path}:/config/config.yml"
      ];
    };
    invidious_companion = {
      image = "quay.io/invidious/invidious-companion:latest";

      hostname = "invidious_companion";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.invidious_companion_environment.path
      ];
      extraOptions = [
        "--cap-drop=ALL"
        "--read-only"
        "--security-opt=no-new-privileges:true"
      ];
      networks = [
        "invidious-network"
      ];
      ports = [
        "8282:8282"
      ];
      volumes = [
        "companioncache:/var/tmp/youtubei.js:rw"
      ];
    };
    invidious-db = {
      image = "docker.io/library/postgres:14";

      hostname = "invidious-db";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.invidious-db_environment.path
      ];
      networks = [
        "invidious-network"
      ];
      volumes = [
        "postgresdata:/var/lib/postgresql/data"
        "/mnt/invidious/config/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh"
        "/mnt/invidious/config/sql:/config/sql"
      ];
    };
  };
}
