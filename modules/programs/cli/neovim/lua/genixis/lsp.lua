-- One entry per language server, merged over nvim-lspconfig's defaults (its lsp/<name>.lua).
-- The server binary itself comes from programs.neovim.extraPackages in neovim.nix.
local servers = {
  gopls = {},

  lua_ls = {
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        workspace = {
          checkThirdParty = false,
          library = { vim.env.VIMRUNTIME },
        },
      },
    },
  },

  nixd = {
    -- point nixd at the flake being edited, for nixpkgs/option completion
    before_init = function(_, config)
      local root = config.root_dir
      if not root or not vim.uv.fs_stat(root .. "/flake.nix") then
        return
      end
      local flake = '(builtins.getFlake "git+file://' .. root .. '")'
      local nixd = config.settings.nixd
      nixd.nixpkgs = { expr = "import " .. flake .. ".inputs.nixpkgs { }" }
      if vim.uv.fs_stat(root .. "/common/base.nix") then -- this repo (genixis)
        local darwin = flake .. ".darwinConfigurations.m2pro-mbp.options"
        nixd.options = {
          darwin = { expr = darwin },
          ["home-manager"] = { expr = darwin .. ".home-manager.users.type.getSubOptions [ ]" },
          nixos = { expr = flake .. ".nixosConfigurations.media.options" },
        }
      end
    end,
    settings = {
      nixd = {
        formatting = { command = { "nixfmt" } },
      },
    },
  },

  pyright = {},
}

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})
for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  vim.lsp.enable(name)
end

-- the fzf-lua pickers of the LSP maps (issue #165): one chord lists the references of the
-- symbol under the cursor, gD its definitions. Both keys sit in the Tool layer, and the
-- built-in maps stay: grr keeps the quickfix of references and gd the direct jump. gD
-- shadows the nvim default that jumps to the declaration; gopls and lua_ls report the
-- declaration of a Go or Lua symbol as its definition, so nothing is lost
local fzf = require("fzf-lua")
local map = vim.keymap.set
map("n", "<S-F12>", fzf.lsp_references, { desc = "References (picker)" })
map("n", "gD", fzf.lsp_definitions, { desc = "Definitions (picker)" })

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set(
      "n",
      "gd",
      vim.lsp.buf.definition,
      { buffer = args.buf, desc = "Go to definition" }
    )
    -- Ctrl+click jumps like gd (issue #165): Ctrl operates the tool in the pane, and tmux
    -- forwards a click with its modifier to a pane whose program asked for mouse events
    -- (options.lua sets mouse=a). The map replaces the nvim default that jumps to the tag
    -- under the click
    vim.keymap.set(
      "n",
      "<C-LeftMouse>",
      "<LeftMouse><cmd>lua vim.lsp.buf.definition()<CR>",
      { buffer = args.buf, desc = "Go to definition" }
    )
  end,
})

-- one key turns inlay hints on and off, in every buffer at once; they stay off until then
vim.keymap.set("n", "<leader>th", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = "Inlay hints" })

vim.diagnostic.config({
  float = { border = "rounded" },
  severity_sort = true,
  virtual_text = true,
})
