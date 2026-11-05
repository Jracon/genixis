{
  pkgs,
  ...
}:

{
  programs.yazi = {
    enable = true;

    # no status bar: the narrow pane can't fit it (mode, size, name, permissions, position). Same
    # layout as yazi's own Root:layout, with the status row at height 0. git.yazi marks each file's
    # git status at the right of its row (ignored files in dark grey)
    initLua = ''
      require("git"):setup()

      function Root:layout()
        self._chunks = ui.Layout()
          :direction(ui.Layout.VERTICAL)
          :constraints({
            ui.Constraint.Length(1),
            ui.Constraint.Length(Tabs.height()),
            ui.Constraint.Fill(1),
            ui.Constraint.Length(0),
          })
          :split(self._area)
      end
    '';
    keymap.mgr.prepend_keymap = [
      {
        desc = "Enter the hovered directory, or open the file in the editor pane";
        on = "<Enter>";
        run = "plugin smart-enter";
      }
      {
        desc = "Read the hovered file in the editor pane";
        on = "<A-Enter>"; # tmux turns Shift+Enter into this in yazi panes (yazi never sees Shift+Enter inside tmux)
        run = "shell -- ide-view %h";
      }
      {
        desc = "Open the hovered file with the default application of the OS";
        on = "<S-F1>"; # WezTerm sends Shift+F1 for Cmd/Super+Enter, in yazi panes only (issue #149); tmux maps F13 sequences onto shifted F-keys, so F13 cannot pass through it
        run = "open"; # the open opener runs `open` on macOS and `xdg-open` on Linux
      }
    ];
    plugins = {
      git = pkgs.yaziPlugins.git;
      smart-enter = pkgs.yaziPlugins.smart-enter;
    };
    settings = {
      mgr = {
        # one column: no parent and no preview (the pane is narrow); h goes up, Shift+Enter reads a file
        ratio = [
          0
          1
          0
        ];
        show_hidden = true;
      };
      open.prepend_rules = [
        {
          mime = "text/*";
          use = "edit";
        }
      ];
      opener.edit = [
        {
          desc = "Edit";
          for = "unix";
          run = "ide-open %s"; # yazi substitutes %s with the selected paths (it does not pass them as $@)
        }
        {
          block = true;
          desc = "Edit here";
          for = "unix";
          run = "nvim %s";
        }
      ];
      # git.yazi needs a fetcher for files and one for directories
      plugin.prepend_fetchers = [
        {
          group = "git";
          run = "git";
          url = "*";
        }
        {
          group = "git";
          run = "git";
          url = "*/";
        }
      ];
    };
    # `y` opens yazi and cds the shell into the directory you quit in (new default for stateVersion >= 26.05)
    shellWrapperName = "y";
  };
}
