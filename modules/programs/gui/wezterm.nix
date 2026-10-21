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

      return config
    '';
  };
}
