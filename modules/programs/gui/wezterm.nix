{
  programs.wezterm = {
    enable = true;

    extraConfig = ''
      local config = wezterm.config_builder()

      config.audible_bell = "Disabled"
      config.color_scheme = "Tokyo Night" -- matches nvim (tokyonight "night" style)
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
