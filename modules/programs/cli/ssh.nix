{
  config,
  ...
}:

{
  age = {
    # the user key of this user, the only key a Home Manager layer reads (see docs/secrets.md)
    identityPaths = [
      "${config.home.homeDirectory}/.ssh/genixis_user"
    ];
    secrets.ssh_config = {
      file = ../../../.ssh/config.age;
      path = "${config.home.homeDirectory}/.ssh/genixis_config";
    };
  };

  # public material: the forge host key, verified under the forge name (see docs/secrets.md)
  home.file.".ssh/forge_known_hosts".source = ./forge-known-hosts;

  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;
    includes = [
      config.age.secrets.ssh_config.path
    ];
    # short names resolve via MagicDNS on the tailnet, or the router's DNS on the LAN
    settings = {
      # an agent keeps the key after the first use, so ssh asks the passphrase once per login session
      "*".AddKeysToAgent = "yes";
      # the hand-managed file stays first and writable; the committed file only supplements it
      "*".UserKnownHostsFile = "~/.ssh/known_hosts ~/.ssh/forge_known_hosts";
      desktop.User = "jademeskill";
      "media services".User = "root";
    };
  };
}
