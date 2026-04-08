{
  programs.eza = {
    enable = true;

    colors = "always";
    enableFishIntegration = true;
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
