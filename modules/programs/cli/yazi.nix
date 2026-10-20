{
  programs.yazi = {
    enable = true;

    # `y` opens yazi and cds the shell into the directory you quit in (new default for stateVersion >= 26.05)
    shellWrapperName = "y";
  };
}
