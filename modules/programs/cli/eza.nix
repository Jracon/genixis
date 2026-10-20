{
  programs.eza = {
    enable = true;

    colors = "auto"; # plain output when piped
    extraOptions = [
      "--all"
      "--group-directories-first"
      "--header"
      "--long"
      "--modified"
      "--smart-group"
    ];
    icons = "auto";
  };
}
