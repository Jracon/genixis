{
  config,
  pkgs,
  themes,
  ...
}:

{
  programs.neovim = {
    enable = true;

    defaultEditor = true;
    # language servers and formatters; adding a language = its server here + an entry in lua/genixis/lsp.lua
    extraPackages = with pkgs; [
      fd
      lua-language-server
      nixd
      nixfmt
      ripgrep
      stylua
    ];
    initLua = ''
      vim.opt.runtimepath:prepend("${./neovim}")
      require("genixis")
    '';
    plugins = with pkgs.vimPlugins; [
      blink-cmp
      conform-nvim
      direnv-nvim # loads the project's .envrc so nvim sees its tools
      fzf-lua
      gitsigns-nvim
      nvim-lspconfig
      (nvim-treesitter.withPlugins (
        parsers: with parsers; [
          lua
          markdown
          markdown_inline
          nix
          query
          vim
          vimdoc
        ]
      ))
      (themes.lib.neovimPlugin pkgs config.genixis.palette.colors)
      which-key-nvim
      yazi-nvim
    ];
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withPython3 = false;
    withRuby = false;
  };
}
