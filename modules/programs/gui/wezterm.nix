{
  config,
  lib,
  themes,
  ...
}:

let
  palette = config.genixis.palette.colors;
in
{
  programs.wezterm = {
    enable = true;

    extraConfig = ''
      local config = wezterm.config_builder()

      config.audible_bell = "Disabled"
      -- fixterms CSI-u: lets tmux tell Ctrl+1..9 from 1..9 without the kitty protocol (breaks arrows in tmux 3.6)
      config.enable_csi_u_key_encoding = true
      config.color_schemes = ${lib.generators.toLua { } (themes.lib.weztermSchemes palette)}
      -- follow the OS appearance (wezterm.gui only exists in the GUI process)
      local appearance = wezterm.gui and wezterm.gui.get_appearance() or "Dark"
      config.color_scheme = appearance:find("Dark") and "${palette.name}-dark" or "${palette.name}-light"
      config.font = wezterm.font("FiraCode Nerd Font")
      config.hide_tab_bar_if_only_one_tab = true -- tmux handles tabs and splits
      config.scrollback_lines = 10000
      -- left Option sends Alt/Meta (fish, tmux and nvim bindings); right Option still types special characters
      config.send_composed_key_when_left_alt_is_pressed = false
      config.send_composed_key_when_right_alt_is_pressed = true

      -- issue #101: the first window of the GUI is the host window. The
      -- home tab opens in the home directory, the window title is
      -- user@host and the tab title is home, so the project tool finds
      -- this window and puts its session tabs in it. A start with a
      -- program of its own keeps that program and sets no titles.
      local user = os.getenv("USER")
      if user == nil or user == "" then
        user = "user"
      end
      local host = wezterm.hostname()
      if host == nil or host == "" then
        host = "localhost"
      end
      host = string.gsub(host, "%..*", "")
      -- the title of the window of this user on this host: user@host,
      -- both parts in lower case and the host without its domain
      local hostTitle = string.lower(user) .. "@" .. string.lower(host)
      -- the tab title of the home tab of this host window
      local homeTitle = "home"

      -- the marker of a host window lives in the pinned title of its home
      -- tab: the reserved home name on this machine, or the user@host of
      -- the login of a delegated window. A pane title push cannot reach a
      -- pinned tab title (issue #115). This returns the window title that
      -- the marker stands for, or nil for a name that is no marker.
      local function markerTitle(name)
        if name == homeTitle then
          return hostTitle
        elseif name ~= nil and string.find(name, "^[^@%s]+@[^@%s]+$") then
          return name
        end
        return nil
      end

      -- issue #142: the new-tab key serves the window it is pressed in. The
      -- title of a window names a login when it holds the marker form and is
      -- not this user on this host: such a window runs the new tab on its
      -- login, with the ssh command of its home tab, so every tab of the
      -- window is a shell on the remote host. Every other window keeps the
      -- default program, and so does a new window, which carries no marker.
      -- The remote home command is the same line the project tool runs on
      -- the home tab of that window (remoteHomeCommand, wezterm.go); the
      -- copy here must stay word for word the same, and a test of the tool
      -- holds the two together.
      local remoteHomeCommand = [[exec env PROJECT_HOME_TAB=1 $SHELL -lc 'command -v fastfetch >/dev/null 2>&1 && exec "$SHELL" -l -C fastfetch; exec "$SHELL" -l']]
      local function newTabAction()
        return wezterm.action_callback(function(window, pane)
          -- the title of the window is computed and written back (issue
          -- #115), so the mux reports the marker, whatever the panes push
          local title = wezterm.mux.get_window(window:window_id()):get_title()
          local target = markerTitle(title)
          if target == nil or target == hostTitle then
            window:perform_action(wezterm.action.SpawnTab "CurrentPaneDomain", pane)
            return
          end
          window:perform_action(
            wezterm.action.SpawnCommandInNewTab {
              args = { "ssh", "-o", "ConnectTimeout=10", "-t", target, "--", remoteHomeCommand },
            },
            pane
          )
        end)
      end
      -- Ctrl+(Shift+)Tab go to tmux (nvim tabs in an ide window) instead of switching WezTerm tabs
      config.keys = {
        { key = "Tab", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment },
        { key = "Tab", mods = "CTRL|SHIFT", action = wezterm.action.DisableDefaultAssignment },
        -- the default new-tab keys, Cmd+T on macOS and Ctrl+Shift+T on Linux
        { key = "T", mods = "SUPER", action = newTabAction() },
        { key = "T", mods = "CTRL|SHIFT", action = newTabAction() },
      }

      wezterm.on("gui-startup", function(cmd)
        if cmd ~= nil and cmd.args ~= nil and #cmd.args > 0 then
          wezterm.mux.spawn_window(cmd)
          return
        end
        local shell = os.getenv("SHELL")
        if shell == nil or shell == "" then
          shell = "fish"
        end
        local tab, _, window = wezterm.mux.spawn_window({
          args = { shell, "-C", "fastfetch" },
          cwd = wezterm.home_dir,
        })
        window:set_title(hostTitle)
        tab:set_title(homeTitle)
      end)

      -- issue #135: the home tab shows where its shell works, not its
      -- marker. The marker stays pinned in the tab title, and this event
      -- computes the display from the title of the active pane, which fish
      -- pushes as the working directory (fish_title, fish.nix): the home
      -- tab of this machine shows the directory alone, and the home tab of
      -- a remote login names its login before the directory, for example
      -- dev@services: ~. Every other tab keeps the default title, so the
      -- tab of a session keeps its pinned session name.
      wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
        local marker = markerTitle(tab.tab_title)
        local paneTitle = tab.active_pane.title or ""
        if marker == nil or paneTitle == "" then
          return nil
        end
        if tab.tab_title == homeTitle then
          return wezterm.truncate_right(paneTitle, max_width)
        end
        return wezterm.truncate_right(marker .. ": " .. paneTitle, max_width)
      end)

      -- issue #115: a pane title replaces a pinned window title, so the
      -- title of a host window is computed, never pinned. The marker is
      -- the pinned title of the home tab: home on this machine, or the
      -- user@host of the login of a delegated window. The event returns
      -- the marker as the window title and writes it back, so the panes of
      -- the window cannot keep their own titles there, not in the title
      -- bar and not in what wezterm cli list reports. Every other window
      -- keeps the title that its active pane pushes.
      wezterm.on("format-window-title", function(tab, pane, tabs, panes, config)
        local title = nil
        for _, t in ipairs(tabs) do
          title = markerTitle(t.tab_title)
          if title ~= nil then
            break
          end
        end
        local window = nil
        if tab.window_id ~= nil then
          window = wezterm.mux.get_window(tab.window_id)
        end
        if title == nil and window ~= nil then
          -- the home tab can be closed: a title of the marker form stands
          local current = window:get_title()
          if current and string.find(current, "^[^@%s]+@[^@%s]+$") then
            title = current
          end
        end
        if title == nil then
          return nil
        end
        if window ~= nil and window:get_title() ~= title then
          window:set_title(title)
        end
        return title
      end)

      return config
    '';
  };
}
