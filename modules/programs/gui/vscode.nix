{
  pkgs,
  ...
}:

{
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
        "editor.detectIndentation" = false;
        "editor.fontFamily" = "FiraCode Nerd Font";
        "editor.fontLigatures" = true;
        "editor.formatOnSave" = true;
        "editor.formatOnSaveMode" = "file";
        "editor.indentSize" = "tabSize";
        "editor.minimap.enabled" = false;
        "editor.tabSize" = 2;
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "git.autofetch" = true;
        "git.enableSmartCommit" = true;
        "git.openRepositoryInParentFolders" = "always";
        "notebook.lineNumbers" = "on";
        "terminal.integrated.fontLigatures.enabled" = true;
        "update.showReleaseNotes" = false;
        "vsicons.dontShowNewVersionMessage" = true;
        "window.confirmSaveUntitledWorkspace" = false;
        "workbench.iconTheme" = "vscode-icons";
        "workbench.layoutControl.enabled" = false;
        "workbench.startupEditor" = "none";
      };
    };
  };
}
