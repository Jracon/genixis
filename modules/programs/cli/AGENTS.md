# programs/cli/ — CLI Tool Modules

One `.nix` file per tool. All files loaded for every platform (NixOS + Darwin + Home Manager) via `generateConfigModules { programs = ["cli"]; }`.

## FILES

| File | Tool | Notes |
|------|------|-------|
| `bat.nix` | bat (cat replacement) | aliased as `cat` in zsh |
| `eza.nix` | eza (ls replacement) | aliased as `ls` in zsh |
| `git.nix` | git | global config |
| `neovim.nix` | neovim | editor config |
| `packages.nix` | misc CLI packages | catch-all for tools without own file |
| `starship.nix` | starship prompt | |
| `tmux.nix` | tmux | auto-attach on NixOS terminal login (zsh.nix enforces this) |
| `yt-dlp.nix` | yt-dlp | media downloader |
| `zsh.nix` | zsh | shell + aliases + custom functions |

## ZSH CUSTOM FUNCTIONS (zsh.nix)

| Function | Action |
|----------|--------|
| `rebuild <target>` | `nixos-rebuild` / `darwin-rebuild` from remote flake |
| `local-rebuild <target>` | Same but from local `.` |
| `rehome <target>` | `home-manager switch` from remote flake |
| `local-rehome <target>` | Same but from local `.` |

On NixOS: zsh auto-attaches to tmux session `main` on interactive login (skipped on Darwin).

## ALIASES (defined in zsh.nix)

```
cat  → bat
ls   → eza
tmux → tmux new -As main
```

## CONVENTIONS

- Platform-conditional logic uses `pkgs.stdenv.isDarwin` / `pkgs.stdenv.isLinux`
- Tools that need aliases or shell integration go in `zsh.nix`, not their own file
- New tool with significant config → own file; simple `enable = true` → `packages.nix`
