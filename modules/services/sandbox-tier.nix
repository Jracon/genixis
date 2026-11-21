{
  config,
  lib,
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
  # half two, the unit spec: /etc/genixis/sandbox-tier.json names the systemd
  # properties of the transient unit of each leg. The dispatcher reads the
  # file at spawn time and passes each property to systemd-run, so the bounds
  # of the leg unit live in this file. The bounds of the agent unit of each
  # leg live in the second home, the dispatcher (dispatcher.py,
  # agent_unit_properties): the unit binds its per-branch state directory,
  # whose path the dispatcher computes at spawn time, so the static spec
  # cannot name it, and a bind of the shared parent would open the state of
  # every sibling leg to each agent.

  # the home of dev, the user whose legs the tier bounds
  devHome = config.home-manager.users.dev.home.homeDirectory;
  # the project root of the loop: the checkout with main/ and the worktrees
  # beside it, the project memory, and the per-leg state that the dispatcher
  # writes (modules/services/dispatcher/dispatcher.py, prepare_leg_runtime)
  projectRoot = "${devHome}/projects/genixis";
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
  tmuxSocketDir = "/run/user/${toString config.users.users.dev.uid}/tmux-${toString config.users.users.dev.uid}";
  # the socket of the nix daemon: nix build and nix eval of a leg reach the
  # daemon through it, and a connect to a unix socket needs write access to
  # its inode, so the read-only tree of ProtectSystem=strict would refuse it
  nixDaemonSocket = "/nix/var/nix/daemon-socket";
  # the tailnet range: the CGNAT block that every tailnet address lives in,
  # and the address of the resolver of the tailnet, 100.100.100.100, with it.
  # DNS of a leg flows to that resolver or to the local stub of resolved, so
  # both stay reachable
  tailnetRange = "100.64.0.0/10";
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

  # the systemd properties of the transient unit of a leg. ProtectHome=tmpfs
  # hides every home path behind an empty read-only file system, and the bind
  # entries below are the only paths that stay visible: systemd documents
  # tmpfs as the mode that admits bound subpaths, where yes admits none
  # (systemd.exec(5), ProtectHome=). ReadWritePaths beside each writable bind
  # reopens it for writing under the read-only tree of ProtectSystem=strict.
  # IPAddressDeny with IPAddressAllow bounds egress at the address level: a
  # leg reaches the loopback, the tailnet, and nothing else, so the model
  # endpoints answer only through the proxy. The memory bound stays with the
  # user slice of the spawn-storm layers (docs/services.md), so no memory
  # property appears here
  unitProperties = [
    "ProtectSystem=strict"
    "ProtectHome=tmpfs"
    "PrivateTmp=yes"
    "NoNewPrivileges=yes"
    "CapabilityBoundingSet="
    "SystemCallFilter=@system-service"
    "IPAddressDeny=any"
    "IPAddressAllow=localhost ${tailnetRange}"
    "BindPaths=${projectRoot}"
    "ReadWritePaths=${projectRoot}"
    "BindPaths=${devHome}/.cache"
    "ReadWritePaths=${devHome}/.cache"
    "BindPaths=${devHome}/.local/share/direnv"
    "ReadWritePaths=${devHome}/.local/share/direnv"
    "BindPaths=-${tmuxSocketDir}"
    "ReadWritePaths=-${tmuxSocketDir}"
    "BindPaths=${nixDaemonSocket}"
    "ReadWritePaths=${nixDaemonSocket}"
    "BindReadOnlyPaths=${devHome}/.claude"
    "BindReadOnlyPaths=${devHome}/.config/project/plans"
    "BindReadOnlyPaths=${devHome}/.config/tea"
  ];

  # the proxy environment of a leg. The proxy variables carry both cases,
  # because the toolchain of a leg reads either (curl the lowercase, the go
  # tools of tea the uppercase). no_proxy keeps the loopback out of the proxy,
  # and ssh reads none of them, so ssh to the tailnet stays direct. GOPATH
  # moves the module cache of the go gate into the writable cache tree, so
  # the per-leg state of a branch holds its harness data alone and the
  # backup member of the leg state stays small (docs/backups.md)
  proxyEnvironment = {
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    no_proxy = "localhost,127.0.0.1,::1";
    NO_PROXY = "localhost,127.0.0.1,::1";
    GOPATH = "${devHome}/.cache/go";
  };

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

    environment.etc."genixis/sandbox-tier.json".text = builtins.toJSON {
      inherit unitProperties;
      environment = proxyEnvironment;
    };
  };
}
