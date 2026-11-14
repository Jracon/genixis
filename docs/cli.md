# cli

Command-line programs of every platform: the shell, the editor, the plain-word commands, and the tmux server of Darwin.

## One File per Tool

One directory holds one file per command-line tool, and the flake loads the whole directory on every platform (flake.nix, homeModules). Fish is the one login shell, and nvim is the editor.

Directory holds these files:

- Shell and its surface: `fish.nix`, `starship.nix`, `tmux.nix`, `fastfetch.nix`.
- Editor: `neovim.nix`, with the lua modules under `lua/genixis/`.
- One file per tool: `bat.nix`, `delta.nix`, `direnv.nix`, `eza.nix`, `gh.nix`, `git.nix`, `lazygit.nix`, `ssh-agent.nix`, `yazi.nix`, `yt-dlp.nix`.
- Cross-topic files: `ssh.nix` and `forge-known-hosts` (docs/secrets.md), `claude.nix` (docs/forge-hook.md), `project.nix` (docs/project.md), `syncthing.nix` (docs/services.md), `palette.nix` (docs/flake.md), `packages.nix`.
- The one list of the terminal bindings sits in lib/keymap.nix, and `tmux.nix`, `fish.nix`, and `wezterm.nix` derive their bind lines from its rows (docs/keymap.md).
- Rebuild functions of fish.nix: the owner procedure lives in docs/runbook.md.

## Plain-Word Commands

Plain-word commands of fish (modules/programs/cli/fish.nix). Each gate names the state that must hold:

1. `e`: open nvim. With no argument, the file picker opens.
2. `ide`: open the ide window of the project, and change the shell to its checkout.
3. `search`: the unified search. It runs rg, qmd, and semble in groups, and `--deep` switches it to a qmd query. It finds the index of the checkout by walking up, and it builds a missing index first.
4. `lmk`: ask one question to a standalone claude call.
5. `btw`: the tell side of the same plumbing, through the project binary.
6. `cln`: clean the Nix store with nh, keep five generations and the current one.
7. `lgs`: follow the journal of one podman unit. Its gate is a podman host. Owner procedure lives in docs/runbook.md.
8. `tmux`: attach the session `main`, or `ssh` over a remote login, and start it when it holds no server.
9. `tmux-server`: on Darwin, probe the launchd tmux server and print the restart path on failure.
10. `clip` and `paste`: the clipboard of the tmux buffer, of pbcopy on Darwin, or of the OSC 52 escape on Linux. Owner procedure lives in docs/runbook.md.
11. `agenix`: edit a secret. Inside an ide window, the editor pane opens it.
12. `rebuild`, `local-rebuild`, `rehome`, `local-rehome`: the rebuild paths. Owner procedure lives in docs/runbook.md.
13. `fish_title`: the pane title, the working directory with the home shortened.

Fish integration turns on once, for every program, through `home.shell.enableFishIntegration` (fish.nix). Do not set the option per tool, and do not hand-wire an integration into fish.nix.

## Abbreviations and Aliases

Abbreviations of fish expand at an interactive prompt only (fish.nix, shellAbbrs): `b` to yazi, `dl` to delta, `g` to zoxide, `iss` to gh issue list, `json` to jq, `l` to fd, `lg` to lazygit, `monitor` to bottom, `prc` to gh pr checkout, `prs` to gh pr list, `r` to bat. Two carry a gate: `ld` to lazydocker where the tool is installed, and `open` to xdg-open on a graphical desktop. Prefer an abbreviation to an alias, and shadow no command of the system: `history`, `help`, `diff`, `git`, `top`, and the macOS `open` stay untouched. Alias `cat` runs bat, a drop-in that keeps the name, and the directory words `ls`, `ll`, `la`, `lt` come from eza. bat and eza colour by auto only, so piped output stays plain.

## Packages Without a Command

Tools without their own plain-word command sit in `packages.nix`: ast-grep, bitwarden-cli, glow, nixd, nixfmt, the Reticulum tools, tailscale, and unzip, plus the enable-only programs bottom, fd, fzf, jq, nh, ripgrep, and zoxide. A bare enable with no config goes into that block, not into its own file. A tool that agents read about gets one description sentence for the machine context in the same file.

## Editor

Editor rules, at their realization in modules/programs/cli/neovim.nix and the lua modules under `lua/genixis/`:

1. nvim is the default editor, with the aliases vi, vim, and vimdiff. VSCodium stays installed as the fallback GUI editor of the gui set.
2. Plugins, grammars, servers, and formatters come from nixpkgs, and the config is plain lua under `lua/genixis/`. A generated init file prepends the store copy of the module directory to the runtime path, so a lua edit takes effect after a rebuild and an nvim restart. Never hardcode a checkout path to load a config live. No plugin manager and no runtime download exists.
3. Format on save runs through conform, with stylua for lua, nixfmt for nix, and ruff format for python (editing.lua). Format lua with stylua, the config of which sits beside the modules.
4. Language servers are gopls, lua_ls, nixd, and pyright, and nixd reads the option sets of this repository through its setup (lsp.lua).
5. Pickers run through fzf-lua, and the file manager is yazi (editing.lua).
6. Tests run through neotest with the go adapter, and the debugger through nvim-dap with dap-go (test.lua; dap.lua).
7. To add a language: put its server or formatter into extraPackages, add the server to lsp.lua, add the formatter to editing.lua, and add the grammar to the treesitter plugins.

## DevShell

DevShell of the flake pins the tools that edit this repository, and the committed .envrc loads it through direnv in every allowed checkout. A new worktree needs `direnv allow` only when its .envrc differs from the one in main/ (flake.nix, devShells). Each devShell needs only the nixpkgs input, so a machine that this flake does not build enters it from any checkout with Nix and flakes alone.

## Tmux Server on Darwin

On Darwin, launchd owns the tmux server, and a client never starts one: the fish function `tmux` and each activation hook run with `-N`, which makes a client fail when no server answers (fish.nix; tmux.nix). One server runs on the Mac, up from login, reachable from every process chain, with no second server and no split socket.

Agent rules, at their realization in modules/programs/cli/tmux.nix:

1. Program runs `tmux -D`, the foreground server, with the fish of the profile as the default shell.
2. `KeepAlive` and `RunAtLoad` keep the server up from login. `ProcessType` is Interactive.
3. Soft limit of open files rises to 61440.
4. Environment names the locale, an explicit path, and the log file `~/Library/Logs/tmux-server.log`.

Guards:

1. Fish function `tmux` attaches with `-N` after it probes the server, and the probe prints the restart path on failure: `launchctl kickstart gui/<uid>/<label>`, and the log file.
2. An activation hook of a switch re-sources the configuration with `tmux -N source-file -q`, and a failure costs nothing. A re-source adds and replaces bindings; a binding that the new configuration removed stays until the next server restart, because a restart ends every pane. A configuration therefore writes full sets for `terminal-features` and `update-environment` (issue 191).
3. A popup starts in the working directory of the tmux server, not of the caller. Every popup command carries `-d` with the working directory of the pane.
4. A script that calls the tmux executable skips the fish function, so on Darwin no script runs `tmux new-session` unless a server runs. A test or probe server needs its own socket: pass `-L` with a name on every command of that server. A shell inside tmux exports `TMUX`, and tmux prefers the socket of that variable, so a `kill-server` that aims at a temporary directory can end the server of the user.
5. When another server holds the socket, `tmux -D` exits with an error and launchd tries again every ten seconds. One `tmux kill-server` ends the loop.

Local Network grant:

1. A server that a WezTerm starts loses the LAN when that WezTerm quits, because the macOS Local Network grant follows the process chain of the server. A launchd server keeps the grant.
2. Its grant also follows the code signature, which changes at each Nix build, so no fix inside this repository holds it for every chain (workaround record in docs/runbook.md).
3. An activation hook reaches only the socket that the switch environment resolves. A switch from a context without `TMUX_TMPDIR` silently misses the server (the review of pull request 238, verified on services).

Attach with the fish function `tmux`. Never run bare `tmux` by hand on Darwin: without `-N` it starts a second server. When no server answers, run `launchctl kickstart gui/<uid>/<label>` with the label of the agent, then read `~/Library/Logs/tmux-server.log`. Change the server settings: edit the agent block in modules/programs/cli/tmux.nix, and rebuild the machine.

## Terminal Law

Terminal Law of this topic, at its application (docs/design.md holds the map):

1. Text is the interface. No desktop app or voice surface is added while a text surface answers.
2. One login shell. Fish is the login shell, and this repository configures no second.

Decisions behind the commands:

3. A plain-word command is gated on its tool being present, not on the platform, so the same fish config runs on every host (fish.nix). A platform gate lost, because the gate on the tool serves every host. Reopens: none named.
4. An abbreviation expands only at an interactive prompt, so a session that reads the command sees the real tool. An alias lost, because it hides the real tool from a session. Reopens: none named.
5. nh runs the rebuilds, because it shows a package diff before the switch and elevates with sudo itself (fish.nix). A plain rebuild command lost, because it shows no diff and elevates by hand. Reopens: none named.
6. Rebuild functions carry the mirror fallback of the forge, with the reason in the code comment (fish.nix). Procedure and workaround record live in docs/runbook.md.
7. Two workaround records cover the rebuild path. Workaround record, the path-flake read of local-rebuild. Context: Nix refuses a checkout that another user owns, so root cannot build from the checkout of dev. Decision: local-rebuild reads the checkout as a path flake when the current user does not own it. The audit verified the trade: an ignored directory of the worktree enters no store copy, so the read changes no result (the probe that closed entry 12 of issue 218). Options that lost: a per-user checkout, because the ownership rule of git stands. Consequences: the rebuild needs no second checkout. Status: keep as a stated design. Reopen trigger: git lifts the ownership refusal, or Nix gains a per-user build. Workaround record, the elevation strategy of a root rebuild. Context: the owner runs a rebuild as root. Decision: the root rebuild sets the elevation strategy to none, because root needs no elevation. Options that lost: none on record. Consequences: the root rebuild elevates once, inside nh. Status: deferred. Cause: no verdict says whether the setting is a standing pattern. Trigger and end: the owner takes the verdict, and the ruling lands in this record.

## Purpose of the Commands

Purpose of the topic: short plain words cover the daily work at a terminal, on every host this flake builds, and the same editor answers with the same keys. Why item 1 of this file states the criterion.

## Add and Probe

Add a tool:

1. Write one file under `modules/programs/cli/`, or enable the program in `packages.nix`.
2. Add the description of the tool for the machine context, when agents read about it (packages.nix).
3. Run `nix fmt`, then `nix flake check --impure`.

Add a plain-word command: write the fish function with its gate in fish.nix, and keep the name a plain word.

Add an abbreviation: add it to the shellAbbrs list, and keep the expansion a real tool.

Probe a lua change of the editor: put a probe script under `.scratch/` of the worktree and run `nvim --headless -c 'lua dofile(".scratch/probe.lua")' -c 'qa!'`. Inside the probe, prepend the module directory of the worktree to the runtime path, clear the `genixis` modules from `package.loaded`, and require `genixis` again. Each script is throwaway, and no shipped config gains a checkout path. A change of `package.path` alone loads the store copy of the module directory. A runtime-path searcher runs before `package.path`, and the init file already prepends the store copy.
