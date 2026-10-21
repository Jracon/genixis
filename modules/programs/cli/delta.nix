{
  programs.delta = {
    enable = true;

    enableGitIntegration = true;
    options = {
      line-numbers = true;
      navigate = true; # n/N jump between files
      syntax-theme = "ansi"; # the 16 terminal colours, so it follows the WezTerm scheme
    };
  };
}
