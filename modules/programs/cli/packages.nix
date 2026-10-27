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
    tailscale
    unzip
  ];

  # tools that agents should prefer (see claude.nix)
  genixis.claude.tools = {
    ast-grep.description = "search and rewrite code by syntax tree, instead of `rg` for structural patterns: `ast-grep run -p '<pattern>' -l <lang>`.";
    fd.description = "find files by name, instead of `find`; respects `.gitignore`.";
    jq.description = "query and edit JSON.";
    rg.description = "search text, instead of `grep`; respects `.gitignore`.";
    tea = {
      description = "Forgejo CLI, the `gh` of the self-hosted Forgejo server: pull requests, issues, releases. Named logins; pick one with `--login`.";
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
