{
  programs.git = {
    enable = true;

    settings = {
      fetch.prune = true;
      init.defaultBranch = "main";
      pull.ff = "only";
      user = {
        email = "32557834+Jracon@users.noreply.github.com";
        name = "Jade Isaiah Meskill";
      };
    };
  };
}
