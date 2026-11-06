# AGENTS.md - genixis Nix Configuration Repository

**Last updated:** 2026-11-06 | **Branch:** main

A declarative Nix flake monorepo. It configures NixOS, macOS (nix-darwin), and Home Manager, and runs a self-hosted media stack and productivity services in Podman OCI containers.

The origin is a self-hosted Forgejo server (`git+https://forgejo.local.jracon.xyz/jracon/genixis`), reachable on the LAN only. The README install commands use this URL. The origin is mirrored to `github:jracon/genixis`. The README uses the mirror as its off-LAN fallback, and so does `.forgejo/workflows/update-flake.yaml` (see docs/ci.md).

> **Keep this file current.** Update AGENTS.md in the same commit when a change does one of these:
>
> - It adds, removes, or renames a host, an output, a flake input, a `common/` file, a module directory, a container, or a Home Manager user.
> - It changes or breaks a convention below.
>
> Update README.md in the same commit if install or rebuild steps change. If the code and this file disagree, fix whichever is wrong. Do not work around the disagreement.
>
> **Writing rules.** Write every change to this file in Simplified Technical English (ASD-STE100). Use short sentences, active voice, and one word for one meaning. Put one instruction in each sentence. The text must also read fluently. Do not use sentence fragments or long chains of clauses. Use the `technical-english` skill when you write or rewrite a section. Compare each rewrite with its original through the `semantic-rewrite` skill.

---

## TOOLS

- `nix fmt` formats the repository. Use it, not `nixfmt` directly.
- `nixd` is the Nix language server. `nixfmt` is the formatter behind `nix fmt`.
- `nh` runs builds and switches, through the fish functions `rebuild` and `rehome`. Do not run a rebuild unless the user asks.
- `.claude/settings.json` is the command allowlist of this repository. Git tracks the file, so every worktree gets it. It allows these commands:
  - `nix fmt`, `nix fmt -- --ci`, and `nix flake check --impure`.
  - `nix flake archive --json --dry-run`. Its output lists the store path of each flake input at `.inputs.<name>.path`. Use it, not `nix eval`, to find an input path.
  - `nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath`, in this exact form.
  - `tea comment --repo jracon/genixis ...` and `tea pulls create --repo jracon/genixis ...`. Put `--repo jracon/genixis` directly after the subcommand. A rule matches only the start of a command.
  - It denies `tea comment` with `delete` or `rm`.
  - The global rules of `claude.nix` deny `direnv exec`, `nix eval` with `--expr` or `--apply`, `nix repl`, and `git -C`. See docs/forge-hook.md. If a tool is missing from the environment, report it.

## STRUCTURE

```
genixis/
├── flake.nix                # Outputs: darwinConfigurations, devShells, formatter, homeConfigurations, nixosConfigurations
├── home.nix                  # Home Manager base (stateVersion, standalone homeDirectory fallback)
├── agenix-rules.nix           # agenix public keys
├── common/                    # Modules shared across hosts — see flake.nix's module lists for which file goes where
├── lib/                       # Non-module helpers that modules import (no host lists it, so expandModules never loads it)
│   ├── project-package.nix    # buildGoModule of the project tool (also the flake check, so go test runs on the runner)
│   └── syncthing.nix          # Syncthing devices + folders (shared by the NixOS and Home Manager modules)
├── modules/
│   ├── hardware/               # cachyos-kernel, windows-dual-boot (desktop only)
│   ├── programs/cli/           # One .nix per CLI tool, loaded on every platform
│   ├── programs/darwin/        # macOS-only Home Manager extras
│   ├── programs/gui/           # GUI apps (macOS, and NixOS with local.gui = true)
│   ├── programs/nixos/         # NixOS-only Home Manager extras
│   ├── services/                # dispatcher/ (factory loop), syncthing.nix, tailscale/, rclone-webdav.nix
│   └── virtualisation/
│       ├── podman.nix           # backend config + daily autoPrune
│       └── oci-containers/      # self-hosted services, one subdir per group
├── users/                       # optional per-user Home Manager overrides (users/<name>.nix, loaded if present)
├── disk-layouts/                # disko partitioning templates
└── docs/                        # the documentation tree; see The docs tree below
```

docs/ holds the documentation tree of the repository. docs/design-philosophy.md holds its design criteria. Each reference file of the tree is named in the section below.

## The docs tree

The reference text of this repository lives in docs/. Read a file only when the task needs it.

Build the search index of the tree with `qmd collection add docs`. Search the index with `qmd query '<question>'`. The index is state of the host, not of the repository.

- `docs/design-philosophy.md` — the criteria that decide what belongs in this repository.
- `docs/flake.md` — `flake.nix`: module loading, the outputs, Home Manager, the colour palettes, and the per-machine settings.
- `docs/secrets.md` — the agenix secrets, the key channels, the ssh login and push keys, and the ssh route to the forge.
- `docs/keymap.md` — the modifier layers and the one table of the key bindings.
- `docs/terminal-aesthetic.md` — the rules of the prompt, the status bar, the fish greeting, and the fastfetch panel (issue #104).
- `docs/cli.md` — `modules/programs/cli/`: fish and its functions, neovim, the plain-word commands, the aliases, and the editor.
- `docs/project.md` — the `project` binary and the `ide` window.
- `docs/forge-hook.md` — the claude.nix context of Claude Code, the permissions, the plans, and the answers of the forge hook.
- `docs/tmux-darwin.md` — the tmux server on Darwin.
- `docs/containers.md` — the Podman container patterns and the per-service quirks.
- `docs/services.md` — the dispatcher loop, tailscale, syncthing, and rclone-webdav.
- `docs/ci.md` — the CI workflows and the forge templates.
- `docs/code-style.md` — the Nix layout rules and the anti-patterns.

## COMMITS

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>)!: <summary>`.

- **Summary:** lowercase, imperative, no trailing period. The whole subject line has at most 72 characters.
- **Types:**
  - `feat` — a new capability: a service, program, host, user, or option.
  - `fix` — a correction of wrong or unsafe behaviour.
  - `refactor` — a restructuring with no behaviour change (ideally identical derivations).
  - `style` — `nix fmt` or layout-only changes.
  - `chore` — dependency and lock bumps, removals, housekeeping.
  - `ci` — `.forgejo/workflows/`.
  - `docs` — AGENTS.md, docs/, README, comments only.
  - `revert`.
- **Scope** (optional): the one thing that the commit touches. Omit it when a commit spans several things.
  - A host: `media`, `desktop`, `darwin`.
  - A service or container: `romm`, `caddy`, `tailscale`.
  - A program: `fish`, `nvim`.
  - An area: `flake`, `home`, `common`, `containers`, `agenix`.
- **Breaking (`!` + `BREAKING CHANGE:` footer):** use it for anything that needs a manual step on the next rebuild. Examples: data migration, re-login, file cleanup. The footer says what to do.
- **Body:** explain *why*, and anything that the diff does not show. Use one topic for each commit. Each commit must evaluate on its own.
- The CI bot commit `chore: update flake inputs` already fits this standard. Leave it as it is.

## COMMANDS

```bash
nix fmt                                                          # Format all .nix files
nix fmt -- --ci                                                  # Check formatting (matches CI)
nix flake check --impure                                        # Validate (matches CI)
nixos-rebuild switch --impure --flake .#${ROLE}                  # Apply NixOS + Home Manager (local checkout)
sudo darwin-rebuild switch --impure --flake .#${HOSTNAME}        # Apply macOS + Home Manager (local checkout)
home-manager switch --impure --flake .#${USERNAME}                # Standalone Home Manager, non-NixOS only
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel   # Dry build
nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath   # Evaluate Darwin (flake check skips it)
nix repl .#nixosConfigurations.<host>.config                     # Debug interactively
nix flake update                                                 # Bump all inputs
```

The `rebuild` and `rehome` fish functions (see docs/cli.md) do the same against `git+https://forgejo.local.jracon.xyz/jracon/genixis` instead of `.`. They are for machines without a local checkout.

Forgejo is LAN-only. Sometimes it does not answer within 3 seconds (for example in WSL while the Windows host is on the work VPN). Then the functions fall back to the GitHub mirror, `git+https://github.com/jracon/genixis`. They also override the `themes` input with its mirror `git+https://github.com/jracon/themes` at the locked revision.

Use `git+https://`. Never use `github:` refs. They resolve through the rate-limited, unauthenticated GitHub API.

You must `git add` new files before the flake can see them.
