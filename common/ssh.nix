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

  # add public SSH key to root and every Home Manager user; dev stays keyless until it gets its own
  users.users = lib.genAttrs (lib.remove "dev" homeUsers) (_: {
    openssh.authorizedKeys.keyFiles = [
      ../.ssh/id_ed25519.pub
    ];
  });
}
