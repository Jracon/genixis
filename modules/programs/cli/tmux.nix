{
  config,
  pkgs,
  ...
}:

let
  # ANSI colour names, so the status bar follows the terminal's active scheme (dark or light)
  accent = config.genixis.palette.colors.signatureAnsi;
in
{
  programs.tmux = {
    enable = true;

    baseIndex = 1;
    clock24 = true;
    disableConfirmationPrompt = true;
    escapeTime = 10; # long delays make Esc lag in nvim
    extraConfig = ''
      # 24-bit colour from the outer terminal
      set -as terminal-features ",*:RGB"
      # let nvim and remote shells set the system clipboard (OSC 52)
      set -g set-clipboard on
      set -g renumber-windows on
      # distinguish Ctrl+digit (and other modified keys) from the plain key; WezTerm sends CSI-u
      set -g extended-keys on
      set -as terminal-features ",xterm*:extkeys"

      # open splits and windows in the current pane's directory
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Ctrl+1..9 jump to that window
      bind -n C-1 select-window -t 1
      bind -n C-2 select-window -t 2
      bind -n C-3 select-window -t 3
      bind -n C-4 select-window -t 4
      bind -n C-5 select-window -t 5
      bind -n C-6 select-window -t 6
      bind -n C-7 select-window -t 7
      bind -n C-8 select-window -t 8
      bind -n C-9 select-window -t 9

      # Ctrl+arrows move between panes
      bind -n C-Down select-pane -D
      bind -n C-Left select-pane -L
      bind -n C-Right select-pane -R
      bind -n C-Up select-pane -U

      # status bar as a tab bar: middle-click closes, double-click renames or opens a window
      bind -n MouseDown2Status kill-window -t=
      bind -n DoubleClick1Status command-prompt -I "#W" "rename-window -- '%%'"
      bind -n DoubleClick1StatusDefault new-window -c "#{pane_current_path}"

      # Alt+drag selects a rectangle (columns of output)
      bind -n M-MouseDrag1Pane if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -M ; send-keys -X rectangle-toggle'

      # Alt+wheel scrolls ten lines at a time in copy mode
      bind -T copy-mode-vi M-WheelUpPane send-keys -N 10 -X scroll-up
      bind -T copy-mode-vi M-WheelDownPane send-keys -N 10 -X scroll-down

      # colours: the status bar is transparent; `reverse` turns the accent into a block whose text
      # is the terminal background, which keeps it legible in dark and light
      set -g message-style "fg=${accent}"
      set -g pane-active-border-style "fg=${accent}"
      set -g pane-border-style "fg=brightblack"
      set -g status-style "bg=default,fg=brightblack"
      set -g window-status-current-format " #I:#W#{window_flags} "
      set -g window-status-current-style "fg=${accent},reverse,bold"
      set -g window-status-format " #I:#W#{window_flags} "
    '';
    focusEvents = true; # nvim autoread/gitsigns refresh on pane focus
    historyLimit = 50000;
    keyMode = "vi";
    mouse = true;
    newSession = true;
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = better-mouse-mode;
        # wheel sends Up/Down to pagers that don't ask for the mouse (bat/less, man, delta)
        extraConfig = ''
          set -g @emulate-scroll-for-no-mouse-alternate-buffer on
        '';
      }
      {
        plugin = yank;
        # mouse drag-copy goes to the system clipboard, not just the tmux buffer
        extraConfig = ''
          set -g @yank_selection_mouse clipboard
        '';
      }
    ];
    terminal = "tmux-256color";
  };
}
