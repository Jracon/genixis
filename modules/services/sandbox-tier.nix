{
  config,
  lib,
  pkgs,
  ...
}:

let
  # the sandbox tier of issue 607, section S of issue 393: the bounds of each
  # spawned leg on this host. The tier has two halves, and this file is
  # security spine (docs/agent-context.md, Trust criterion 10): an agent wrote
  # it, and the owner reviews it line by line and merges it
  # (docs/adr/spine-work-by-agents.md). The oracle of the tier is the probe
  # harness of the dispatcher module (modules/services/dispatcher/sandbox-probe.py):
  # a run inside a spawned session quotes each control, and the run exits 0
  # when every control holds.
  #
  # half one, the forward proxy: squid answers on the loopback alone, and its
  # dstdomain allowlist is the only route of a leg to an off-tailnet address.
  # half two, the unit templates: the two transient-looking service templates
  # below are the units of each leg. They live on the system manager, because
  # only the system manager runs as root and so enforces the IP firewall: the
  # user manager skips IPAddressDeny and IPAddressAllow for non-root (the
  # manager warning of the first tier spawn, 2026-11-21 10:52), so the raw
  # egress and proxy-bypass controls of the oracle quoted the open state and
  # the owner ruled the system manager with delegation (issue 607, the record
  # of 2026-11-24). The dispatcher, a user service, starts and stops the
  # instances through systemctl, and the polkit delegation below grants that
  # for the two template names alone. A StartUnit call carries no unit
  # properties, so a leg-named grant cannot be abused to smuggle a User= or
  # an opened IPAddressAllow into a leg unit; the transient-unit property path
  # of systemd-run could, which is why the tier uses template instances. The
  # per-spawn data of a leg rides the request file that the dispatcher writes
  # and the ExecStart of the leg template reads
  # (modules/services/dispatcher/leg-run.py)

  # the home of dev, the user whose legs the tier bounds
  devHome = config.home-manager.users.dev.home.homeDirectory;
  devUid = config.users.users.dev.uid;
  # the project root of the loop: the checkout with main/ and the worktrees
  # beside it, the project memory, and the per-leg state that the dispatcher
  # writes (modules/services/dispatcher/dispatcher.py, prepare_leg_runtime)
  projectRoot = "${devHome}/projects/genixis";
  # the per-leg state of the dispatcher (dispatcher.py, LEG_STATE_ROOT): the
  # instance name of each template unit names the branch, and the binds and
  # output paths of the templates derive the per-leg paths from %i the way
  # leg_slug derives the state directory
  legStateRoot = "${projectRoot}/.claude-legs";
  # the socket directory of the tmux server of the owner: a leg opens its
  # view window through the socket that sits there
  # (modules/services/dispatcher/dispatcher.nix, TMUX_TMPDIR). The bind names
  # the directory alone, because a bind of the socket file itself goes stale
  # when the server restarts, and the whole runtime directory of dev stays
  # out: it also holds the private socket of the systemd user manager, and a
  # leg that reaches that socket starts further transient user units that
  # carry none of the tier properties, so every bound of the tier would be
  # escapable from inside the leg (the review of pull request 615). The minus
  # prefix lets the unit start when no tmux server runs yet; such a leg opens
  # no view window, and the window is a view, not a need of the leg
  tmuxSocketDir = "/run/user/${toString devUid}/tmux-${toString devUid}";
  # the socket of the nix daemon: nix build and nix eval of a leg reach the
  # daemon through it, and a connect to a unix socket needs write access to
  # its inode, so the read-only tree of ProtectSystem=strict would refuse it
  nixDaemonSocket = "/nix/var/nix/daemon-socket";
  # the tailnet range: the CGNAT block that every tailnet address lives in,
  # and the address of the resolver of the tailnet, 100.100.100.100, with it.
  # DNS of a leg flows to that resolver or to the local stub of resolved, so
  # both stay reachable
  tailnetRange = "100.64.0.0/10";
  # the container address of the forge on the default bridge of Podman
  # (lib/oci-containers.nix, forgeContainerAddress: the container claims
  # the address with a static assignment). The entry is deliberate, and it
  # bounds one address: the ssh port of the forge is the publish of its
  # container, and a publish of Podman is a DNAT rule that rewrites the
  # destination of a connect to the container address. The egress filter of
  # a leg unit reads the destination after that rewrite, so the allow list
  # must name the container address, and no entry for an address of this
  # host can pass the publish: the owner probe of 2026-11-25 ran a
  # root-level unit that allowlisted the LAN address of the publish, and
  # its connect still timed out (issue 658). The entry carries the ssh port
  # and the http port of the forge alone, because the address is the
  # container and no other port listens on it. The owner reviews the entry
  # line by line (docs/adr/spine-work-by-agents.md)
  inherit (import ../../lib/oci-containers.nix) forgeContainerAddress;
  # the loopback prefixes of the allow entry: the numeric expansion that
  # resource-control(5), Table 1, defines for the symbolic token localhost.
  # The transient-unit property path of systemd-run parses address prefixes
  # only, so it refuses the token with Failed to parse IP address prefix:
  # the first tier spawn of 2026-11-21 10:52 died before its unit was
  # created. The numeric form holds the same addresses on both paths, the
  # unit file and the property path, and the leg-units check of
  # lib/checks.nix rejects each allow entry that is no address prefix
  loopbackPrefixes = [
    "127.0.0.0/8"
    "::1"
  ];
  proxyPort = 3128;
  proxyUrl = "http://127.0.0.1:${toString proxyPort}";

  # the endpoint host of one plan: the same option that writes the plan files
  # (modules/programs/cli/claude.nix), so the proxy allowlist and the plans
  # share one source. The form of a base URL is https://host[/path]; the
  # assertion rejects any other form, so a new plan with a new form fails the
  # build instead of silently leaving the endpoint out of the allowlist
  planHost =
    url:
    let
      groups = builtins.match "https://([^/]+).*" url;
    in
    assert groups != null;
    builtins.head groups;
  planHosts = lib.unique (
    map (plan: planHost plan.baseUrl) (
      lib.attrValues config.home-manager.users.dev.genixis.claude.plans
    )
  );

  # the fixed entries beside the plan endpoints: the forge, github, and the
  # binary cache of nix
  fixedEntries = [
    "forgejo.local.jracon.xyz"
    "github.com"
    ".github.com"
    "cache.nixos.org"
  ];

  # a dot entry of dstdomain covers the bare host beside each subdomain, and
  # squid 7 ignores a covered pair with a warning at parse time: the first
  # switch of the tier logged the covered pair of github. The filter drops
  # each bare host whose dot entry sits in the same list, so the derivation
  # writes no covered pair, whatever side of the list the pair comes from
  allowlist =
    let
      hosts = planHosts ++ fixedEntries;
    in
    lib.filter (host: !builtins.elem ".${host}" hosts) hosts;

  # the token of the plan of every leg: an agenix secret of the home of
  # dev. Agenix decrypts each secret into /run/user/<uid>/agenix.d/
  # <generation>, points the symlink /run/user/<uid>/agenix at the live
  # generation, and the plans file zai.token names the entry zai_token of
  # that tree (modules/programs/cli/claude.nix, age.secrets.zai_token). The
  # plans bind carries the symlink alone: ProtectHome=tmpfs also hides
  # /run/user, so the target stayed absent inside the unit, and the plan
  # check of the first tier spawn after the rebuild of 2026-11-21 12:47
  # died on the dangling link. The read-only bind resolves the symlink
  # chain at unit start, and each spawn builds a fresh unit, so a rotation
  # under a new generation reaches every later leg. The bind names the
  # token alone: the whole agenix tree would expose every user secret to
  # every leg. The minus prefix keeps the unit startable while no
  # zai_token.age sits in the tree: the plan check of the spawn then names
  # the missing token through the envelope, where a hard bind would stop
  # the unit before any message could say why
  planToken = "/run/user/${toString devUid}/agenix/zai_token";

  # the environment entries that the template carries, and so the dispatcher
  # never passes: the proxy variables, because the model endpoints of a leg
  # answer through the proxy only (the raw egress is closed by the IP
  # firewall of the system manager), and GOPATH, which moves the module cache
  # of the go gate into the writable cache tree, so the per-leg state of a
  # branch holds its harness data alone and the backup member of the leg
  # state stays small (docs/backups.md). The variables carry both cases,
  # because the toolchain of a leg reads either (curl the lowercase, the go
  # tools of tea the uppercase). no_proxy keeps the loopback out of the
  # proxy, and ssh reads none of them, so ssh to the tailnet stays direct.
  # The per-leg environment (the config directory, the agent socket, the git
  # transport, PATH, TMUX_TMPDIR) rides the request file
  # (modules/services/dispatcher/leg-run.py), because the dispatcher derives
  # it per spawn and a template is authored once
  proxyEnvironment = {
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    no_proxy = "localhost,127.0.0.1,::1";
    NO_PROXY = "localhost,127.0.0.1,::1";
    GOPATH = "${devHome}/.cache/go";
  };

  # the bounds that both templates share: the whole file system read-only
  # beside the binds, every home hidden behind an empty read-only file
  # system (systemd.exec(5), ProtectHome=), a private /tmp, no new
  # privileges, an empty capability set, and a filtered syscall set. The
  # memory bound stays with the user slice of the spawn-storm layers
  # (docs/services.md), so no memory property appears here. In a system
  # unit no sandbox option implies a user namespace: the manager is root
  # and applies every bound itself
  commonBounds = {
    ProtectSystem = "strict";
    ProtectHome = "tmpfs";
    PrivateTmp = true;
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    SystemCallFilter = "@system-service";
  };

  # the writable and read-only file-system entries of the leg template. The
  # per-leg daemon socket entry mounts the socket directory of the leg state
  # over the hardcoded daemon root of the harness (/tmp/cc-daemon-<uid>,
  # dispatcher.py, daemon_socket_paths and DAEMON_TMP_ROOT), so the
  # supervisor socket lands in the leg state, stays reachable from outside
  # the unit through the host-side link, and the rest of /tmp stays private
  # (issue 633). systemd applies the bind entries after the private tmp is
  # set up, the way the plan token bind lands over the home that
  # ProtectHome=tmpfs hides
  legBinds = {
    BindPaths = [
      projectRoot
      "${devHome}/.cache"
      "${devHome}/.local/share/direnv"
      "-${tmuxSocketDir}"
      nixDaemonSocket
      "${legStateRoot}/%i/daemon-socket:/tmp/cc-daemon-${toString devUid}"
    ];
    ReadWritePaths = [
      projectRoot
      "${devHome}/.cache"
      "${devHome}/.local/share/direnv"
      "-${tmuxSocketDir}"
      nixDaemonSocket
    ];
    BindReadOnlyPaths = [
      "${devHome}/.claude"
      "${devHome}/.config/project/plans"
      "-${planToken}"
      "${devHome}/.config/tea"
    ];
  };

  # the template of the leg unit. Type=forking makes the unit outlive the
  # spawn: the initial process exits after the envelope, and the supervisor
  # of the leg and its sessions stay in the cgroup. ExitType=cgroup keeps
  # the unit active while one process of the cgroup stays
  # (systemd.service(5), ExitType=): the unit ends when the last process
  # leaves. The default ExitType=main ends the unit when the process that
  # the manager tracks as the main process exits, and Type=forking gives
  # the manager no reliable rule for that process over a cgroup that holds
  # the supervisor and its sessions (systemd.service(5), GuessMainPID=).
  # The run of issue 634 lost the unit that way: the exit of the session
  # process ended the unit, the kill phase of that stop killed the
  # supervisor, and the harness restart of the session found no supervisor
  # inside the unit and started the session process outside it. With the
  # cgroup exit type the supervisor survives the exit of a session process,
  # and the session process that the restart starts runs as a process of
  # the supervisor, inside the cgroup of the unit. The stdout and stderr of
  # the unit land in files of the leg state (%i expands in the append
  # paths, load-fragment.c runs the value through unit_path_printf),
  # because the envelope carries the exit code in meta and the files
  # replace the pipe for both. The IP firewall holds in the kernel here:
  # the leg reaches the loopback, the tailnet, and nothing else, so the
  # model endpoints answer only through the proxy
  legUnitService = {
    description = "the leg of the factory loop, instance %i";
    environment = proxyEnvironment;
    serviceConfig = {
      Type = "forking";
      ExitType = "cgroup";
      User = "dev";
      ExecStart = "${pkgs.python3}/bin/python3 ${./dispatcher/leg-run.py} ${legStateRoot}/%i";
      StandardOutput = "append:${legStateRoot}/%i/spawn.out";
      StandardError = "append:${legStateRoot}/%i/spawn.err";
      IPAddressDeny = "any";
      IPAddressAllow = loopbackPrefixes ++ [
        tailnetRange
        forgeContainerAddress
      ];
    }
    // commonBounds
    // legBinds;
  };

  # the template of the agent unit of a leg: the agent holds the push key
  # alone, touches nothing but its socket, and answers no network address,
  # so it runs under the shared bounds wherever they bite and carries no
  # allow entry: both access lists default to empty, so IPAddressDeny=any
  # alone leaves it no network address at all (systemd.resource-control(5),
  # the lists are empty by default). The agent never reads a file, so the
  # leg state bind serves the socket alone
  legAgentService = {
    description = "the ssh agent of one leg, instance %i";
    serviceConfig = {
      User = "dev";
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a ${legStateRoot}/%i/agent.sock";
      IPAddressDeny = "any";
      BindPaths = [ "${legStateRoot}/%i" ];
      ReadWritePaths = [ "${legStateRoot}/%i" ];
    }
    // commonBounds;
  };

  # the polkit delegation of the tier (the ruling of the owner on issue 607,
  # the record of 2026-11-24): the receiver, a user service of dev, starts
  # and stops the leg instances on the system manager, and polkit answers
  # those calls. The rule grants the action
  # org.freedesktop.systemd1.manage-units only when the subject is dev, the
  # unit detail names a leg template instance, and the verb is start or
  # stop; systemd 262 passes the unit name and the verb of each call as
  # polkit details (bus_verify_manage_units_async_impl,
  # src/core/dbus-util.c of the locked systemd, and the StartTransientUnit
  # and StartUnit/StopUnit methods that route through it). The verb check
  # is load-bearing: SetUnitProperties rides the same action with the verb
  # set-property, and a grant without the verb check would let any dev
  # process rewrite the bounds of a running leg, for example IPAddressAllow.
  # The unit check is load-bearing too: without it the grant would cover
  # every unit of the host. The instance charset is the leg slug set, so an
  # escaped or path-like instance name cannot widen the grant
  polkitRule = ''
    polkit.addRule(function(action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") {
            return;
        }
        if (subject.user != "dev") {
            return;
        }
        var unit = action.lookup("unit");
        var verb = action.lookup("verb");
        if (!unit || (verb != "start" && verb != "stop")) {
            return;
        }
        if (!/^leg-(unit|agent)@[A-Za-z0-9-]*\.service$/.test(unit)) {
            return;
        }
        return polkit.Result.YES;
    });
  '';

  # the squid config: the loopback alone listens, the allowlist is the only
  # destination, CONNECT runs against port 443 alone, and nothing is cached,
  # so the proxy keeps no state and no backup entry (docs/backups.md)
  #
  # configText replaces the whole file that the nixos module of the lock
  # writes (nixos/modules/services/networking/squid.nix), so this text
  # carries each runtime line of the module default itself. Without
  # pid_filename, squid opens its pid file inside the read-only store prefix
  # of its package and stops at pre-start: the failure of the first switch
  # of the tier. The pid line answers the PIDFile line of the unit, which
  # names /run/squid.pid. Without cache_effective_user, squid drops to
  # nobody and cannot write its logs, so the user line names the squid user
  # that the pre-start of the module hands the log directory to, and the two
  # log lines land under /var/log/squid, the one directory that the
  # pre-start creates
  squidConfig = ''
    http_port 127.0.0.1:${toString proxyPort}
    acl local_src src localhost 127.0.0.0/8 ::1
    acl allowed_dst dstdomain ${toString allowlist}
    acl ssl_ports port 443
    http_access deny CONNECT !ssl_ports
    http_access allow local_src allowed_dst
    http_access deny all
    cache deny all
    cache_effective_user squid squid
    pid_filename /run/squid.pid
    cache_log stdio:/var/log/squid/cache.log
    access_log stdio:/var/log/squid/access.log
  '';
in
{
  # the tier serves the legs of the dispatcher, so it exists exactly when the
  # dispatcher module is active (its webhook secret is committed)
  config = lib.mkIf (builtins.pathExists ./dispatcher/webhook.age) {
    services.squid = {
      enable = true;
      configText = squidConfig;
    };

    # the polkit daemon answers the spawn and stop calls of the receiver.
    # The delegation grants nothing beyond the two leg template names with
    # the two verbs, so the daemon exists for the tier alone on this host
    security.polkit = {
      enable = true;
      extraConfig = polkitRule;
    };

    # the two templates of the tier. Nothing wants them, so no instance
    # runs at boot: the dispatcher starts each instance at spawn time and
    # the manager collects it when the cgroup empties. The templates carry
    # every bound of the tier, so the properties of a leg unit are
    # root-authored here and never arrive through a spawn call
    systemd.services = {
      "leg-unit@" = legUnitService;
      "leg-agent@" = legAgentService;
    };
  };
}
