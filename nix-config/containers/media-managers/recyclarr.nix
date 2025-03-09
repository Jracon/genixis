{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    recyclarr = {
      hostname = "recyclarr";
      image = "ghcr.io/recyclarr/recyclarr";

      environment = {
        TZ = "America/Phoenix";
      };
      pull = "always";
      volumes = [ 
        "/mnt/media/data/recyclarr:/config" 
      ];
      user = "1000:1000";
    };
  };
}