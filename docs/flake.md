# The flake

How `flake.nix` loads modules and builds the outputs: the hosts, Home Manager, the colour palettes, and the per-machine settings.

## MODULE LOADING (flake.nix)

Hosts list their modules as plain paths. `expandModules` replaces each directory in a list with every `.nix` file below it (recursively). Files and non-path modules (for example `agenix.nixosModules.default`) pass through unchanged. A mistyped path causes an evaluation error. A `.nix` file added to a listed directory loads automatically, so keep non-module files (`.age`, `.yaml`, scripts) non-`.nix`.

**Outputs:**

- NixOS: `bare`, `media` (arr stack and downloaders), `services` (productivity and infrastructure), `desktop` (dual-boot Windows gaming PC, Plasma, CachyOS kernel), `wsl` (NixOS-WSL), `disko` (install-time).
- Darwin: `m2pro-mbp`.
- Home Manager (standalone): `jademeskill`, `nixos`, `root`.
- Checks: `project`, the Go package of the project tool. Its `checkPhase` runs `gofmt -l` and `go test`, so `nix flake check --impure` runs the tests of the tool on each system it checks. `nix flake check` checks the current system only; the runner builds the linux check and this machine builds the darwin one.
- devShells: `default` for each system. It pins the tools that edit this repository: `go`, `gopls`, `pyright`, `ruff`, `nixd`, `stylua`, and `nixfmt`.

`nixosConfiguration { homeUsers; roleModules; } [ <host module paths> ]` builds the NixOS hosts. The wrappers are `desktopConfiguration`, `serverConfiguration`, and `wslConfiguration`. `nixosConfigurations` sets each host's `networking.hostName` to its output name with `mkDefault`, so `/etc/nixos/configuration.nix` can override it. `disko` is left out.

To learn which `common/*.nix` file applies to which host, read the module lists in `flake.nix`. They are the source of truth.

### Home Manager

Home Manager runs **as a NixOS/nix-darwin module** (`common/home-manager.nix`), so `nixos-rebuild` and `darwin-rebuild` apply it too. The settings are `useGlobalPkgs = true`, `useUserPackages = true`, and `backupFileExtension = "backup"`.

- **Users per host:** `homeUsers` in `flake.nix` sets them.
  - Every NixOS host manages `root`. `desktop` adds `jademeskill`. `wsl` adds `nixos`. Darwin manages `jademeskill`.
  - `services` adds `dev` for remote development, through `devServerConfiguration` in `flake.nix`. This wrapper also loads `llm-agents.nix`. No other server loads it.
  - `common/nixos.nix` declares each non-root `homeUsers` entry as `isNormalUser`. This merges with `/etc/nixos/configuration.nix`.
- **Palette:** each host chooses its own. `nixosConfiguration` takes `palette` (default `violet`; `desktopConfiguration` passes `moss`). `homeModules` turns it into `genixis.palette.name`. Darwin and standalone homes use the default. See Colour palette below.
- **Program set:** the `homeModules` function chooses it by platform. The standalone `homeConfigurations` reuse the same `homeModules`.
  - Darwin: `cli` + `darwin` + `gui`.
  - NixOS with `local.gui = true`: `cli` + `gui` + `nixos`.
  - NixOS otherwise: `cli` + `nixos`.
- **Standalone `homeConfigurations`** exist only for non-NixOS machines. Do not run `rehome` on a NixOS or Darwin host. It would fight the generation that the system manages.
- `useGlobalPkgs` is on. **Never set `nixpkgs.*` inside a Home Manager module.** It causes an error.

**Gotchas to know before you edit `common/`:**

- Every NixOS and Darwin host loads `base.nix`. It sets empty `defaultPackages`, git, flakes, Nix GC and optimise, and the timezone. Put anything universal and OS-level here.
- `homebrew.nix` adds `${homebrew.prefix}/bin` and `/sbin` to `environment.systemPath` at `mkOrder 1100`. This is after the Nix profiles, so Nix-installed tools shadow Homebrew tools.
- `nixpkgs.nix` holds `allowUnfree` and the `nix-vscode-extensions` overlay. Every NixOS and Darwin host loads it. Standalone Home Manager loads it too, because the option paths are identical. It is the one place for nixpkgs config.
- `darwin.nix` uses `self.rev or self.dirtyRev or null` for `system.configurationRevision`. Keep `self` in specialArgs. The file also sets `users.users.<user>.home`, which the Home Manager module needs.
- `agenix.nix` loads on Darwin and on servers. Its Darwin identity path comes from `config.system.primaryUser`. NixOS has no `user` argument.
- `gaming.nix` is for `desktop` only. It sets up Steam (with Remote Play and local transfer firewall rules, and a gamescope session), GameMode, and 32-bit graphics. Playnite runs on Windows only, so it lives on the Windows side of the dual boot.
- `dummy-configuration.nix` exists only so that builds and CI do not fail when no host config exists yet. Never edit it.
- `llm-agents.nix` installs `ccusage`, `qmd`, and `semble` from `numtide/llm-agents.nix`. It takes `claude-code` from nixpkgs, which builds the native binary. The file needs the `llm-agents` input in specialArgs. It declares `qmd` and `semble` in `genixis.claude.tools` for every Home Manager user, through `home-manager.sharedModules`. So standalone homes do not list them.
- `wsl.nix` force-disables systemd-boot (this overrides the dummy config). It leaves `wsl.defaultUser` to `/etc/nixos/configuration.nix`.
- Never put NixOS-only options in a file that Darwin loads. Check the module list in `flake.nix` first.

## Colour palette

Palettes live in their own flake, the `themes` input. It is the public Forgejo repository `jracon/themes`, fetched over HTTPS.

- `palettes.json` is the source of truth. It has the palettes `moss` and `violet`.
- Its `lib` generates theme files for any consumer (CSS, JSON, WezTerm, a neovim plugin).
- To change or add a colour, edit it in `themes`. Then run `nix flake update themes` here. Do not copy hex values into this repository.

This repository only chooses and applies palettes. `modules/programs/cli/palette.nix` exposes these options:

- `genixis.palette.name` is the palette name. Each host sets it (see Home Manager above).
- `genixis.palette.colors` is `themes.lib.resolve name`. It holds the palette plus `ansi.{dark,light}` and `signatureAnsi`.

Real hex appears in two places only:

- WezTerm uses `themes.lib.weztermSchemes`, picked by the OS appearance.
- Neovim uses the `themes` plugin from `themes.lib.neovimPlugin` (`:colorscheme themes`). The plugin reads `background` from the terminal and re-applies on `OptionSet background`.

Every other terminal tool names ANSI colours, so it follows the active WezTerm scheme: tmux, starship, bat `ansi`, delta `ansi`, and lazygit. Do not hardcode hex in them.

## `modules/programs/darwin/` and `modules/programs/nixos/`

- `darwin/default.nix` enables `targets.darwin.copyApps` and disables `linkApps`. So the Home Manager `.app` bundles are real copies in `~/Applications/Home Manager Apps`, and Spotlight indexes them. The Dock (`common/darwin.nix`) pins those copies, not the `${pkgs.<app>}` store paths. Otherwise, apps that Spotlight starts would show up as a second Dock entry.
- `nixos/packages.nix` holds the bare enables for NixOS only (lazydocker).

## NOTES

- Per-machine secrets and settings are in `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS). These files are **not committed**. Shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; syncthing-device-ids = { <hostname> = "..."; }; windows-efi-handle = "..."; }`.
