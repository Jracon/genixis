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
        esbenp.prettier-vscode # Prettier
        jnoortheen.nix-ide # Nix IDE
        mkhl.shfmt # shfmt
        ms-python.black-formatter # Black Formatter
        ms-python.python # Python
        ms-python.vscode-pylance # Pylance
        ms-vscode-remote.remote-ssh # Remote - SSH
        ms-vscode-remote.remote-ssh-edit # Remote - SSH: Editing Configuration Files
        # ms-vscode.remote-explorer # Remote Explorer
        timonwong.shellcheck # ShellCheck
        vscode-icons-team.vscode-icons # vscode-icons
      ];
      userSettings = {
        "chat.disableAIFeatures" = true;
        "editor.accessibilitySupport" = "off";
        "editor.autoIndentOnPaste" = true;
        "editor.detectIndentation" = false;
        "editor.fontFamily" = "FiraCode Nerd Font";
        "editor.fontLigatures" = true;
        "editor.formatOnPaste" = true;
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
        "python.analysis.typeCheckingMode" = "strict";
        "terminal.integrated.fontLigatures.enabled" = true;
        "terminal.integrated.suggest.enabled" = false;
        "update.showReleaseNotes" = false;
        "vsicons.dontShowNewVersionMessage" = true;
        "window.confirmSaveUntitledWorkspace" = false;
        "workbench.iconTheme" = "vscode-icons";
        "workbench.layoutControl.enabled" = false;
        "workbench.startupEditor" = "none";

        "[python]" = {
          "editor.defaultFormatter" = "ms-python.black-formatter";
          "editor.formatOnSave" = true;
          "editor.tabSize" = 4;

          "editor.codeActionsOnSave" = {
            "source.organizeImports" = "explicit";
          };
        };
        "python.analysis.diagnosticSeverityOverrides" = {
          "reportAttributeAccessIssue" = "none";
          "reportMissingTypeStubs" = "none";
          "reportUnknownMemberType" = "none";
        };
      };
    };
  };
}
