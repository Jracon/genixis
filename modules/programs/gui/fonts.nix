{
  pkgs,
  ...
}:

{
  fonts.fontconfig.enable = true;

  home.packages = [
    # unhinted: every host display is high-density, and the hinted build drops
    # the infinite-arrow ligatures (docs/terminal-aesthetic.md)
    pkgs.maple-mono.NF-unhinted
  ];
}
