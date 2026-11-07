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
      delve # the debugger behind nvim-dap-go, so a Go file debugs from any checkout
      fd
      gopls
      lua-language-server
      nixd
      nixfmt
      pyright
      ripgrep
      ruff
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
      FixCursorHold-nvim # recommended by neotest, for its cursorhold-based watching
      friendly-snippets # the snippet set that luasnip loads per filetype
      fzf-lua
      gitsigns-nvim
      grug-far-nvim # project-wide find and replace, with every match previewed before the write
      luasnip # expands snippets; blink.cmp routes expansion through it
      neo-tree-nvim # the file tree in the left split of the editor pane (issue #196); its nui.nvim dependency rides along on the runtime path
      neotest # runs the test under the cursor
      neotest-golang # the Go adapter of neotest; go itself comes from the devShell
      nvim-autopairs
      nvim-dap # the debug adapter client: breakpoints, stepping, the REPL
      nvim-dap-go # wires Go to delve; the binary comes from extraPackages and the devShell
      nvim-dap-ui # the debug views: variables, call stack, REPL, around the debugged buffer
      nvim-lspconfig
      nvim-nio # async library of neotest
      nvim-treesitter-context # pins the enclosing function signature at the top of the view
      nvim-treesitter-textobjects # syntax-aware text objects: functions, arguments, classes
      (nvim-treesitter.withPlugins (
        parsers: with parsers; [
          go
          lua
          markdown
          markdown_inline
          nix
          python
          query
          vim
          vimdoc
        ]
      ))
      (themes.lib.neovimPlugin pkgs config.genixis.palette.colors)
      plenary-nvim # dependency of neotest
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
