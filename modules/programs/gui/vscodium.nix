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
      userSettings = {
        "chat.disableAIFeatures" = true;
        "editor.accessibilitySupport" = "off";
        "editor.autoIndentOnPaste" = true;
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
        "git.confirmSync" = false;
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
          "reportCallIssue" = "none";
          "reportMissingTypeStubs" = "none";
          "reportUnknownMemberType" = "none";
        };
      };
    };
  };
}
