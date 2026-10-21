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
      gui.theme.activeBorderColor = [
        config.genixis.palette.colors.signatureAnsi
        "bold"
      ];
    };
  };
}
