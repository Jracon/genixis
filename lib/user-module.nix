# The optional per-user module of users/<name>.nix (docs/flake.md): it loads
# when the file exists, and this repository commits no such file today. The
# directory sits beside this file, so the helper decides the path.
name: if builtins.pathExists ../users/${name}.nix then [ ../users/${name}.nix ] else [ ]
