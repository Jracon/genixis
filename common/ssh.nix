{
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

  # add public SSH key to root user
  users.users."root".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFYN8DlBKCTbFYgl52VFImP58YRBaYdPTKuyaY6e37T"
  ];
}
