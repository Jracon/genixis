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

  # add public SSH key to root user
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../.ssh/id_ed25519.pub
  ];
}
