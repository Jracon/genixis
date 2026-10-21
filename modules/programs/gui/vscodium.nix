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
          esbenp.prettier-vscode # Prettier - Code formatter
          jnoortheen.nix-ide # Nix IDE
          mechatroner.rainbow-csv # Rainbow CSV
          mkhl.direnv # direnv
          mkhl.shfmt # shfmt
          ms-python.black-formatter # Black Formatter
          ms-python.isort # isort
          ms-python.python # Python
          ms-python.vscode-pylance # Pylance
          timonwong.shellcheck # ShellCheck
          vscode-icons-team.vscode-icons # vscode-icons
        ])
        ++ (with pkgs.open-vsx; [
          jeanp413.open-remote-ssh # Open Remote - SSH (VSCodium-compatible remote-ssh)
        ]);
      userSettings = builtins.fromJSON (builtins.readFile ./vscodium/settings.json);
    };
  };
}
