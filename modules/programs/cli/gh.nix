{
  genixis.claude.tools.gh.description = "GitHub CLI: pull requests, issues, and API calls.";

  # manages ~/.config/gh/config.yml only; the login in hosts.yml is left alone
  programs.gh = {
    enable = true;

    settings = {
      aliases.co = "pr checkout";
      git_protocol = "https"; # pairs with the gh git credential helper this module enables
    };
  };
}
