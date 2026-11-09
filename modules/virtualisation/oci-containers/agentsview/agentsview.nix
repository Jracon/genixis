{
  ...
}:

{
  # reachable through caddy at agentsview.local.jracon.xyz
  networking.firewall.allowedTCPPorts = [
    8790
  ];

  system.activationScripts.create_agentsview_directory.text = ''
    mkdir -p /mnt/agentsview
  '';

  virtualisation.oci-containers.containers.agentsview = {
    image = "ghcr.io/kenn-io/agentsview:0.46.1";

    hostname = "agentsview";
    pull = "newer";

    environment = {
      AGENTSVIEW_TELEMETRY_ENABLED = "0";

      # reads and labels only (issue 74, phase 4): point the scanner at the
      # read-only bind of the session directories of dev
      CLAUDE_PROJECTS_DIR = "/sessions/projects";
      TZ = "America/Phoenix";
    };
    ports = [
      "8790:8080"
    ];
    volumes = [
      "/mnt/agentsview:/data"
      "/home/dev/.claude:/sessions:ro"
    ];
  };
}
