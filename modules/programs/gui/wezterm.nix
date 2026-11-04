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
      -- Ctrl+(Shift+)Tab go to tmux (nvim tabs in an ide window) instead of switching WezTerm tabs
      config.keys = {
        { key = "Tab", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment },
        { key = "Tab", mods = "CTRL|SHIFT", action = wezterm.action.DisableDefaultAssignment },
      }
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

      -- issue #115: a pane title replaces a pinned window title, so the
      -- title of a host window is computed, never pinned. The marker is
      -- the home tab: home on this machine, or the user@host of the login
      -- of a delegated window. The event returns the marker as the window
      -- title and writes it back, so the panes of the window cannot keep
      -- their own titles there, not in the title bar and not in what
      -- wezterm cli list reports. Every other window keeps the title that
      -- its active pane pushes.
      wezterm.on("format-window-title", function(tab, pane, tabs, panes, config)
        local title = nil
        for _, t in ipairs(tabs) do
          local name = t.tab_title
          if name == homeTitle then
            title = hostTitle
            break
          elseif name and string.find(name, "^[^@%s]+@[^@%s]+$") then
            title = name
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
