{
  pkgs,
  ...
}:

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

      # open splits and windows in the current pane's directory
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
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
      # Ctrl-h/j/k/l move between tmux panes and nvim splits alike (prefix + Ctrl-l clears the screen)
      vim-tmux-navigator
      yank
    ];
    terminal = "tmux-256color";
  };
}
