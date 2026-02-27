{
  llm-agents,
  pkgs,
  ...
}:

{
  environment.systemPackages = with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    opencode
    pi
  ];
}
