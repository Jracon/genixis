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
        qmd.description = "search Markdown in indexed collections: `qmd query '<question>'`. It indexes nothing until `qmd collection add <dir>`; `qmd collection list` shows what exists.";
        semble.description = "search code by meaning, when you do not know the exact words for `rg`: `semble search '<natural-language query>' [path]`. `semble find-related <file> <line>` finds similar code. `--content docs` searches docs instead of code.";
      };
    }
  ];
}
