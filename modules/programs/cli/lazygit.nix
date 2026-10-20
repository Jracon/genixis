{
  programs.lazygit = {
    enable = true;

    # lazygit >= 0.66 calls these diffRenderers (formerly paging/pagers)
    settings.git.diffRenderers = [
      {
        command = "delta --{{colorScheme}} --paging=never";
      }
    ];
  };
}
