{
  llm-agents,
  pkgs,
  ...
}:

{
  environment = {
    systemPackages = with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
    ];

    # The claude-code wrapper defaults CLAUDE_CODE_CERT_STORE to "system", which on macOS
    # can't verify api.anthropic.com (UNABLE_TO_GET_ISSUER_CERT_LOCALLY); add Nix's CA bundle
    variables.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
  };
}
