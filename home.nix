{
  config, 
  lib, 
  pkgs, 
  user, 
  ...
}:

{
  home = {
    stateVersion = "25.05";
    username = "${user.name}";

    homeDirectory = if pkgs.stdenv.isDarwin then 
                      "/Users/${user.name}"
                    else 
                      "/home/${user.name}";
  };
}
