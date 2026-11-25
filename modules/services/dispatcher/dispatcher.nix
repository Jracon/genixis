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
  # allowlisted harness commands itself (issue #96). The store path of go
  # comes second, so a spawned leg runs the Go gate of the project tool
  # itself (issue #110): a worktree holds go from its devShell only when
  # the direnv environment of that worktree loaded, and a spawn outside a
  # loaded environment starts the leg with no toolchain
  unitPath = "${pkgs.python3}/bin:${pkgs.go}/bin:/etc/profiles/per-user/dev/bin:/run/current-system/sw/bin";
  dispatcher = "${pkgs.python3}/bin/python3 ${./dispatcher.py}";

  # no sandbox option may enter these user units: each of them must reach the
  # ssh config of dev, the tea login, and the whole home, and every sandbox
  # option in a user unit implies a user namespace (systemd 262,
  # systemd.exec(5), ProtectHome=), where root-owned files read as nobody and
  # ssh refuses its own config (verified on services, the run of issue 93).
  # The legs are bounded instead: the sandbox tier (modules/services/sandbox-tier.nix,
  # issue 607) writes the properties of the transient unit of each leg, and
  # the dispatcher passes them to systemd-run at spawn time. Inside that unit
  # no ssh file of dev is visible, so the git transport of a leg runs through
  # an agent that the dispatcher starts with the push key alone, and the
  # options of the ssh command come from the dispatcher, not from a config
  # file
  commonEnvironment = [
    "DISPATCHER_STATE_DIR=${stateDir}"
    "PATH=${unitPath}"
    # a login shell of dev exports TMUX_TMPDIR through the Home Manager
    # session variables, so tmux puts its socket under /run/user/1000. The
    # user manager sources no profile, so without this line every unit
    # reaches /tmp/tmux-1000/default instead: each spawned leg opens its
    # view window on that second server, in a second session named after
    # the project, and no attach of the owner shows it (issue #143). %t is
    # the runtime directory of the user (systemd.unit(5), Specifiers)
    "TMUX_TMPDIR=%t"
    # the sandbox tier of the legs (issue 607): with the knob set, each
    # spawn starts a leg-unit template instance on the system manager and
    # passes only the per-spawn argv and env through the request file of
    # the leg state (modules/services/dispatcher/leg-run.py). The templates
    # and the polkit delegation live in the tier module
    # (modules/services/sandbox-tier.nix), which activates with the same
    # webhook secret condition that gates this module, so the knob and the
    # templates land together
    "DISPATCHER_TIER=1"
    # the git transport of a leg inside the tier: ssh to the forge through
    # the tailnet name of this host (the forge ssh port of the container
    # mapping, ssh.nix and forgejo.nix hold the other halves), the key from
    # an agent that holds the push key alone, and the host key pinned by the
    # committed known_hosts file, which the checkout of the project carries
    "DISPATCHER_PUSH_KEY=%h/.ssh/claude-bot"
    "DISPATCHER_FORGE_HOST=forgejo.local.jracon.xyz"
    "DISPATCHER_FORGE_SSH_HOST=services"
    "DISPATCHER_FORGE_SSH_PORT=222"
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
            # through `project spawn --headless`, each inside a transient user
            # scope (issue #93), so the session machinery sits beside this
            # unit. A restart must still not kill that machinery: the daemon
            # that a leg started before the scopes existed lives on in the
            # cgroup of this unit, so only the python process is killed
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
