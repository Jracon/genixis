{
  config,
  pkgs,
  ...
}:

let
  # the non-secret lines of the upstream prod.env of wger-project/docker. The
  # secret lines live in environment.age: SECRET_KEY, SITE_URL,
  # CSRF_TRUSTED_ORIGINS, and PS_DATABASE_URI. The app reads PS_DATABASE_URI as
  # its own database URL when DJANGO_DB_ENGINE is unset, so the PowerSync name
  # of the variable is the upstream shape, not a PowerSync deployment here.
  appEnvironment = {
    ACCESS_TOKEN_LIFETIME = "10";
    ALLOW_GUEST_USERS = "False";
    ALLOW_REGISTRATION = "False";
    ALLOW_UPLOAD_VIDEOS = "True";
    AXES_COOLOFF_TIME = "30";
    AXES_ENABLED = "True";
    AXES_FAILURE_LIMIT = "10";
    AXES_HANDLER = "axes.handlers.cache.AxesCacheHandler";
    AXES_IPWARE_META_PRECEDENCE_ORDER = "HTTP_X_FORWARDED_FOR,REMOTE_ADDR";
    AXES_IPWARE_PROXY_COUNT = "2";
    AXES_LOCKOUT_PARAMETERS = "ip_address";
    CACHE_API_EXERCISES_CELERY = "True";
    CACHE_API_EXERCISES_CELERY_FORCE_UPDATE = "True";
    CELERY_BACKEND = "redis://wger-cache:6379/2";
    CELERY_BROKER = "redis://wger-cache:6379/2";
    CELERY_WORKER_CONCURRENCY = "2";
    DJANGO_CACHE_BACKEND = "django_redis.cache.RedisCache";
    DJANGO_CACHE_CLIENT_CLASS = "django_redis.client.DefaultClient";
    DJANGO_CACHE_LOCATION = "redis://wger-cache:6379/1";
    DJANGO_CACHE_TIMEOUT = "1296000";
    DJANGO_CLEAR_STATIC_FIRST = "False";
    DJANGO_COLLECTSTATIC_ON_STARTUP = "True";
    DJANGO_DEBUG = "False";
    DJANGO_PERFORM_MIGRATIONS = "True";
    DOWNLOAD_INGREDIENTS_FROM = "WGER";
    EXERCISE_CACHE_TTL = "2419200";
    EXPOSE_PROMETHEUS_METRICS = "False";
    GUNICORN_CMD_ARGS = "--workers 3 --threads 2 --worker-class gthread --timeout 240";
    LOG_LEVEL_PYTHON = "INFO";
    MIN_ACCOUNT_AGE_TO_TRUST = "21";
    NUMBER_OF_PROXIES = "2";
    REFRESH_TOKEN_LIFETIME = "2880";
    SYNC_EXERCISES_CELERY = "True";
    SYNC_EXERCISE_IMAGES_CELERY = "True";
    SYNC_EXERCISE_VIDEOS_CELERY = "True";
    SYNC_INGREDIENTS_CELERY = "True";
    SYNC_INGREDIENTS_DUMP_URL = "https://wger.de/media/ingredients/ingredients.jsonl.gz";
    TIME_ZONE = "America/Phoenix";
    TZ = "America/Phoenix";
    USE_CELERY = "True";
    USE_RECAPTCHA = "False";
    WGER_INSTANCE = "https://wger.de";
    WGER_PORT = "8000";
    WGER_USE_GUNICORN = "True";
    # two proxies stand before the app, caddy and wger-nginx: each one appends
    # one entry to X-Forwarded-For, and each one counts in the two settings
    # above and in this one
    X_FORWARDED_PROTO_HEADER_SET = "True";
  };
in
{
  age.secrets = {
    wger-db_environment.file = ./db_environment.age;
    wger_environment.file = ./environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    8888
  ];

  system.activationScripts = {
    create_wger-network.text = ''
      ${pkgs.podman}/bin/podman network create wger-network --ignore
    '';
    # the image writes static, media, and beat as the container user (UID 1000)
    # and expects those directories readable by every user, because wger-nginx
    # serves two of them as its own user
    create_wger_directories.text = ''
      mkdir -p /mnt/wger/beat /mnt/wger/media /mnt/wger/postgres /mnt/wger/redis /mnt/wger/static
      chown 1000:1000 /mnt/wger/beat /mnt/wger/media /mnt/wger/static
    '';
  };

  virtualisation.oci-containers.containers = {
    wger = {
      image = "docker.io/wger/server:2.7.0";

      hostname = "wger";
      pull = "newer";

      dependsOn = [
        "wger-cache"
        "wger-db"
      ];
      environment = appEnvironment;
      environmentFiles = [
        config.age.secrets.wger_environment.path
      ];
      extraOptions = [
        "--health-cmd=wget --no-verbose --tries=1 -O /dev/null http://127.0.0.1:8000/api/v2/version/"
        "--health-interval=10s"
        "--health-retries=5"
        # the first start loads the fixtures, collects the static files, and
        # migrates the database, so it needs a long start period
        "--health-start-period=300s"
        "--health-timeout=5s"
        "--stop-timeout=60"
      ];
      networks = [
        "wger-network"
      ];
      volumes = [
        "/mnt/wger/media:/home/wger/media"
        "/mnt/wger/static:/home/wger/static"
      ];
    };

    wger-cache = {
      image = "docker.io/library/redis:8-alpine";

      hostname = "wger-cache";
      pull = "newer";

      # the flags carry the deltas of the upstream redis.conf: no protected
      # mode, because the app containers connect without a password, a 1 GB
      # ceiling with volatile-lru eviction, and snapshots instead of the
      # append-only log
      cmd = [
        "redis-server"
        "--appendonly"
        "no"
        "--maxmemory"
        "1gb"
        "--maxmemory-policy"
        "volatile-lru"
        "--protected-mode"
        "no"
        "--save"
        "3600 1 300 100 60 10000"
      ];
      extraOptions = [
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=5s"
      ];
      networks = [
        "wger-network"
      ];
      volumes = [
        "/mnt/wger/redis:/data"
      ];
    };

    wger-celery-beat = {
      image = "docker.io/wger/server:2.7.0";

      hostname = "wger-celery-beat";
      pull = "newer";

      cmd = [
        "/start-beat"
      ];
      dependsOn = [
        "wger-celery-worker"
      ];
      environment = appEnvironment;
      environmentFiles = [
        config.age.secrets.wger_environment.path
      ];
      networks = [
        "wger-network"
      ];
      volumes = [
        "/mnt/wger/beat:/home/wger/beat"
      ];
    };

    wger-celery-worker = {
      image = "docker.io/wger/server:2.7.0";

      hostname = "wger-celery-worker";
      pull = "newer";

      cmd = [
        "/start-worker"
      ];
      dependsOn = [
        "wger"
      ];
      environment = appEnvironment;
      environmentFiles = [
        config.age.secrets.wger_environment.path
      ];
      extraOptions = [
        "--health-cmd=celery -A wger inspect ping"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=5s"
      ];
      networks = [
        "wger-network"
      ];
      volumes = [
        "/mnt/wger/media:/home/wger/media"
      ];
    };

    wger-db = {
      image = "docker.io/library/postgres:15-alpine";

      hostname = "wger-db";
      pull = "newer";

      # the command is the upstream one. wal_level=logical serves the deferred
      # PowerSync mobile sync, and the other flags are the upstream tuning
      cmd = [
        "postgres"
        "-c"
        "wal_level=logical"
        "-c"
        "shared_buffers=256MB"
        "-c"
        "effective_cache_size=768MB"
        "-c"
        "work_mem=8MB"
        "-c"
        "random_page_cost=1.1"
        "-c"
        "max_connections=30"
      ];
      environmentFiles = [
        config.age.secrets.wger-db_environment.path
      ];
      extraOptions = [
        # -h forces the TCP check, so the initdb phase, which listens on the
        # unix socket only, cannot report ready too early
        "--health-cmd=pg_isready -h localhost -U wger"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=5s"
        "--shm-size=256m"
      ];
      networks = [
        "wger-network"
      ];
      volumes = [
        "/mnt/wger/postgres:/var/lib/postgresql/data"
      ];
    };

    wger-nginx = {
      image = "docker.io/library/nginx:stable";

      hostname = "wger-nginx";
      pull = "newer";

      dependsOn = [
        "wger"
      ];
      extraOptions = [
        "--health-cmd=service nginx status"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=5s"
      ];
      networks = [
        "wger-network"
      ];
      ports = [
        "8888:80"
      ];
      volumes = [
        "${./nginx.conf}:/etc/nginx/conf.d/default.conf:ro"
        "/mnt/wger/media:/wger/media:ro"
        "/mnt/wger/static:/wger/static:ro"
      ];
    };
  };
}
