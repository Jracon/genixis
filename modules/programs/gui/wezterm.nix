{
  programs.wezterm = {
    enable = true;

    enableZshIntegration = true;

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
