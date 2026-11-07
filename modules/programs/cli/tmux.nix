{
  config,
  lib,
  pkgs,
  ...
}:

let
  # ANSI colour names, so the status bar follows the terminal's active scheme (dark or light)
  accent = config.genixis.palette.colors.signatureAnsi;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  # a path that a tmux update doesn't change: Home Manager boots out an agent whose plist changed,
  # and that kills every pane, including the one that runs the rebuild
  profile = config.home.profileDirectory;
  # the one keymap table, which the Option+K popup shows from any pane: the store copy of the
  # table, so every host reads the table of its own build
  keymapDoc = ../../../docs/keymap.md;
  # the table rendered for the popup: key to action in wrapped plain text, without the
  # conflict-check column. The renderer runs at build time, so the popup needs only the pager
  keymapTable = pkgs.runCommand "keymap-table" { nativeBuildInputs = [ pkgs.gawk ]; } ''
    awk -f ${./keymap-table.awk} ${keymapDoc} > $out
  '';
in
{
  config = {
    # the popups of the Option layer; docs/keymap.md holds the row and the conflict check of each
    # key. The keymap entry shows the rendered table itself, from any pane, on the pager of the
    # host; the markdown file stays the single source
    genixis.tmux.popups = {
      keymap = {
        command = "less ${keymapTable}";
        key = "k";
      };

      lazydocker = {
        command = "lazydocker";
        condition = config.programs.lazydocker.enable;
        # the key takes Shift, because M-d is fish kill-word
        key = "D";
      };

      lazygit = {
        command = "lazygit";
        key = "g";
      };
    };

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
        # the socket forward of a window of a remote login (issue #141) reaches new panes: WEZTERM_UNIX_SOCKET
        # names the forwarded socket, PROJECT_GUI_SOCKET the socket on the machine that owns the window
        set -ag update-environment " WEZTERM_UNIX_SOCKET PROJECT_GUI_SOCKET"
        # distinguish Ctrl+digit (and other modified keys) from the plain key; WezTerm sends CSI-u
        set -g extended-keys on
        set -as terminal-features ",xterm*:extkeys"

        # open splits and windows in the current pane's directory
        bind '"' split-window -v -c "#{pane_current_path}"
        bind % split-window -h -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"

        # Ctrl operates the tool in the pane (issue #145; the keymap table in docs/keymap.md names every
        # binding and its layer): Ctrl+0..9 in an ide window go to that tab of its nvim (0 = 10th),
        # from any pane; Ctrl+Tab and Ctrl+Shift+Tab (C-BTab to tmux) the next and previous.
        # Elsewhere the key goes to the program. The M-0..9 bindings below switch the tmux
        # window; the stock prefix digits keep their tmux default action
      ''
      + lib.concatMapStrings (n: ''
        bind -n C-${n} if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} ${n}'" "send-keys C-${n}"
      '') (map toString (lib.range 0 9))
      + lib.concatMapStrings (n: ''
        bind -n M-${n} select-window -t :=${n}
      '') (map toString (lib.range 1 9))
      + ''
        bind -n C-BTab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} prev'" "send-keys C-BTab"
        bind -n C-Tab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} next'" "send-keys C-Tab"

        # Shift+Enter reads the hovered file in yazi (ide-view). yazi only understands the kitty keyboard
        # protocol, which tmux doesn't forward, so it can't see Shift+Enter; send it Alt+Enter instead
        bind -n S-Enter if -F '#{==:#{pane_current_command},yazi}' 'send-keys M-Enter' 'send-keys S-Enter'

        # Ctrl+Shift+F opens the project-wide search of nvim (issues #165, #193): a pane cannot
        # read Shift on a control key without the kitty protocol, the same limit as the
        # Shift+Enter rewrite above, so an nvim pane gets the key as M-F. Every other pane gets
        # the C-f of the legacy encoding
        bind -n C-S-f if -F '#{==:#{pane_current_command},nvim}' 'send-keys M-F' 'send-keys C-f'

        # Option operates tmux (left Option sends Alt; issue #145): Option+arrows move between
        # panes, so Ctrl+arrows reach the tool in the pane. The keymap table in docs/keymap.md holds
        # the conflict check of each Option binding: fish loses its directory history and its
        # token search on the alt+arrows inside tmux; Shift+arrows keep the word movement
        bind -n M-Down select-pane -D
        bind -n M-Left select-pane -L
        bind -n M-Right select-pane -R
        bind -n M-Up select-pane -U

        # Option+0 selects the tenth window, as Ctrl+0 selects the tenth nvim tab; := picks the
        # window by its number, which honors base-index 1 (the stock prefix 0 is dead there)
        bind -n M-0 select-window -t :=10

        # Option+(Shift+)Tab switches to the next and the previous window (issue #165). M-BTab is
        # the shifted Tab, as C-BTab above; the chords ride the same extended-keys path as the
        # window digits. A desktop window manager owns Alt+Tab before WezTerm sees it, so there
        # the digits keep the window switching
        bind -n M-Tab next-window
        bind -n M-BTab previous-window

        # Option+W closes the window with no prompt (issue #165), as the middle-click on the
        # status bar does; fish keeps its alt-w, the description of the token under the
        # cursor, outside tmux
        bind -n M-w kill-window

        # status bar as a tab bar, at the top: middle-click closes, double-click renames or opens a window
        set -g status-position top
        bind -n MouseDown2Status kill-window -t=
        bind -n DoubleClick1Status command-prompt -I "#W" "rename-window -- '%%'"
        bind -n DoubleClick1StatusDefault new-window -c "#{pane_current_path}"

        # The popups of genixis.tmux.popups open in the current pane's directory. The lazydocker
        # key takes the shifted M-D, because M-d is fish kill-word. The prefix keeps the rare
        # tmux commands: the splits and the new window above, and the tmux defaults (detach,
        # copy mode, and the rest)
      ''
      + lib.concatMapStrings (
        popup:
        lib.optionalString popup.condition ''
          bind -n M-${popup.key} display-popup -E -d "#{pane_current_path}" -h 90% -w 90% ${popup.command}
        ''
      ) (lib.attrValues config.genixis.tmux.popups)
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
      # Home Manager writes `new-session -A -s 0` into the tmux configuration when this option is
      # on. That line creates a stray session 0 at every server start. It also attaches each client
      # that sources the configuration to that session. No host needs the option. The fish login
      # attach makes its session by itself, and a server starts on demand.
      newSession = false;
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
  };

  options.genixis.tmux.popups = lib.mkOption {
    default = { };
    description = "The popups that Option opens, by name. The module writes one bind line from each entry: Option plus the key of the entry runs the command of the entry in the directory of the current pane, while the condition of the entry holds. The popup fills 90 percent of the height and the width of the terminal, and it ends when the command ends.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          command = lib.mkOption {
            description = "The command that the popup runs.";
            type = lib.types.str;
          };

          condition = lib.mkOption {
            default = true;
            description = "The condition that installs the binding. The module writes the bind line only where the condition is true.";
            type = lib.types.bool;
          };

          key = lib.mkOption {
            description = "The key that opens the popup, after the M- that Option sends. An uppercase letter adds Shift.";
            type = lib.types.str;
          };
        };
      }
    );
  };
}
