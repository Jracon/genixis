{
  programs.wezterm = {
    enable = true;

    extraConfig = ''
      return {
          font = wezterm.font(
              {
                  family = "FiraCode Nerd Font",
              }
          )
      }
    '';
  };
}
