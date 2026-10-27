{
  llm-agents,
  pkgs,
  ...
}:

{
  environment = {
    systemPackages = with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      ccusage
      gitnexus
      semble
      qmd
    ];

    # The claude-code wrapper defaults CLAUDE_CODE_CERT_STORE to "system", which on macOS
    # can't verify api.anthropic.com (UNABLE_TO_GET_ISSUER_CERT_LOCALLY); add Nix's CA bundle
    variables.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
  };

  # document the installed tools for agents (see modules/programs/cli/claude.nix)
  home-manager.sharedModules = [
    {
      genixis.claude.tools = {
        gitnexus.description = "graph-powered code intelligence: query a repository's structure and dependencies.";
        qmd.description = "local search engine for docs, notes, and knowledge bases.";
        semble.description = "fast local code search by meaning; use it when `rg` needs exact words.";
      };
    }
  ];
}
