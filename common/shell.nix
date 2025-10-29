{
  pkgs,
  ...
}:

{
  environment.pathsToLink = [ "/share/zsh" ];

  users.defaultUserShell = pkgs.zsh;
}
