{
  ...
}:

{
  services.openssh = {
    enable = true;
    settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
    };
  };

  users.users."8".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINFYN8DlBKCTbFYgl52VFImP58YRBaYdPTKuyaY6e37T"
  ];
}