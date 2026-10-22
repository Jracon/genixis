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
        # focus first: --remote waits on any prompt (e.g. an existing swap file) shown in that pane
        tmux select-pane -t "$IDE_EDITOR_PANE"
        # --headless: without it the client starts its own TUI, which fails under yazi's raw tty
        nvim --headless --server "$IDE_NVIM_SOCK" --remote "$@"
      elif [ -n "''${TMUX:-}" ]; then
        tmux new-window nvim "$@"
      else
        echo "ide-open: not in an ide or tmux session; use yazi's Open with (O) for a blocking nvim" >&2
        exit 1
      fi
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
    ideView
  ];

  programs.yazi = {
    enable = true;

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
      # one column: no parent and no preview (the pane is narrow); h goes up, Shift+Enter reads a file
      mgr.ratio = [
        0
        1
        0
      ];
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
