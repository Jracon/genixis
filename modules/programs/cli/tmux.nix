{
  config,
  lib,
  pkgs,
  ...
}:

let
  # re-proportions the panes of an `ide` window (ids stored as window options by `ide`) to the
  # window size: yazi 15% (24-40 columns), claude 30% (at least 40), shell 20% of the height
  ideLayout = pkgs.writeShellApplication {
    name = "ide-layout";
    text = ''
      files=$(tmux show-option -wqv -t "$1" @ide_files)
      [ -n "$files" ] || exit 0
      agent=$(tmux show-option -wqv -t "$1" @ide_agent)
      shell=$(tmux show-option -wqv -t "$1" @ide_shell)
      read -r w h < <(tmux display-message -p -t "$1" '#{window_width} #{window_height}')

      files_w=$((w * 15 / 100))
      files_w=$((files_w < 24 ? 24 : files_w > 40 ? 40 : files_w))
      agent_w=$((w * 30 / 100))
      agent_w=$((agent_w < 40 ? 40 : agent_w))
      shell_h=$((h * 20 / 100))
      shell_h=$((shell_h < 6 ? 6 : shell_h))

      tmux resize-pane -t "$files" -x "$files_w" || true
      tmux resize-pane -t "$agent" -x "$agent_w" || true
      tmux resize-pane -t "$shell" -y "$shell_h" || true
    '';
  };
  # ANSI colour names, so the status bar follows the terminal's active scheme (dark or light)
  accent = config.genixis.palette.colors.signatureAnsi;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  # a path that a tmux update doesn't change: Home Manager boots out an agent whose plist changed,
  # and that kills every pane, including the one that runs the rebuild
  profile = config.home.profileDirectory;
in
{
  home.packages = [ ideLayout ];

  # macOS credits a server that a WezTerm started to that WezTerm, and blocks its LAN connections once
  # that WezTerm quits. `tmux -D` listens on the default socket, and it keeps running with no sessions
  launchd.agents.tmux = {
    enable = isDarwin;

    config = {
      EnvironmentVariables = {
        LANG = "en_US.UTF-8"; # launchd sets none, and panes inherit it
        # for what the server runs itself (run-shell, hooks, popups); fish in a pane sets its own
        PATH = lib.concatStringsSep ":" [
          "${profile}/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
          "/opt/homebrew/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
      KeepAlive = true; # also starts a fresh server after `tmux kill-server`
      ProcessType = "Interactive"; # panes run builds; launchd must not throttle them like a background job
      ProgramArguments = [
        "${profile}/bin/tmux"
        "-D"
      ];
      RunAtLoad = true;
      SoftResourceLimits.NumberOfFiles = 61440; # launchd's default of 256 breaks nix builds in panes
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/tmux-server.log";
    };
  };

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
      # terminal title: the session name, so a project's WezTerm window keeps one title whatever its tabs show
      set -g set-titles on
      set -g set-titles-string "#S"
      # distinguish Ctrl+digit (and other modified keys) from the plain key; WezTerm sends CSI-u
      set -g extended-keys on
      set -as terminal-features ",xterm*:extkeys"

      # open splits and windows in the current pane's directory
      bind '"' split-window -v -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Ctrl+0..9: in an ide window, that tab of its nvim (0 = 10th), from any pane; Ctrl+Tab and
      # Ctrl+Shift+Tab (C-BTab to tmux) the next and previous. Elsewhere the key goes to the program.
      # Windows are prefix+0..9 (tmux's default)
    ''
    + lib.concatMapStrings (n: ''
      bind -n C-${n} if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} ${n}'" "send-keys C-${n}"
    '') (map toString (lib.range 0 9))
    + ''
      bind -n C-BTab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} prev'" "send-keys C-BTab"
      bind -n C-Tab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} next'" "send-keys C-Tab"

      # Shift+Enter reads the hovered file in yazi (ide-view). yazi only understands the kitty keyboard
      # protocol, which tmux doesn't forward, so it can't see Shift+Enter; send it Alt+Enter instead
      bind -n S-Enter if -F '#{==:#{pane_current_command},yazi}' 'send-keys M-Enter' 'send-keys S-Enter'

      # Ctrl+arrows move between panes
      bind -n C-Down select-pane -D
      bind -n C-Left select-pane -L
      bind -n C-Right select-pane -R
      bind -n C-Up select-pane -U

      # status bar as a tab bar, at the top: middle-click closes, double-click renames or opens a window
      set -g status-position top
      bind -n MouseDown2Status kill-window -t=
      bind -n DoubleClick1Status command-prompt -I "#W" "rename-window -- '%%'"
      bind -n DoubleClick1StatusDefault new-window -c "#{pane_current_path}"

      # big popups for the git and docker TUIs, opened in the current pane's directory
      bind g display-popup -E -d "#{pane_current_path}" -h 90% -w 90% lazygit
    ''
    + lib.optionalString config.programs.lazydocker.enable ''
      bind D display-popup -E -d "#{pane_current_path}" -h 90% -w 90% lazydocker
    ''
    + ''
      # Alt+drag selects a rectangle (columns of output)
      bind -n M-MouseDrag1Pane if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -M ; send-keys -X rectangle-toggle'

      # Alt+wheel scrolls ten lines at a time in copy mode
      bind -T copy-mode-vi M-WheelUpPane send-keys -N 10 -X scroll-up
      bind -T copy-mode-vi M-WheelDownPane send-keys -N 10 -X scroll-down

      # keep `ide` windows proportioned when the terminal is resized or a client attaches
      set-hook -g client-attached 'run-shell -b "ide-layout #{window_id}"'
      set-hook -g client-resized 'run-shell -b "ide-layout #{window_id}"'

      # colours: the status bar is transparent; `reverse` turns the accent into a block whose text
      # is the terminal background, which keeps it legible in dark and light
      set -g message-style "fg=${accent}"
      set -g pane-active-border-style "fg=${accent}"
      set -g pane-border-style "fg=brightblack"
      # no `[session]` on the left: the window names already say what's open
      set -g status-left ""
      set -g status-style "bg=default,fg=brightblack"
      set -g window-status-current-format " #I:#W#{window_flags} "
      set -g window-status-current-style "fg=${accent},reverse,bold"
      set -g window-status-format " #I:#W#{window_flags} "
    '';
    focusEvents = true; # nvim autoread/gitsigns refresh on pane focus
    historyLimit = 50000;
    keyMode = "vi";
    mouse = true;
    newSession = !isDarwin; # the launchd server would keep a stray session 0 from the moment of login
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
    shell = lib.mkIf isDarwin "${profile}/bin/fish"; # launchd's SHELL isn't guaranteed to be fish
    terminal = "tmux-256color";
  };
}
