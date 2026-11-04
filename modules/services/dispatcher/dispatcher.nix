{
  config,
  lib,
  pkgs,
  ...
}:

let
  # the gateway of the Podman default bridge. The forgejo container sits on
  # that bridge, so its webhook deliveries reach the host here with no
  # firewall opening. Verified on the host: the default bridge is the network
  # named `podman`, subnet 10.88.0.0/16, gateway 10.88.0.1. Confirm it with
  # `podman network inspect podman` and switch to the poll fallback when it
  # differs (see README.md in this directory)
  bridgeGateway = "10.88.0.1";
  receiverPort = 8741;

  stateDir = "%h/.local/state/dispatcher";
  # the user manager of a lingering user starts with no login environment,
  # so the units name the two profiles that hold project, tea, git, claude.
  # The store path of python3 comes first, so a spawned leg runs the two
  # allowlisted harness commands itself (issue #96)
  unitPath = "${pkgs.python3}/bin:/etc/profiles/per-user/dev/bin:/run/current-system/sw/bin";
  dispatcher = "${pkgs.python3}/bin/python3 ${./dispatcher.py}";

  # a leg must also run an impure flake check itself. The check reads
  # /etc/nixos/configuration.nix when it exists, and the configuration of
  # services then fails the hostId assertion of the media host. An empty
  # read-only tmpfs over /etc/nixos hides the host configuration, so the
  # check evaluates the dummy configuration instead. The forgejo runner
  # unit hides /etc/nixos for the same reason (forgejo.nix). A sandbox
  # option in a user unit implies PrivateUsers (systemd 254), so each unit
  # runs in a user namespace: dev keeps its own uid, files of other users
  # appear as nobody, and the spawned legs inherit the namespace
  legIsolation.TemporaryFileSystem = [
    "/etc/nixos:ro"
  ];

  commonEnvironment = [
    "DISPATCHER_STATE_DIR=${stateDir}"
    "PATH=${unitPath}"
  ];
in
{
  # the service exists only when the owner has created the secret file with
  # `agenix -e` (the pattern of the zai plan secret): nothing changes on the
  # host until then, so the module is additive and reversible
  config = lib.mkIf (builtins.pathExists ./webhook.age) {
    age.secrets.dispatcher_webhook = {
      file = ./webhook.age;

      # the receiver runs as a user service of dev, so the secret file must
      # be readable for dev and for no other non-root user
      group = "users";
      mode = "0400";
      owner = "dev";
    };

    # the user services must run at boot, with no dev login session
    users.users.dev.linger = true;

    # traffic from a container to the bridge gateway enters the input chain
    # of the host, so the forgejo container reaches the receiver only with a
    # firewall rule. The rule names the bridge interface, so no other network
    # can reach the port.
    networking.firewall.interfaces.podman0.allowedTCPPorts = [ receiverPort ];

    home-manager.users.dev.systemd.user = {
      services = {
        dispatcher-poll = {
          Service = legIsolation // {
            Environment = commonEnvironment;
            ExecStart = "${dispatcher} poll";
            Type = "oneshot";
          };
        };

        dispatcher-receiver = {
          Service = legIsolation // {
            Environment = commonEnvironment ++ [
              "DISPATCHER_BIND=${bridgeGateway}"
              "DISPATCHER_PORT=${toString receiverPort}"
              "DISPATCHER_WEBHOOK_SECRET_FILE=${config.age.secrets.dispatcher_webhook.path}"
            ];
            ExecStart = "${dispatcher} serve";
            # the sweep inside the receiver starts background agent sessions
            # through `project spawn --headless`; a restart of the receiver
            # must not kill them, so only the python process itself is killed
            KillMode = "process";
            Restart = "on-failure";
            RestartSec = "5s";
          };
          Install.WantedBy = [ "default.target" ];
        };

        dispatcher-run = {
          Service = legIsolation // {
            Environment = commonEnvironment;
            ExecStart = "${dispatcher} run";
            Type = "oneshot";
          };
        };
      };

      timers = {
        # the fallback of the receiver: off by default. When the bridge
        # facts fail, the owner stops the receiver and starts this timer
        # (systemctl --user, as dev). See README.md in this directory
        dispatcher-poll = {
          Timer = {
            OnBootSec = "2min";
            OnUnitActiveSec = "2min";
            Unit = "dispatcher-poll.service";
          };
        };

        # always on: it sweeps events the receiver queued but could not
        # process, so a crash costs at most one minute
        dispatcher-sweep = {
          Timer = {
            OnBootSec = "2min";
            OnUnitActiveSec = "1min";
            Unit = "dispatcher-run.service";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
