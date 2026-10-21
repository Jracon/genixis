{
  config,
  pkgs,
  ...
}:

let
  # when this checkout exists, nvim loads its Lua straight from it, so edits apply on restart
  # without a rebuild; everywhere else (servers, fresh machines) it uses the copy in the Nix store
  checkout = "${config.home.homeDirectory}/projects/genixis/modules/programs/cli/neovim";
in
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
      local checkout = "${checkout}"
      vim.opt.runtimepath:prepend(vim.uv.fs_stat(checkout) and checkout or "${./neovim}")
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
      tokyonight-nvim
      vim-tmux-navigator
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
