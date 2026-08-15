{
  pkgs,
  ...
}:

{
  users.defaultUserShell = pkgs.fish;

  boot.loader = {
    generic-extlinux-compatible.configurationLimit = 5;
    grub.configurationLimit = 5;
    systemd-boot.configurationLimit = 5;
  };
  environment.systemPackages = [
    pkgs.isd
  ];
  programs = {
    fish.enable = true;
    nix-ld.enable = true;
  };
}
