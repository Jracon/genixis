{
  ...
}:

{
  age.secrets = {
    gamevault_db_password.file = ./gamevault/db_password.age;

    gamevault_admin_username.file = ./gamevault/admin_username.age;
    gamevault_admin_password.file = ./gamevault/admin_password.age;

    gamevault_igdb_client_id.file = ./gamevault/igdb_client_id.age;
    gamevault_igdb_client_secret.file = ./gamevault/igdb_client_secret.age; 
  };

  networking.firewall = {
    allowedTCPPorts = [
      1337
    ];
  };

  virtualisation.oci-containers.containers = {
    gamevault-backend = {
      hostname = "gamevault-backend";
      image = "phalcode/gamevault-backend:latest";

      environment = {
        DB_HOST = "gamevault-db";
        DB_USERNAME = "gamevault";
        DB_PASSWORD = age.secrets.gamevault_db_password.path;

        SERVER_ADMIN_USERNAME = age.secrets.gamevault_admin_username.path;
        SERVER_ADMIN_PASSWORD = age.secrets.gamevault_admin_password.path;
        SERVER_LOG_LEVEL = "debug";

        METADATA_IGDB_CLIENT_ID = age.secrets.gamevault_igdb_client_id.path;
        METADATA_IGDB_CLIENT_SECRET = age.secrets.gamevault_igdb_client_secret.path;
      };
      ports = [
        "1337:8080/tcp"
      ];
      pull = "always";
      volumes = [
        "/mnt/media/data/gamevault:/media"
        "/mnt/media/games/windows:/files"
      ];
    };

    gamevault-db = {
      hostname = "gamevault-db";
      image = "postgres:16";

      environment = {
        POSTGRES_DB = "gamevault";
        POSTGRES_USER = "gamevault";
        POSTGRES_PASSWORD = age.secrets.gamevault_db_password.path;
      };
      pull = "always";
      user = "1000:1000";
      volumes = [
        "/mnt/media/data/gamevault/db:/var/lib/postgresql/data"
      ];
    };
  };
}
