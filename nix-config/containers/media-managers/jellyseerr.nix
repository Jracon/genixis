{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    jellyseerr = {
      hostname = "jellyseerr";
      image = "fallenbagel/jellyseerr:latest";

      environment = {
        TZ = "America/Phoenix";
      };
      ports = [ "5055" ];
      pull = "always";
      volumes = [ "/mnt/media/data/jellyseerr:/app/config" ];
    };
  };
}