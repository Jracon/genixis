{
    ...
}:

{
  programs.eza = {
    eza = {
      enable = true;
      icons = "auto";
      colors = "auto";
      git = true;

      extraOptions = [
        "--group-directories-first"
        "--group"
        "--all"
      ];
    };
  };
}
