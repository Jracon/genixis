{
  config,
  ...
}:

{
  programs.lazygit = {
    enable = true;

    settings = {
      # lazygit >= 0.66 calls these diffRenderers (formerly paging/pagers)
      git.diffRenderers = [
        {
          command = "delta --{{colorScheme}} --paging=never";
        }
      ];
      gui = {
        # the branches view shows how far each branch sits from the base branch, which the
        # review diff flow of nvim reads (issue #181); the base follows git.mainBranches
        showDivergenceFromBaseBranch = "arrowAndNumber";
        theme.activeBorderColor = [
          config.genixis.palette.colors.signatureAnsi
          "bold"
        ];
      };
    };
  };
}
