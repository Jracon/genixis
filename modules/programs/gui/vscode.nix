{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    vscode
  ];

  programs.vscode = {
    enable = true;

    profiles.default = {
      enableExtensionUpdateCheck = true;
      enableUpdateCheck = true;

      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide # Nix IDE
        ms-vscode-remote.remote-ssh # Remote - SSH
        ms-vscode-remote.remote-ssh-edit # Remote - SSH: Editing Configuration Files
        # ms-vscode.remote-explorer # Remote Explorer
        vscode-icons-team.vscode-icons # vscode-icons
      ];

      userSettings = {
        "chat.disableAIFeatures" = true;
        "notebook.lineNumbers" = "on";
        "update.showReleaseNotes" = false;
        "vsicons.dontShowNewVersionMessage" = true;
        "window.confirmSaveUntitledWorkspace" = false;

        "editor" = {
          "detectIndentation" = false;
          "indentSize" = "tabSize";
          "minimap.enabled" = false;
          "tabSize" = 2;

          "rulers" = [
            80
          ];
        };

        "git" = {
          "autofetch" = true;
          "enableSmartCommit" = true;
          "openRepositoryInParentFolders" = "always";
        };

        "workbench" = {
          "iconTheme" = "vscode-icons";
          "startupEditor" = "none";
        };
      };
    };
  };
}
