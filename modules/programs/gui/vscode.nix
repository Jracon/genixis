{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    vscode # vscodium # TODO: When remote-ssh works properly, switch
  ];

  programs.vscode = {
    enable = true;
    # package = pkgs.vscodium; # TODO: When remote-ssh works properly, switch

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
        "workbench.layoutControl.enabled" = false; # NOTE: doesn't work when nested for some reason

        "editor" = {
          "detectIndentation" = false;
          "formatOnSave" = true;
          "formatOnSaveMode" = "file";
          "indentSize" = "tabSize";
          "minimap.enabled" = false;
          "tabSize" = 2;

          "rulers" = [
            80
          ];
        };

        "explorer" = {
          "confirmDelete" = false;
          "confirmDragAndDrop" = false;
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
