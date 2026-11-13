# AGENTS.md - genixis Nix Configuration Repository

**Last updated:** 2026-11-12 | **Branch:** main

A declarative Nix flake monorepo. It configures NixOS, macOS (nix-darwin), and Home Manager, and runs a self-hosted media stack and productivity services in Podman OCI containers.

Origin of this repository is a self-hosted Forgejo server (`git+https://forgejo.local.jracon.xyz/jracon/genixis`), reachable on the LAN. Its name also resolves off the LAN, through the subnet route of the tailnet. README install commands use this URL. Origin is mirrored to `github:jracon/genixis`. README uses the mirror as its off-LAN fallback (see docs/ci.md).

> **Keep this file current.** Update AGENTS.md in the same commit when a change does one of these:
>
> - It adds, removes, or renames a host, an output, a flake input, a `common/` file, a module directory, a container, or a Home Manager user.
> - It changes or breaks a convention below.
>
> Update README.md in the same commit if install or rebuild steps change. If the code and this file disagree, fix whichever is wrong. Do not work around the disagreement.
>
> **Writing rules.** Write every change to this file in Simplified Technical English (ASD-STE100). Use short sentences, active voice, and one word for one meaning. Put one instruction in each sentence. Its text must also read fluently. Do not use sentence fragments or long chains of clauses. Use the `technical-english` skill when you write or rewrite a section. Compare each rewrite with its original through the `semantic-diff` skill.

---

## TOOLS

- `nix fmt` formats the repository. Use it, not `nixfmt` directly.
- `nixd` is the Nix language server. `nixfmt` is the formatter behind `nix fmt`.
- `nh` runs builds and switches, through the fish functions `rebuild` and `rehome`. Do not run a rebuild unless the user asks.
- `.claude/settings.json` is the command allowlist of this repository. Git tracks the file, so every worktree gets it. It allows these commands:
  - `nix fmt`, `nix fmt -- --ci`, and `nix flake check --impure`.
  - `nix flake archive --json --dry-run`. Its output lists the store path of each flake input at `.inputs.<name>.path`. Use it, not `nix eval`, to find an input path.
  - `nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath`, in this exact form.
  - `git rm` with one or more paths removes tracked files of the worktree. Its allowlist holds no rule for `rm`.
  - `tea comment --repo jracon/genixis ...` and `tea pulls create --repo jracon/genixis ...`. Put `--repo jracon/genixis` directly after the subcommand. A rule matches only the start of a command. One `tea comment` rule did not match a multi-line body under dontAsk (issue 226). Post each comment with the verb form `tea comments add <n> <body>` instead. Its forge hook allows the verb form in this repository, also with a multi-line body.
  - It denies `tea comment` with `delete` or `rm`.
  - `claude -p --settings .scratch/*` starts a nested print-mode session, for a probe of the settings behaviour. Write the settings file under `.scratch/` of the worktree. Name the path relative to the worktree root, or the rule does not match.
  - Rules for `qmd update` and `qmd embed` sit in the global allow list of `claude.nix`, not in `.claude/settings.json` of this repository. A search skill sends the sessions of every project to these two commands. Read verbs of `qmd` sit in that list already. Each rule covers the bare command only, because `qmd update --pull` also runs `git pull`. An unattended session cannot edit `.claude/settings.json`, so a leg writes the rules into `claude.nix`. Those rules reach a session only after the next switch of the home.
  - Global rules of `claude.nix` deny `direnv exec`, `nix eval` with `--expr` or `--apply`, `nix repl`, and `git -C`. See docs/forge-hook.md. If a tool is missing from the environment, report it.

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
│   ├── hardware/               # cachyos-kernel, windows-dual-boot (desktop), user-slice-memory, watchdog, zram (services)
│   ├── programs/cli/           # One .nix per CLI tool, loaded on every platform
│   ├── programs/darwin/        # macOS-only Home Manager extras
│   ├── programs/gui/           # GUI apps (macOS, and NixOS with local.gui = true)
│   ├── programs/nixos/         # NixOS-only Home Manager extras
│   ├── services/                # dispatcher/ (factory loop), reticulum.nix, syncthing.nix, tailscale/, rclone-webdav.nix
│   └── virtualisation/
│       ├── podman.nix           # backend config + daily autoPrune
│       └── oci-containers/      # self-hosted services, one subdir per group
├── users/                       # optional per-user Home Manager overrides (users/<name>.nix, loaded if present)
├── disk-layouts/                # disko partitioning templates
└── docs/                        # the documentation tree; see The docs tree below
```

docs/ holds the documentation tree of the repository. docs/design.md holds the repository-wide design criteria, and each topic file holds the criteria of its topic. Each file of the tree is named in the section below.

## The docs tree

Reference text of this repository lives in docs/. Read a file only when the task needs it. A session loads the index first.

Each checkout holds its own qmd index under `.qmd/`. Its config `.qmd/index.yml` is tracked. Databases and caches under `.qmd/` are ignored. Build the index of a fresh checkout with `qmd update` and `qmd embed`. Search the tree with `qmd query '<question>'`. A `search` skill holds the procedure.

Each file of the tree opens with a title and a one-line purpose. One file holds one topic, and each criterion lives with the concept that it governs (docs/design.md holds the map).

- `docs/design.md` — the repository-wide criteria: the Stance, the Necessity Tests, the Workaround discipline, the trust posture, the Documentation Law, and the map to the topic files.
- `docs/flake.md` — the flake outputs and the module loading, with the Declarative Law.
- `docs/secrets.md` — the key channels, the tokens, and the secret inventory, with the Security Law of secrets.
- `docs/keymap.md` — the binding table of the modifier layers, with the Terminal Law of the layers.
- `docs/terminal-aesthetic.md` — the rules of the four terminal surfaces and the frame, with the colour rule.
- `docs/cli.md` — the shell, the editor, the plain-word commands, and the text-is-the-interface criterion.
- `docs/project.md` — the project binary and the ide window, with the Workflow Law.
- `docs/forge-hook.md` — the settings layers, the plans, and the answers of the forge hook, with the least-privilege rules.
- `docs/tmux-darwin.md` — the launchd tmux server of Darwin and its client guards.
- `docs/containers.md` — the container groups, the services, and the reverse proxy, with the Service Law.
- `docs/services.md` — the dispatcher loop, the tailnet, the sync, the naming chain of the forge, and the spawn-storm resilience layers.
- `docs/ci.md` — the workflows, the runner, and the templates of the forge, with the gate rules.
- `docs/runbook.md` — the operating procedures of the repository, for the owner at a terminal.
- `docs/decisions.md` — the decision register and the rejected list.

## COMMITS

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>)!: <summary>`.

- **Summary:** lowercase, imperative, no trailing period. A whole subject line holds at most 72 characters.
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
- **Breaking (`!` + `BREAKING CHANGE:` footer):** use it for anything that needs a manual step on the next rebuild. Examples: data migration, re-login, file cleanup. Its footer says what to do.
- **Body:** explain *why*, and anything that the diff does not show. Use one topic for each commit. Each commit must evaluate on its own.
- No probe content reaches a commit. A person answers the permission prompt of a probe. An allowlist entry, a nix store path, a temporary test command, or an edit of `AGENTS.md` or of a settings file does not answer it.
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

Fish functions `rebuild` and `rehome` (see docs/runbook.md) do the same against `git+https://forgejo.local.jracon.xyz/jracon/genixis` instead of `.`. They are for machines without a local checkout.

Sometimes the forge does not answer within 3 seconds (for example in WSL while the Windows host is on the work VPN). Then the functions fall back to the GitHub mirror, `git+https://github.com/jracon/genixis`. They also override the `themes` input with its mirror `git+https://github.com/jracon/themes` at the locked revision.

Use `git+https://`. Never use `github:` refs. They resolve through the rate-limited, unauthenticated GitHub API.

You must `git add` new files before the flake can see them.
