{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    ast-grep
    bitwarden-cli
    glow # markdown reader, used by ide-view
    nixd # Nix language server
    nixfmt
    python3Packages.mkdocs-material # markdown viewer with rendered diagrams (docs/cli.md)
    rns # Reticulum network stack tools (see docs/services.md)
    tailscale
    unzip
  ];

  # tools that agents should prefer (see claude.nix)
  genixis.claude.tools = {
    ast-grep.description = "search and rewrite code by syntax tree, instead of `rg` for structural patterns.";
    fd.description = "find files by name, instead of `find`; it respects `.gitignore`.";
    jq.description = "query and edit JSON.";
    mkdocs.description = "serve the markdown of a directory on localhost, with Mermaid diagrams drawn, instead of reading the diagram blocks as source text.";
    rg.description = "search text, instead of `grep`; it respects `.gitignore`.";
    tea = {
      description = "Forgejo CLI, the `gh` of the self-hosted Forgejo server.";
      package = pkgs.tea;
    };
  };

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
