# The one read of the machine-private local files. docs/flake.md names the
# files: /etc/nixos/local.nix on NixOS and for a standalone home,
# /etc/nix-darwin/local.nix for a standalone home on Darwin, and
# /tmp/etc/nixos/local.nix at install time. The first file of the list that
# exists loads, and no file gives the empty attrset.
list:
let
  # walk the list until one file exists
  read =
    rest:
    if rest == [ ] then
      { }
    else if builtins.pathExists (builtins.head rest) then
      import (builtins.head rest)
    else
      read (builtins.tail rest);
in
read list
