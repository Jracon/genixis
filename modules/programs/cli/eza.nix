{
  programs.eza = {
    enable = true;

    colors = "always";
    enableZshIntegration = true;
    icons = "always";

    extraOptions = [
      "--all"
      "--group-directories-first"
      "--header"
      "--long"
      "--modified"
      "--smart-group"
    ];
  };
}
