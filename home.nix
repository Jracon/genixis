{
  config, 
  lib, 
  pkgs, 
  user, 
  ...
}:

{
  home = {
    stateVersion = "24.11";
    username = "${user.name}";

    homeDirectory = if pkgs.stdenv.isDarwin then 
                      "/Users/${user.name}"
                    else 
                      "/home/${user.name}";
  };
}
