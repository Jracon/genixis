{
  ...
}:

{
  programs.firefox.enable = if pkgs.stdenv.isDarwin then 
                              false
                            else
                              true;
}
