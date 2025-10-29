{
  pkgs,
  user,
  ...
}:

{
  home = {
    homeDirectory =
      if pkgs.stdenv.isDarwin then
        "/Users/${user.name}"
      else if user.name == "root" then
        "/root"
      else
        "/home/${user.name}";
    stateVersion = "25.05";
    username = "${user.name}";
  };
}
