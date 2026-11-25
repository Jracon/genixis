# cli

Command-line programs of every platform: the shell, the editor, the plain-word commands, and the tmux server of Darwin.

## One File per Tool

One directory holds one file per command-line tool, and the flake loads the whole directory on every platform (flake.nix, homeModules). Fish is the one login shell, and nvim is the editor.

Directory holds these files:

- Shell and its surface: `fish.nix`, `starship.nix`, `tmux.nix`, `fastfetch.nix`.
- Editor: `neovim.nix`, with the lua modules under `lua/genixis/`.
- One file per tool: `bat.nix`, `delta.nix`, `direnv.nix`, `eza.nix`, `gh.nix`, `git.nix`, `lazygit.nix`, `ssh-agent.nix`, `yazi.nix`, `yt-dlp.nix`.
- Cross-topic files: `ssh.nix` and `forge-known-hosts` (docs/secrets.md), `claude.nix` (docs/agent-context.md), `project.nix` (docs/project.md), `syncthing.nix` (docs/services.md), `palette.nix` (docs/flake.md), `packages.nix`.
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

Tools without their own plain-word command sit in `packages.nix`: ast-grep, bitwarden-cli, glow, mkdocs, nixd, nixfmt, the Reticulum tools, tailscale, and unzip, plus the enable-only programs bottom, fd, fzf, jq, nh, ripgrep, and zoxide. A bare enable with no config goes into that block, not into its own file. A tool that agents read about gets one description sentence for the machine context in the same file.

## Local Markdown Viewer

mkdocs-material renders markdown in a browser page. It draws Mermaid diagrams, its search field filters the pages, and each edit of a served file reloads its page. The tool sits in `packages.nix`. This repository tracks one `mkdocs.yml` at its root, and its `docs_dir` names `docs/`, so `mkdocs serve` from a checkout serves the docs tree on localhost. The file holds no `nav`, because mkdocs builds the `nav` from the directory tree. A new page needs no edit of the file.

Any other directory serves the same way: give it one `mkdocs.yml` with `docs_dir` set to that directory, and run `mkdocs serve` there. The tracked tree holds no diagram source: the register rejects it, and plain reads stay first-class (docs/decisions.md, rejected list).

## Editor

Editor rules, at their realization in modules/programs/cli/neovim.nix and the lua modules under `lua/genixis/`:

1. nvim is the default editor, with the aliases vi, vim, and vimdiff. VSCodium stays installed as the fallback GUI editor of the gui set.
2. Plugins, grammars, servers, and formatters come from nixpkgs, and the config is plain lua under `lua/genixis/`. A generated init file prepends the store copy of the module directory to the runtime path, so a lua edit takes effect after a rebuild and an nvim restart. Never hardcode a checkout path to load a config live. No plugin manager and no runtime download exists.
3. Format on save runs through conform, with stylua for lua, nixfmt for nix, and ruff format for python (editing.lua). Format lua with stylua, the config of which sits beside the modules.
4. Language servers are basedpyright, gopls, lua_ls, and nixd, and nixd reads the option sets of this repository through its setup (lsp.lua). The python type checker of the editor and the python type gate of the repository are one tool: basedpyright (docs/ci.md).
5. Pickers run through fzf-lua, and the file manager is yazi (editing.lua).
6. Tests run through neotest with the go adapter, and the debugger through nvim-dap with dap-go (test.lua; dap.lua).
7. To add a language: put its server or formatter into extraPackages, add the server to lsp.lua, add the formatter to editing.lua, and add the grammar to the treesitter plugins.

### VSCodium profiles

modules/programs/gui/vscodium.nix declares seven VSCodium profiles:

1. `default` holds the shared extensions and settings: Claude Code, direnv, vscode-icons, Open Remote SSH, and EditorConfig.
2. `nix` adds the Nix IDE extension, set to use nixd.
3. `go` adds the Go extension.
4. `python` adds basedpyright and ruff. Ruff formats python on save. The python settings sit in modules/programs/gui/vscodium/python.json.
5. `lua` adds lua language server and StyLua.
6. `shell` adds ShellCheck and shfmt.
7. `genixis` holds the union of the five language profiles, plus Prettier and Caddyfile support.

A profile of VSCodium does not inherit extensions or settings from `default`. Home Manager writes one settings.json and one extensions.json for each profile (mkVscodeModule.nix of Home Manager, `profileDir`). The Nix file therefore prepends the shared extensions and settings to each profile, so each extension and each shared setting is written once. The update checks are set on `default` only, and they apply to all profiles.

A folder gets its profile in the editor UI, outside Nix. Open the folder, choose Profiles in the Manage menu (the gear), choose the profile, and select Switch. Open the folder under that profile once, and VSCodium opens it under that profile again. A sub-tree, for example modules/services/dispatcher/, can open under `python` alone, and the genixis checkout opens under `genixis`.

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
8. Workaround record, the zero-typing ssh extension of the desktop. Context: issue 62 and pull request 73 left an optional extension for the desktop: ksshaskpass as the askpass, plus one ssh-add at login. The extension sits on top of the per-user agent of ssh-agent.nix. With it, the owner types no passphrase after boot. Both entities kept the extension as future work. No record held the deferral. Decision: the extension stays future work, on this record. ssh asks the passphrase on the desktop once per boot, at the first use of the key (`AddKeysToAgent` in ssh.nix). The Mac holds the zero-typing path through its Keychain (docs/runbook.md). Options that lost: the build of the extension with issue 73, because the landed design already gives the goal of issue 62, one passphrase per boot. The rejection, because the ruling of the owner took the deferral (issue 376). Consequences: the repository holds no part of the extension. The deferral sits on this record. The gap of the Workaround Discipline closed (docs/design.md). Status: deferred. Cause: of the six alternatives of issue 62, the extension needs the most parts in working order. The parts are the agent, the askpass, the wallet PAM, and one ssh-add at login. The exact NixOS options are unverified. The system half sits in the machine-local configuration of the desktop, outside this repository. Trigger: the owner asks for zero typing on desktop. End: an issue that carries the build opens, or the ruling turns to rejection.
9. Workaround record, the per-user ssh agent. Context: issue 62 asked for one passphrase per boot, and its investigation comment of 2026-11-02 compared six alternatives. Pull request 73 landed the design in modules/programs/cli/ssh-agent.nix and modules/programs/cli/ssh.nix. A note of the old docs/secrets.md carried the design until the docs rebuild dropped it, and issue 431 tracks the loss. Decision: a systemd user service starts one agent per user at login, on every platform except Darwin. The AddKeysToAgent setting in ssh.nix makes ssh load the key into the agent at the first use of the key, so the passphrase is typed once per login session. The service stays off on Darwin, because launchd there already runs one agent for every login session, and a second agent would split the environment in two. Options that lost: keychain, the proposal of issue 62, because it prompts during the first interactive shell after boot, it overrides a forwarded agent, and it starts a second agent next to the agent of macOS. The launchd half of the same module on Darwin, because it duplicates the agent that macOS already runs, so the environment splits between fish panes and GUI processes. The sshAuthSock export of fish alone, because it exports a socket and starts no agent, so it is a component of the landed design and no fix on its own. Gnome-keyring on the desktop, because it is desktop only, it puts a second credential store and a GTK prompt stack on a Plasma desktop that runs KWallet, and it conflicts with programs.ssh.startAgent. KWallet with ksshaskpass on the desktop, because it needs the most pieces in working order, and the deferral of that extension lives in item 8 of this file. Consequences: every Linux home gets the agent from login, and no work runs during shell startup. The socket export keeps a forwarded agent. The Mac goes from one ask per ssh run to one per boot. On the servers, no session bus runs, so the helper unit that pushes the socket into the D-Bus activation environment fails after login, and the failure is cosmetic. On wsl, a home without a systemd user manager exports a socket that no process serves, and pull request 73 kept it unverified whether ssh then decrypts the key per run. Status: keep as a stated design. Reopen trigger: macOS stops running one agent per login session through launchd, or the owner asks for one agent shape on every platform.

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
