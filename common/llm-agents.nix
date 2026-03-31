{
  llm-agents,
  pkgs,
  ...
}:

{
  environment.systemPackages = with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    oh-my-opencode
    opencode
  ];
}
