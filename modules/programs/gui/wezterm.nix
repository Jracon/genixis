{
  programs.wezterm = {
    enable = true;

    enableFishIntegration = true;

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
