{
  pkgs,
  ...
}:

{
  users.defaultUserShell = pkgs.zsh;

  boot.loader = {
    generic-extlinux-compatible.configurationLimit = 5;
    grub.configurationLimit = 5;
    systemd-boot.configurationLimit = 5;
  };
  environment.systemPackages = [
    pkgs.isd
  ];
  programs = {
    nix-ld.enable = true;
    zsh.enable = true;
  };
}
