{
  llm-agents,
  pkgs,
  ...
}:

{
  environment.systemPackages = with llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    codex
    gemini-cli
    oh-my-opencode
    opencode
  ];
}
