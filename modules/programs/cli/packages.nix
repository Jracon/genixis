{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    bitwarden-cli
    glow # markdown reader, used by ide-view
    nixd # Nix language server
    nixfmt
    tailscale
    tea # Forgejo CLI
    unzip
  ];

  # programs with no configuration beyond enable
  programs = {
    bottom.enable = true;
    fd.enable = true;
    fzf.enable = true;
    jq.enable = true;
    nh.enable = true;
    ripgrep.enable = true;
    zoxide.enable = true;
  };
}
