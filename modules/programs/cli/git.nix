{
  config,
  ...
}:

{
  programs.git = {
    enable = true;

    settings = {
      # the global ignore file below; git would read this path by default, the setting keeps the link visible
      core.excludesFile = "${config.xdg.configHome}/git/ignore";
      fetch.prune = true;
      init.defaultBranch = "main";
      pull.ff = "only";
      user = {
        email = "32557834+Jracon@users.noreply.github.com";
        name = "Jade Isaiah Meskill";
      };
    };
  };

  # .scratch/ is the throwaway directory of every worktree (see AGENTS.md, "Projects"); git must never
  # track or show it, so the name sits in the global ignore file, not in .git/info/exclude of each clone
  xdg.configFile."git/ignore".text = ''
    .scratch/
  '';
}
