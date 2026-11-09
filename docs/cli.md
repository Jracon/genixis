# The CLI programs

The per-tool rules of `modules/programs/cli/`: fish and its functions, neovim, the plain-word commands, the aliases, and the editor.

## `modules/programs/cli/`

The shell is **fish**, not zsh. `zsh.nix` no longer exists. Do not reintroduce it.

Each tool has one file. A bare `enable = true` with no extra config goes in the `programs` block of the `packages.nix` in that directory, not in its own file. Use `cli/packages.nix` for every platform and `nixos/packages.nix` for NixOS only.

Fish integration is on once, through `home.shell.enableFishIntegration = true` in `fish.nix`. This is the default for the `enableFishIntegration` option of every program. Do not set it per tool. Do not hand-wire integrations into `fish.nix`.

The `project` binary and the `ide` window are in docs/project.md. The Claude Code context and the forge hook are in docs/forge-hook.md. The tmux server on Darwin is in docs/tmux-darwin.md.

### Neovim

Files: `neovim.nix` and `neovim/lua/genixis/`.

- Plugins, Tree-sitter grammars, language servers, and formatters come from nixpkgs (`plugins` and `extraPackages`). The config is plain Lua in `neovim/`.
- The generated `init.lua` prepends the store copy of `neovim/` to the runtimepath. Lua edits take effect after a rebuild and an nvim restart. Never hardcode a checkout path to load the config live.
- The colourscheme comes from the `themes` flake (see Colour palette in docs/flake.md), not tokyonight.
- There is no Mason and no lazy.nvim. Nothing downloads at runtime.
- `flake.nix` pins the tools that edit this repository in `devShells.<system>.default`. The committed `.envrc` loads the devShell through direnv in every allowed checkout. A new worktree needs `direnv allow` only when its `.envrc` differs from the one in `main/`. `nix develop` enters the devShell without direnv. The devShell needs only the nixpkgs input of this flake, and the lock file pins that input. A machine that this flake does not build can enter the devShell from any checkout. That machine needs only Nix with the flakes feature. The global installs in `extraPackages` serve files outside a project. Pin the tools of each project in the devShell of its own flake.
- Format Lua with `stylua`. The config is in `neovim/.stylua.toml`.
- To add a language:
  1. Add its server or formatter to `extraPackages`.
  2. Add a `servers` entry in `lsp.lua`.
  3. Add a `formatters_by_ft` entry in `editing.lua`.
  4. Add its grammar to `nvim-treesitter.withPlugins`.
- `nixd` gets option completion for this repository (Darwin, Home Manager, NixOS `media`) through `before_init` in `lsp.lua`.

### Fish custom functions

`fish.nix` defines these functions through `programs.fish.functions`. All of them wrap [nh](https://github.com/nix-community/nh). nh shows a package diff before it switches. It elevates with sudo by itself.

| Function                                      | Action                                                                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `rebuild <host>` / `local-rebuild <host>`     | `nh os switch --impure` / `nh darwin switch --impure` (includes Home Manager), from Forgejo (GitHub mirror if unreachable) / from local `.`  |
| `rehome <user>` / `local-rehome <user>`       | `nh home switch --impure`, remote / local — only defined in standalone configs (`!config.submoduleSupport.enable`)              |

`rebuild` and `rehome` pass `--refresh`. Without it, Nix uses the commit that it found for the branch during the last hour (`tarball-ttl`). A rebuild directly after a push then builds an older commit. If the refresh fails, Nix prints a warning and uses the cached commit.

`nh os` refuses to run as root. So the NixOS functions pass `--elevation-strategy none` when `fish_is_root_user` is true. The servers log in as root.

Nix refuses a git checkout that another user owns. For example, root cannot build from the checkout of `dev` on `services`. So `local-rebuild` reads the checkout as `path:$PWD` when the current user does not own the current directory. A `path:` flake also includes untracked files. Run `local-rebuild` from the root of the checkout in this case.

`nix.gc` in `base.nix` already handles garbage collection. Do not also enable `programs.nh.clean`.

### Plain-word commands

These are in `fish.nix`. Fish abbreviations (`shellAbbrs`) expand to the real command as you type:

- `b` → `y` (yazi), `dl` → `delta`, `g` → `z`, `json` → `jq`, `lg` → `lazygit`, `l` → `fd`, `monitor` → `btm`, `r` → `bat`
- `iss` → `gh issue list`, `prs` → `gh pr list`, `prc` → `gh pr checkout`

Six functions also exist:

- `e` runs `nvim`, or its file picker when you give no arguments.
- `cln` runs `nh clean all --keep 5 --keep-one`. The `--keep-one` flag keeps one GC root for each direnv project.
- `lmk <question...>` asks one quick documentation question through `project lmk`: one standalone claude call in the current checkout answers it on the terminal, with no pane and no live session. Piped stdin is the context of the question (see docs/project.md).
- `btw <fact...>` sends the fact to the claude pane of the current checkout, through `project btw`. With no pane, the fact lands in the shared project memory of the checkout (see docs/project.md).
- `search <query...>` runs the unified search of issue #189. It refreshes the qmd index of the tree (a `.qmd/index.yml` must exist), then fans out grouped over `rg`, `qmd search` (BM25, no models), and `semble search --content all`, each section truncated. The scores of the three tools are not comparable, so the results stay grouped, never fused. A section that finds nothing says so, and a missing tool or a missing qmd index shows in its section, so no empty index fails silently again. `search --deep <question>` runs `qmd query` with the models, the deep tier for when the fast tier finds nothing; the wrapper says so itself when every section came back empty. The abbreviation `search → rg` is gone: the wrapper replaces it at the prompt, and agents keep the routing of the search skill, which `rg` still serves directly.
- `clip` puts the text that a pipe sends on the clipboard. Inside tmux, `clip` runs `tmux load-buffer -w -`. The `-w` flag also sends the text to the terminal with OSC 52. Through a session tab, the text lands on the clipboard of the Mac that shows the window. On Darwin outside tmux, `clip` runs `pbcopy`. On Linux outside tmux, `clip` writes the OSC 52 sequence itself. It writes the sequence only when stdout is a terminal. When stdout is not a terminal, `clip` fails.
- `paste` writes the clipboard to stdout. On Darwin, `paste` runs `pbpaste`. `pbpaste` sees the text that OSC 52 wrote and the text that Cmd+C copied. On Linux, `paste` reads the tmux paste buffer only. Outside tmux, `paste` fails. The reason: WezTerm answers no OSC 52 read query. `paste` shadows the coreutils command of the same name. `command paste` reaches the tool.

Fish also calls `fish_title` for the pane title. The function pushes the working directory of the shell, so the home tab of a host window shows where its shell works (see the host window in docs/project.md).

Some commands are on only when the tool exists. The check uses `osConfig` (null in standalone), not the platform:

- `ld` → `lazydocker` (`programs.lazydocker.enable`).
- `lgs <svc>` → `journalctl -fu podman-<svc>` (Podman hosts).
- `open` → `xdg-open` (Linux with `services.graphical-desktop.enable`).

Prefer abbreviations to aliases. Do not shadow `history`, `help`, `diff`, `git`, `top`, or the macOS `open`.

### Aliases, tmux, and editor

- Aliases are for drop-in replacements that keep the familiar name: `cat→bat`. The `ls`, `ll`, `la`, `lt`, and `lla` aliases come from the integration of `programs.eza`.
- bat and eza use auto colour and icons, so piped output stays plain. Never set them to `always`.
- `tmux` is a function. Bare `tmux` runs `tmux new -As main`. When `SSH_CONNECTION` is set, it runs `ssh` instead, so an ssh login does not join the session of the local terminal. Any other call passes through.
- `EDITOR` is `nvim` everywhere (`programs.neovim.defaultEditor`). VSCodium stays installed as a fallback GUI editor.
- On NixOS, fish attaches on login by running bare `tmux`. Darwin skips this. A shell that holds `PROJECT_HOME_TAB` also skips this. The home tab of a remote login sets the variable, and the shell after a detach in a session tab sets it too (see the host window in docs/project.md).
- The fish keys sit in the Tool layer of the keymap: the Shift+arrows move by word at the prompt, and, under tmux, fish binds Ctrl+D to `delete-char`.
- Ctrl+D never exits the shell under tmux. Use `exit`. The reason: WezTerm types Enter and Ctrl+D into a pane that it closes (Cmd+Q), and the tmux client forwards them to the focused pane.

## NOTES

- The editor is VSCodium, not VSCode, because of unfree and license issues. `jeanp413.open-remote-ssh` (from the `nix-vscode-extensions` Open VSX set) replaces `ms-vscode-remote.remote-ssh`, which Microsoft locks.
