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
    hash = "sha256-0000000000000000000000000000000000000000000000000000";
  };
in
  {
    age.secrets = {
      invidious_environment = {
        file = ./invidious/environment.age;
        mode = "600";
      };

      invidious_db_environment = {
        file = ./invidious/db_environment.age;
        mode = "600";
      };
    };

    environment.etc = {
      "mnt/invidious/config/docker/init-invidious-db.sh".source = "${invidious-source}/docker/init-invidious-db.sh";
      "mnt/invidious/config/sql".source = "${invidious-source}/config/sql";
    };

    networking.firewall.allowedTCPPorts = [
      3000
    ];

    system.activationScripts.create_invidious_directories.text = ''
      mkdir -p /mnt/invidious/config/sql /mnt/invidious/config/docker
    '';

    virtualisation.oci-containers.containers = {
      invidious = {
        hostname = "invidious";
        image = "quay.io/invidious/invidious:latest";

        dependsOn = [
          "invidious-db"
        ];
        environmentFiles = [
          config.age.secrets.invidious_environment.path
        ];
        ports = [
          "3000:3000"
        ];
      };

      inv_sig_helper = {
        hostname = "inv_sig_helper";
        image = "quay.io/invidious/inv-sig-helper:latest";

        cmd = [
          "--tcp"
          "0.0.0.0:12999"
        ];
        environment = {
          RUST_LOG = "info";
        };
        extraOptions = [
          "--cap-drop=ALL"
          "--read-only"
          "--security-opt=no-new-privileges:true"
        ];
      };

      invidious_db = {
        hostname = "invidious_db";
        image = "docker.io/library/postgres:14";

        environmentFiles = [
          config.age.secrets.invidious_db_environment.path
        ];
        volumes = [
          "postgresdata:/var/lib/postgresql/data"

          "/mnt/invidious/config/sql:/config/sql"
          "/mnt/invidious/config/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh"
        ];
      };
    };
  }
