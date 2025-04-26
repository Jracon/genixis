{
  pkgs, 
  user, 
}:

{
  home = {
    username = "${user.name}";
    homeDirectory = if pkgs.stdenv.isDarwin then 
                      "/Users/${user.name}"
                    else 
                      "/home/${user.name}";
  };
}
