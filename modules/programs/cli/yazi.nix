{
  lib,
  pkgs,
  ...
}:

let
  # if a read-only viewer is standing in for the editor pane (see ide-view), swap nvim back into
  # place and close the viewer
  restoreEditor = ''
    restore_editor() {
      local viewer
      viewer=$(tmux show-option -pqv -t "$IDE_EDITOR_PANE" @ide_viewer)
      if [ -n "$viewer" ] && tmux display-message -p -t "$viewer" '#{pane_id}' >/dev/null 2>&1; then
        tmux swap-pane -s "$viewer" -t "$IDE_EDITOR_PANE"
        tmux set-option -pu -t "$IDE_EDITOR_PANE" @ide_viewer
        tmux kill-pane -t "$viewer"
      fi
    }
  '';

  # inside an `ide` session, open files in its nvim pane (over the --listen socket) and focus it;
  # anywhere else, fall back to nvim in a new tmux window. The opener must not block: a blocking
  # opener makes yazi suspend and re-detect the terminal, a 3-5 second stall on every open
  ideOpen = pkgs.writeShellApplication {
    name = "ide-open";
    text = ''
      ${restoreEditor}
      if [ -n "''${IDE_NVIM_SOCK:-}" ]; then
        restore_editor
        # after a `:q` the editor pane is back at its shell: start a fresh nvim there instead of
        # falling through to a new window, and give its socket up to 2 seconds to appear
        if [ ! -S "$IDE_NVIM_SOCK" ] &&
          [ "$(tmux display-message -p -t "$IDE_EDITOR_PANE" '#{pane_current_command}' 2>/dev/null)" = fish ]; then
          tmux send-keys -t "$IDE_EDITOR_PANE" "nvim --listen $IDE_NVIM_SOCK" Enter
          for _ in $(seq 40); do
            [ -S "$IDE_NVIM_SOCK" ] && break
            sleep 0.05
          done
        fi
      fi
      if [ -n "''${IDE_NVIM_SOCK:-}" ] && [ -S "$IDE_NVIM_SOCK" ]; then
        tmux select-pane -t "$IDE_EDITOR_PANE"
        # each file in a tab (genixis.ide.open), passed as a list of Vim strings (' doubled)
        sq="'"
        paths=()
        for path in "$@"; do
          paths+=("$sq''${path//$sq/$sq$sq}$sq")
        done
        list=$(IFS=,; echo "''${paths[*]}")
        # --headless: without it the client starts its own TUI, which fails under yazi's raw tty
        nvim --headless --server "$IDE_NVIM_SOCK" \
          --remote-expr "luaeval('require(\"genixis.ide\").open(_A)', [$list])" >/dev/null
      elif [ -n "''${TMUX:-}" ]; then
        tmux new-window nvim "$@"
      else
        echo "ide-open: not in an ide or tmux session; use yazi's Open with (O) for a blocking nvim" >&2
        exit 1
      fi
    '';
  };

  # `ide-tab <window> <n|next|prev>`: tmux's Ctrl+0..9 (and Ctrl+(Shift+)Tab) in an ide window
  # shows tab n (0 = 10th), or the next or previous tab, of its nvim and focuses it, whichever pane
  # has focus
  ideTab = pkgs.writeShellApplication {
    name = "ide-tab";
    text = ''
      ${restoreEditor}
      IDE_EDITOR_PANE=$(tmux show-option -wqv -t "$1" @ide_editor)
      sock=$(tmux show-option -wqv -t "$1" @ide_sock)
      restore_editor
      tmux select-pane -t "$IDE_EDITOR_PANE"
      [ -S "$sock" ] || exit 0
      case $2 in
        next) call="step(1)" ;;
        prev) call="step(-1)" ;;
        *) call="tab($2)" ;;
      esac
      nvim --headless --server "$sock" --remote-expr "luaeval('require(\"genixis.ide\").$call')" >/dev/null
    '';
  };

  # read-only viewer in the editor pane's place: the viewer runs in a throwaway tmux session and is
  # swapped with the nvim pane, so it is a real pane (Ctrl+arrows still move between panes) and nvim
  # keeps running untouched out of sight. `q` swaps nvim back. glow renders markdown; everything
  # else goes through bat. Outside an `ide` session it falls back to a popup.
  ideView = pkgs.writeShellApplication {
    name = "ide-view";
    text = ''
      ${restoreEditor}
      view() {
        case $1 in
          *.md | *.markdown) ${lib.getExe pkgs.glow} --pager "$1" ;;
          *) bat --paging=always "$1" ;;
        esac
      }

      if [ "$1" = --run ]; then
        # runs inside the viewer pane: $2 is the editor pane, $3 the file
        view "$3" || true
        tmux swap-pane -s "$TMUX_PANE" -t "$2"
        tmux set-option -pu -t "$2" @ide_viewer
        tmux select-pane -t "$2"
      elif [ "$1" = --popup ]; then
        view "$2"
      elif [ -n "''${IDE_EDITOR_PANE:-}" ]; then
        restore_editor
        read -r w h < <(tmux display-message -p -t "$IDE_EDITOR_PANE" '#{pane_width} #{pane_height}')
        viewer=$(tmux new-session -d -P -F '#{pane_id}' -s "ide-view-$$" -x "$w" -y "$h" \
          "$0 --run $(printf '%q %q' "$IDE_EDITOR_PANE" "$1")")
        tmux set-option -p -t "$IDE_EDITOR_PANE" @ide_viewer "$viewer"
        tmux swap-pane -s "$viewer" -t "$IDE_EDITOR_PANE"
        tmux select-pane -t "$viewer"
      else
        tmux display-popup -w 90% -h 90% -E "$0 --popup $(printf '%q' "$1")"
      fi
    '';
  };
in
{
  home.packages = [
    ideOpen
    ideTab
    ideView
  ];

  programs.yazi = {
    enable = true;

    # no status bar: the narrow pane can't fit it (mode, size, name, permissions, position). Same
    # layout as yazi's own Root:layout, with the status row at height 0
    initLua = ''
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
    ];
    plugins.smart-enter = pkgs.yaziPlugins.smart-enter;
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
    };
    # `y` opens yazi and cds the shell into the directory you quit in (new default for stateVersion >= 26.05)
    shellWrapperName = "y";
  };
}
