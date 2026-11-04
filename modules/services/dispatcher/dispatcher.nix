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
  # so the units name the two profiles that hold project, tea, git, claude
  unitPath = "/etc/profiles/per-user/dev/bin:/run/current-system/sw/bin";
  dispatcher = "${pkgs.python3}/bin/python3 ${./dispatcher.py}";

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

    home-manager.users.dev.systemd.user = {
      services = {
        dispatcher-poll = {
          Service = {
            Environment = commonEnvironment;
            ExecStart = "${dispatcher} poll";
            Type = "oneshot";
          };
        };

        dispatcher-receiver = {
          Service = {
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
          Service = {
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
