{
  llm-agents,
  pkgs,
  ...
}:

{
  environment = {
    systemPackages =
      with llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      [
        ccusage
        hunk
        qmd
        semble
        tuicr
        zat
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
        hunk.description = "annotate the live `hunk` diff view of a person and read a diff in slices, instead of printing the whole diff.";
        qmd.description = "search Markdown in indexed collections, instead of `rg` over the same files.";
        semble.description = "search code by meaning, when you do not know the exact words for `rg`.";
        zat.description = "outline a Go, Python, or Markdown file as symbols with line ranges, instead of reading the whole file for a few symbols.";
      };

      # hunk ships its own agent skill for the annotation workflow; the file comes from the
      # installed package, so no vendored copy drifts from it
      home.file.".claude/skills/hunk-review/SKILL.md".source = "${
        llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hunk
      }/share/hunk/skills/hunk-review/SKILL.md";
    }
  ];
}
