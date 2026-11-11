# runbook

The operating procedures of the repository, for the owner at a terminal.

Domain: how-to. Reader: the owner.
Code: none. Each procedure names the files it touches.

## Rebuild a machine

1. Run `local-rebuild <host>` in a checkout of this repository, or `rebuild <host>` on a machine without a checkout. The function runs nh, shows a package diff, and elevates with sudo itself (modules/programs/cli/fish.nix:23-35, 119-124).
2. When the forge does not answer within three seconds, the function prints a notice and falls back to the GitHub mirror. It redirects the themes input to its mirror at the locked revision, and adds `--refresh` so a rebuild right after a push builds that push (fish.nix:40-57).
3. Run `rehome <user>` for a standalone home on a machine that no system of this flake builds, and `local-rehome <user>` in a checkout (fish.nix:36-38, 311-314).
4. Run `cln` to clean the store: it keeps five generations and the current one (fish.nix:79).

The agent-facing command list of AGENTS.md, section COMMANDS, stays where it is.

## Use the clipboard at a terminal

1. Inside tmux, `clip` writes the tmux buffer and `paste` reads it (fish.nix:263-269, 285-305).
2. On Darwin outside tmux, `clip` runs pbcopy and `paste` runs pbpaste (fish.nix:263-271).
3. On Linux outside tmux, `paste` fails: WezTerm answers no OSC 52 read. `clip` prints the OSC 52 escape when standard output is a terminal (fish.nix:285-305).

## Reach the forge over ssh

1. Check that the ssh config secret decrypted: the file `~/.ssh/genixis_config` exists (modules/programs/cli/ssh.nix:12-15).
2. Check the route: `ssh -G forgejo.local.jracon.xyz` answers `user git` and `port 222` (the transport record on issue 166).
3. Check the host key: `~/.ssh/forge_known_hosts` holds the entry under the name with the port (modules/programs/cli/forge-known-hosts:1).
4. Open one connection and read the Forgejo greeting. The naming chain resolves the name: the router override on the LAN, the split DNS through the tailnet off the LAN (docs/decisions.md, record 2).

## Read the log of a container and restart it

1. Run `lgs <service>` to follow the journal of the podman unit (fish.nix:307-309).
2. Restart a container with `systemctl restart podman-<service>`, because each container is a systemd service of its host.
3. The quirks of each service sit in docs/containers.md. Two need the owner most often: the invidious stack restarts on a daily timer (invidious.nix:34-54), and the vaultwarden backup lands daily under `/mnt/vaultwarden-backups` (vaultwarden.nix:22-65).

## Add a secret

1. Put the public key of a new recipient under `.ssh/agenix/` first, when the recipient is new (docs/secrets.md).
2. Add the entry to agenix-rules.nix and name the recipients: user keys or host keys (agenix-rules.nix:17-77).
3. Create the encrypted file with `agenix -e <path>`. Inside an ide window, the editor pane opens it (fish.nix:68-74).
4. Reference the file in the module of the consumer with `age.secrets.<name>.file`, and read the decrypted path through `config.age.secrets.<name>.path`.
5. Commit the encrypted file and the rule in one commit. The next rebuild of each named host decrypts it.
6. Check the plaintext before you commit: agenix verifies the recipients, not the content, so an empty plaintext passes (the audit record on issue 218, part 2, entry 19).

## Onboard a machine to the forge

1. Create one scoped token of the claude-bot login for the machine, and one push key. A wider role is never the answer (Security law item 4, docs/design-philosophy.md).
2. Log the tea of the machine in with the token. The login state of tea is machine state, outside this repository.
3. Add the public login key of the machine under `.ssh/authorized/<machine>.pub`, so the hosts accept it (common/ssh.nix:22-26).
4. Set the git config key `forge.humanLabels` of the clone by hand. No step of a repository writes it, and the hook asks on every label edit without it (modules/programs/cli/claude/forge-hook.py:191-199).
5. Commit the public key of the host under `.ssh/agenix/hosts/<host>.pub` when the host consumes system secrets (docs/secrets.md).

## Run a produced project

1. A produced project, for example Minecraft_Recomposed, owns its git allow rules. A move of the rules needs its own issue in that repository; this repository holds no tracking entity for it (the audit record on issue 218, part 2, entry 8).
2. Set `forge.humanLabels` by hand in each clone of a produced project, or a spawned session there stops at the label-edit prompt (the audit record on issue 218, part 2, entry 11).

## Give a machine the forge name without the chain

A machine that cannot hold the naming chain, for example a host with no DNS path to the router, keeps a hand-edited `/etc/hosts` entry for the forge name. The declarativization of the entry stays an option of the owner, and the stopgap register keeps it as a stated design (docs/decisions.md, record 2 and stopgap register, entry 2).

## Read a Go gate result

1. A bare `go test` in a session of this repository can fail for environment reasons: the main package needs a C compiler that the devShell holds no gcc for on some hosts, and the tests read the git identity of the account (the audit record on issue 218, part 2, entry 21).
2. Treat a green `nix flake check --impure` as the authoritative run: its check phase builds and runs the same tests in the sandbox (lib/project-package.nix:36-43).
3. CI runs the same check on every pull request (.forgejo/workflows/ci.yaml:20-24). Do not retry a failed local run with changed environment variables; quote the failures as environmental and leave the run to the gate.
