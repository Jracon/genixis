{
  ...
}:

{
  security.unprivilegedUsernsClone = true;

  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      autoPrune = {
        enable = true;
        dates = "daily";

        flags = [
          "--all"
        ];
      };
    };
  };

  users.users.root = {
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
      {
        startUid = 1000;
        count = 1;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
      {
        startGid = 1000;
        count = 1;
      }
    ];

    extraGroups = [
      "podman"
    ];
  };
}
