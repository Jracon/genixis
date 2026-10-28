{
  homeUsers,
  lib,
  ...
}:

{
  # enable SSH with standard security rules
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  system.activationScripts.create_ssh_directory.text = ''
    mkdir -p ~/.ssh
  '';

  # authorize every machine's public key (one per machine, .ssh/authorized/<machine>.pub) for root
  # and every Home Manager user
  users.users = lib.genAttrs homeUsers (_: {
    openssh.authorizedKeys.keyFiles = lib.filesystem.listFilesRecursive ../.ssh/authorized;
  });
}
