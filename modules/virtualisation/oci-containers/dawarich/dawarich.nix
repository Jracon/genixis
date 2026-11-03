{
  config,
  pkgs,
  ...
}:

{
  age.secrets = {
    dawarich-db_environment.file = ./db_environment.age;
    dawarich_environment.file = ./environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    3001
  ];

  system.activationScripts = {
    create_dawarich-network.text = ''
      ${pkgs.podman}/bin/podman network create dawarich-network --ignore
    '';
    create_dawarich_directories.text = ''
      mkdir -p /mnt/dawarich/postgres /mnt/dawarich/public /mnt/dawarich/redis /mnt/dawarich/storage /mnt/dawarich/watched
    '';
  };

  virtualisation.oci-containers.containers = {
    # the image entrypoint is `bundle exec`, so the module must set the
    # web-entrypoint override that the upstream compose file sets; that
    # entrypoint creates the database, migrates, and seeds before it starts Rails
    dawarich = {
      image = "freikin/dawarich:1.20.1";

      hostname = "dawarich";
      pull = "newer";

      cmd = [
        "bin/rails"
        "server"
        "-p"
        "3000"
        "-b"
        "::"
      ];
      dependsOn = [
        "dawarich-db"
        "dawarich-redis"
      ];
      entrypoint = "web-entrypoint.sh";
      environment = {
        APPLICATION_PROTOCOL = "https";
        BACKGROUND_PROCESSING_CONCURRENCY = "2";
        DATABASE_HOST = "dawarich-db";
        DATABASE_PORT = "5432";
        PROMETHEUS_EXPORTER_ENABLED = "false";
        RAILS_ENV = "production";
        RAILS_LOG_TO_STDOUT = "true";
        REDIS_URL = "redis://dawarich-redis:6379";
        SELF_HOSTED = "true";
        SIDEKIQ_EMBEDDED = "true";
        STORE_GEODATA = "true";
        TIME_ZONE = "America/Phoenix";
        WEB_CONCURRENCY = "0";
      };
      environmentFiles = [
        config.age.secrets.dawarich_environment.path
      ];
      extraOptions = [
        "--health-cmd=wget -q -O /dev/null http://127.0.0.1:3000/api/v1/health"
        "--health-interval=10s"
        "--health-retries=30"
        "--health-start-period=30s"
        "--health-timeout=10s"
        "--stop-timeout=60"
      ];
      networks = [
        "dawarich-network"
      ];
      ports = [
        "3001:3000"
      ];
      volumes = [
        "/mnt/dawarich/postgres:/dawarich_db_data"
        "/mnt/dawarich/public:/var/app/public"
        "/mnt/dawarich/storage:/var/app/storage"
        "/mnt/dawarich/watched:/var/app/tmp/imports/watched"
      ];
    };

    dawarich-db = {
      image = "docker.io/postgis/postgis:17-3.5-alpine";

      hostname = "dawarich-db";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.dawarich-db_environment.path
      ];
      extraOptions = [
        "--health-cmd=pg_isready -U postgres -d dawarich_production"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=10s"
        "--shm-size=1g"
      ];
      networks = [
        "dawarich-network"
      ];
      volumes = [
        "/mnt/dawarich/postgres:/var/lib/postgresql/data"
        "/mnt/dawarich/redis:/var/shared"
      ];
    };

    dawarich-redis = {
      image = "docker.io/redis:8-alpine";

      hostname = "dawarich-redis";
      pull = "newer";

      cmd = [
        "redis-server"
        "--save"
        "900 1"
        "--save"
        "300 10"
        "--appendonly"
        "no"
      ];
      extraOptions = [
        "--health-cmd=redis-cli --raw incr ping"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=10s"
      ];
      networks = [
        "dawarich-network"
      ];
      volumes = [
        "/mnt/dawarich/redis:/data"
      ];
    };
  };
}
