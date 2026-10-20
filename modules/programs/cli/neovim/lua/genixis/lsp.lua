-- One entry per language server, merged over nvim-lspconfig's defaults (its lsp/<name>.lua).
-- The server binary itself comes from programs.neovim.extraPackages in neovim.nix.
local servers = {
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
}

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})
for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  vim.lsp.enable(name)
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set(
      "n",
      "gd",
      vim.lsp.buf.definition,
      { buffer = args.buf, desc = "Go to definition" }
    )
  end,
})

vim.diagnostic.config({
  float = { border = "rounded" },
  severity_sort = true,
  virtual_text = true,
})
