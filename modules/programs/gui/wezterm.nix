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
      -- home tab opens in the projects directory, the window title is
      -- pinned to user@host and the tab title to home, so the project
      -- tool finds this window and puts its session tabs in it. A start
      -- with a program of its own keeps that program and sets no titles.
      wezterm.on("gui-startup", function(cmd)
        if cmd ~= nil and cmd.args ~= nil and #cmd.args > 0 then
          wezterm.mux.spawn_window(cmd)
          return
        end
        local shell = os.getenv("SHELL")
        if shell == nil or shell == "" then
          shell = "fish"
        end
        local host = wezterm.hostname()
        if host == nil or host == "" then
          host = "localhost"
        end
        host = string.gsub(host, "%..*", "")
        local user = os.getenv("USER")
        if user == nil or user == "" then
          user = "user"
        end
        local tab, _, window = wezterm.mux.spawn_window({
          args = { shell, "-C", "fastfetch" },
          cwd = wezterm.home_dir .. "/projects",
        })
        window:set_title(string.lower(user) .. "@" .. string.lower(host))
        tab:set_title("home")
      end)

      return config
    '';
  };
}
