{
  llm-agents,
  pkgs,
  ...
}:

{
  environment = {
    # claude-code comes from nixpkgs, which builds the native binary (issue #166)
    systemPackages =
      with llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      [
        ccusage
        qmd
        semble
      ]
      ++ [ pkgs.claude-code ];

    # The claude-code wrapper defaults CLAUDE_CODE_CERT_STORE to "system", which on macOS
    # can't verify api.anthropic.com (UNABLE_TO_GET_ISSUER_CERT_LOCALLY); add Nix's CA bundle
    variables.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
  };

  # document the installed tools for agents (see modules/programs/cli/claude.nix)
  home-manager.sharedModules = [
    {
      genixis.claude.tools = {
        qmd.description = "search Markdown in indexed collections, instead of `rg` over the same files.";
        semble.description = "search code by meaning, when you do not know the exact words for `rg`.";
      };
    }
  ];
}
