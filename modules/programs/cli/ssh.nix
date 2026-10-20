{
  config,
  ...
}:

{
  age = {
    identityPaths = [
      "${config.home.homeDirectory}/.ssh/genixis_secrets"
    ];
    secrets.ssh_config = {
      file = ./ssh-config.age;
      path = "${config.home.homeDirectory}/.ssh/genixis_config";
    };
  };

  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;
    includes = [
      config.age.secrets.ssh_config.path
    ];
  };
}
