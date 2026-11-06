# Code style

The layout rules of the Nix files in this repository, and the patterns that no change may introduce.

## CODE STYLE

**Formatting:** Always run `nix fmt` (nixfmt-tree) before commit. Never format by hand. CI fails on unformatted files.

**Layout rules.** nixfmt preserves these rules but does not enforce them. Follow them by hand.

- **Multi-line:** Nested sets and non-empty lists always span multiple lines. Empty ones are `{ }` and `[ ]`. Exception: a one-item list passed as a function argument stays inline (`lib.hm.dag.entryAfter [ "writeBoundary" ]`).
- **Ordering:**
  - Sort keys A–Z, case-insensitive. Break ties by character code (`-` before `_`, shorter prefix first).
  - Single-line options and nested blocks sort together. Never group by shape.
  - Sort function arguments and `inherit` lists the same way. `...` goes last.
  - If a prefix gets a second key, merge both into one block. For example, `nix.settings.x` and `nix = { ... }` become one `nix` block.
- **`enable` and `inherit` come first.** A blank line follows them when other keys follow.
- **Domain-order exceptions:**
  - Containers start with `image`, then a blank line, then `hostname`/`pull`/`user`, then a blank line, then A–Z.
  - Flake inputs put `url` first.
  - disko puts `type` first.
  - starship puts `format` and `right_format` first.
  - VSCodium language blocks (`"[python]"`) go last.
  - Flake `outputs` arguments put `self` first.
  - `let` bindings follow dependency order.
- **Lists** sort A–Z too, except where the order has meaning:
  - Numbers, and port strings, sort numerically by host port.
  - Container `volumes` sort by container path. This keeps a parent mount before the files mounted inside it.
  - Positional arguments (`ExecStart`) and the Dock `persistent-apps` keep their order.
- **Blank lines:** Use one between top-level option paths. Use one between sibling entities (containers, systemd units, flake inputs). Otherwise use blank lines only to separate logical groups.
- **Quotes:** Do not quote keys that are valid identifiers. Write `users.users.root`, not `users.users."root"`.

Files and directories use kebab-case (`rclone-webdav.nix`, `media-servers`). Variables and functions use camelCase (`expandModules`, `homeModules`).

**Simple module:**

```nix
{
  config,
  pkgs,
  ...
}:

{
  services.tailscale.enable = true;
}
```

**With local (per-machine) variables:**

```nix
{
  local,
  ...
}:

let
  primaryDisk = builtins.elemAt local.disks 0;
in { ... }
```

## ANTI-PATTERNS

- Never commit the plaintext of `.age` secret files. Use `agenix` encryption.
- Never hardcode secrets in `.nix` files. Use `age.secrets.*` (see Secret patterns in docs/containers.md).
- Never format by hand. Always use `nix fmt`.
- Never use `pull = "always"` on a container. Use `pull = "newer"`.
- Never omit firewall rules for an exposed container port. Never expose the port of a sidecar DB to the host.
- Never put multi-service orchestration in a flat `.nix` file. Give it a subdirectory.
- Never set `nixpkgs.config` or `nixpkgs.overlays` anywhere but `common/nixpkgs.nix`.
- Never fetch sources with unpinned `builtins.fetchGit` or `fetchTarball`. Add a flake input (`flake = false` for non-flakes).
- Do not reintroduce zsh config. The shell is fish now.
- Data directories are always at `/mnt/<service>/`. Shared media is always at `/mnt/media/`. Do not use named Podman volumes.
