# cli

The command-line programs of every platform: the shell, the editor, and the plain-word commands.

Domain: what. Reader: a session that changes a command-line program or adds one.
Code: modules/programs/cli/.

## What is the topic?

One directory holds one file per command-line tool, and the flake loads the whole directory on every platform (flake.nix:107-119). Fish is the one login shell, and nvim is the editor.

The directory holds these files:

- The shell and its surface: `fish.nix`, `starship.nix`, `tmux.nix`, `fastfetch.nix`, `keymap-table.awk`.
- The editor: `neovim.nix`, with the lua modules under `lua/genixis/`.
- One file per tool: `bat.nix`, `delta.nix`, `direnv.nix`, `eza.nix`, `gh.nix`, `git.nix`, `lazygit.nix`, `ssh-agent.nix`, `yazi.nix`, `yt-dlp.nix`.
- The cross-topic files: `ssh.nix` and `forge-known-hosts` (docs/secrets.md), `claude.nix` (docs/forge-hook.md), `project.nix` (docs/project.md), `syncthing.nix` (docs/services.md), `palette.nix` (docs/flake.md), `packages.nix`.
- The rebuild functions of fish.nix: the owner procedure lives in docs/runbook.md.

## How is the topic realized?

The plain-word commands of fish (modules/programs/cli/fish.nix). Each gate names the state that must hold:

1. `e`: open nvim. With no argument, the file picker opens (fish.nix:81-87).
2. `ide`: open the ide window of the project, and change the shell to its checkout (fish.nix:102-112).
3. `search`: the unified search. It runs rg, qmd, and semble in groups, and `--deep` switches it to a qmd query. It finds the index of the checkout by walking up, and it builds a missing index first (fish.nix:131-242).
4. `lmk`: ask one question to a standalone claude call (fish.nix:116).
5. `btw`: the tell side of the same plumbing, through the project binary (fish.nix:78).
6. `cln`: clean the Nix store with nh, keep five generations and the current one (fish.nix:79).
7. `lgs`: follow the journal of one podman unit. The gate is a podman host (fish.nix:307-309). The owner procedure lives in docs/runbook.md.
8. `tmux`: attach the session `main`, or `ssh` over a remote login, and start it when it holds no server (fish.nix:246-257).
9. `tmux-server`: on Darwin, probe the launchd tmux server and print the restart path on failure (fish.nix:273-277).
10. `clip` and `paste`: the clipboard of the tmux buffer, of pbcopy on Darwin, or of the OSC 52 escape on Linux (fish.nix:263-269, 285-305). The owner procedure lives in docs/runbook.md.
11. `agenix`: edit a secret. Inside an ide window, the editor pane opens it (fish.nix:68-74).
12. `rebuild`, `local-rebuild`, `rehome`, `local-rehome`: the rebuild paths. The owner procedure lives in docs/runbook.md (fish.nix:119-124, 311-314).
13. `fish_title`: the pane title, the working directory with the home shortened (fish.nix:91-97).

The abbreviations of fish expand at an interactive prompt only (fish.nix:318-336): `b` to yazi, `dl` to delta, `g` to zoxide, `iss` to gh issue list, `json` to jq, `l` to fd, `lg` to lazygit, `monitor` to bottom, `prc` to gh pr checkout, `prs` to gh pr list, `r` to bat. Two carry a gate: `ld` to lazydocker where the tool is installed, and `open` to xdg-open on a graphical desktop. Prefer an abbreviation to an alias, and shadow no command of the system: `history`, `help`, `diff`, `git`, `top`, and the macOS `open` stay untouched. The alias `cat` runs bat, a drop-in that keeps the name (fish.nix:407), and the directory words `ls`, `ll`, `la`, `lt` come from eza (fish.nix:406). bat and eza colour by auto only, so piped output stays plain.

The tools without their own plain-word command sit in `packages.nix`: ast-grep, bitwarden-cli, glow, nixd, nixfmt, the Reticulum tools, tailscale, and unzip (packages.nix:7-16), plus the enable-only programs bottom, fd, fzf, jq, nh, ripgrep, and zoxide (packages.nix:31-39). A bare enable with no config goes into that block, not into its own file. A tool that agents read about gets one description sentence for the machine context in the same file (packages.nix:19-28).

Fish integration turns on once, for every program, through `home.shell.enableFishIntegration` (fish.nix:60-61). Do not set the option per tool, and do not hand-wire an integration into fish.nix.

The editor (modules/programs/cli/neovim.nix, lua/genixis/):

1. nvim is the default editor, with the aliases vi, vim, and vimdiff (neovim.nix:12, 70-72). VSCodium stays installed as the fallback GUI editor of the gui set.
2. The plugins, the grammars, the servers, and the formatters come from nixpkgs, and the config is plain lua under `lua/genixis/` (neovim.nix:14-69). The generated init file prepends the store copy of the module directory to the runtime path, so a lua edit takes effect after a rebuild and an nvim restart. Never hardcode a checkout path to load a config live (neovim.nix:26-29). No plugin manager and no runtime download exists.
3. Format on save runs through conform, with stylua for lua, nixfmt for nix, and ruff format for python (lua/genixis/editing.lua:18-33). Format lua with stylua, the config of which sits beside the modules.
4. The language servers are gopls, lua_ls, nixd, and pyright, and nixd reads the option sets of this repository through its setup (lua/genixis/lsp.lua:8-60).
5. The pickers run through fzf-lua, and the file manager is yazi (lua/genixis/editing.lua:44-46, 102-103).
6. The tests run through neotest with the go adapter, and the debugger through nvim-dap with dap-go (lua/genixis/test.lua:11; lua/genixis/dap.lua:12-20).
7. To add a language: put its server or formatter into extraPackages, add the server to lsp.lua, add the formatter to editing.lua, and add the grammar to the treesitter plugins (neovim.nix:14-69).

The devShell of the flake pins the tools that edit this repository, and the committed .envrc loads it through direnv in every allowed checkout. A new worktree needs `direnv allow` only when its .envrc differs from the one in main/ (flake.nix:384-404). The devShell needs only the nixpkgs input, so a machine that this flake does not build enters it from any checkout with Nix and flakes alone.

## Why is the topic that way?

1. The repository configures no second login shell (Terminal law item 6, docs/design-philosophy.md).
2. A plain-word command is gated on its tool being present, not on the platform, so the same fish config runs on every host (fish.nix:13-15).
3. An abbreviation expands only at an interactive prompt, so a session that reads the command sees the real tool (fish.nix:318).
4. nh runs the rebuilds, because it shows a package diff before the switch and elevates with sudo itself (fish.nix:23-24).
5. The rebuild functions carry the mirror fallback of the forge, with the reason in the code comment (fish.nix:40-46). The procedure lives in docs/runbook.md.

## What does the topic enable?

The end of the topic: short plain words cover the daily work at a terminal, on every host this flake builds, and the same editor answers with the same keys. Terminal law item 1 of docs/design-philosophy.md states the criterion of the terminal interface.

## How does a reader use and change the topic?

Add a tool:

1. Write one file under `modules/programs/cli/`, or enable the program in `packages.nix`.
2. Add the description of the tool for the machine context, when agents read about it (packages.nix:19-28).
3. Run `nix fmt`, then `nix flake check --impure`.

Add a plain-word command: write the fish function with its gate in fish.nix, and keep the name a plain word.

Add an abbreviation: add it to the shellAbbrs list, and keep the expansion a real tool.

Probe a lua change of the editor: put a probe script under `.scratch/` of the worktree and run `nvim --headless -c 'lua dofile(".scratch/probe.lua")' -c 'qa!'`. Inside the probe, prepend the module directory of the worktree to the runtime path, clear the `genixis` modules from `package.loaded`, and require `genixis` again. The script is throwaway, and no shipped config gains a checkout path. A change of `package.path` alone loads the store copy of the module directory. The runtime-path searcher runs before `package.path`, and the init file already prepends the store copy (neovim.nix:26-29).
