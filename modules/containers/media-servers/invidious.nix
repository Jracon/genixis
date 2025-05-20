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
        mode = "444";
      };

      invidious_companion_environment = {
        file = ./invidious/companion_environment.age;
        mode = "600";
      };

      invidious-db_environment = {
        file = ./invidious/db_environment.age;
        mode = "600";
      };
    };

    networking.firewall.allowedTCPPorts = [
      3000
      8282
    ];

    system.activationScripts = {
      create_invidious_directories.text = ''
        mkdir -p /mnt/invidious/config/sql /mnt/invidious/config/docker
      '';

      create_invidious-network.text = ''
        ${pkgs.podman}/bin/podman network create invidious-network --ignore
      '';

      copy_invidious_files.text = ''
        cp -r ${invidious-source}/docker/init-invidious-db.sh /mnt/invidious/config/docker/
        cp -r ${invidious-source}/config/sql/* /mnt/invidious/config/sql/
      '';
    };

    virtualisation.oci-containers.containers = {
      invidious = {
        hostname = "invidious";
        image = "quay.io/invidious/invidious:master";

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
        pull = "newer";
        volumes = [
          "${config.age.secrets.invidious_environment.path}:/config/config.yml"
        ];
      };

      invidious_companion = {
        hostname = "invidious_companion";
        image = "quay.io/invidious/invidious-companion:latest";

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

      # inv_sig_helper = {
      #   hostname = "inv_sig_helper";
      #   image = "quay.io/invidious/inv-sig-helper:latest";

      #   cmd = [
      #     "--tcp"
      #     "0.0.0.0:12999"
      #   ];
      #   environment = {
      #     RUST_LOG = "info";
      #   };
      #   extraOptions = [
      #     "--cap-drop=ALL"
      #     "--read-only"
      #     "--security-opt=no-new-privileges:true"
      #   ];
      #   networks = [
      #     "invidious-network"
      #   ];
      #   pull = "newer";
      # };

      invidious-db = {
        hostname = "invidious-db";
        image = "docker.io/library/postgres:14";

        environmentFiles = [
          config.age.secrets.invidious-db_environment.path
        ];
        networks = [
          "invidious-network"
        ];
        pull = "newer";
        volumes = [
          "postgresdata:/var/lib/postgresql/data"

          "/mnt/invidious/config/sql:/config/sql"
          "/mnt/invidious/config/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh"
        ];
      };
    };
  }
