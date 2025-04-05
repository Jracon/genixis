{
  layout, 
  ...
}:

{
  system.activationScripts = {
    helper = {
      deps = [ "specialfs" ];
      text = ''
        grep -q 'disk-layout = "${layout}";' /tmp/etc/nixos/local.nix || sed -i '/^}/i\  disk-layout = "${layout}";' /tmp/etc/nixos/local.nix
        cp -r /tmp/etc /mnt
      '';
    };
  };
}