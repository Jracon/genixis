{
  pkgs,
  ...
}:

{
  programs.vscodium = {
    enable = true;

    profiles.default = {
      enableExtensionUpdateCheck = true;
      enableUpdateCheck = true;
      extensions =
        (with pkgs.vscode-extensions; [
          anthropic.claude-code # Claude Code for VS Code
          mkhl.direnv # direnv
          vscode-icons-team.vscode-icons # vscode-icons
        ])
        ++ (with pkgs.open-vsx; [
          jeanp413.open-remote-ssh # Open Remote - SSH (VSCodium-compatible remote-ssh)
        ]);
      userSettings = builtins.fromJSON (builtins.readFile ./vscodium/settings.json);
    };
  };
}
