# runbook

Operating procedures of the repository, for the owner at a terminal, after the first successful switch of a machine. README owns the steps before that switch.

## Rebuild a Machine

A rebuild runs only when the owner asks for it.

1. Run `local-rebuild <host>` in a checkout of this repository, or `rebuild <host>` on a machine without a checkout. Each function runs nh, shows a package diff, and elevates with sudo itself (fish.nix).
2. Nix refuses a git checkout that another user owns, and root cannot build from the checkout of dev on services. When the current user does not own the checkout, `local-rebuild` reads it as a path flake, and a path flake also sees untracked files. Run it from the root of the checkout in that case.
3. When the forge does not answer within three seconds, the function prints a notice and falls back to the GitHub mirror. It redirects the themes input to its mirror at the locked revision, and adds `--refresh` so a rebuild right after a push builds that push. Workaround record, the mirror fallback (docs/adr/earlier-records-clause-scope.md). Context: the VPN or the LAN can block the forge. A mirror is the fallback for a tailnet outage and for machines that run no Tailscale. Decision: the GitHub mirror stays the fallback source of the rebuild and rehome functions. Options that lost: the forge as the only source, because one path is a single point of failure (Stance item 6, docs/design.md). Consequences: each fallback rebuild reads the mirror, and the mirror can lag behind the forge. Status: keep as a stated design. Reopen trigger: a fallback rebuild that fails on the mirror, or a rebuild right after a push that does not build that push.
4. Run `rehome <user>` for a standalone home on a machine that no system of this flake builds, and `local-rehome <user>` in a checkout. Never run a rehome on a host whose system this flake builds: it would fight the generation that the system manages.
5. Run `cln` to clean the store: it keeps five generations, the current one, and one garbage-collection root for each direnv project. Base.nix already runs an automatic collection, so add no second one (common/base.nix).

One agent-facing command list stays where it is: AGENTS.md, section COMMANDS.

## Use the Clipboard at a Terminal

1. Inside tmux, `clip` writes the tmux buffer with the `-w` flag, which also sends the text to the terminal as an OSC 52 escape. Through a session tab of a remote login, the text lands on the clipboard of the Mac that shows the window.
2. On Darwin outside tmux, `clip` runs pbcopy and `paste` runs pbpaste, and pbpaste also sees the text that an OSC 52 escape wrote.
3. On Linux outside tmux, `paste` fails: WezTerm answers no OSC 52 read. `clip` prints the OSC 52 escape when standard output is a terminal. Its name `paste` shadows the coreutils tool: write `command paste` to reach it.

## Reach the Forge over SSH

1. Check that the ssh config secret decrypted: the file `~/.ssh/genixis_config` exists.
2. Check the route: `ssh -G forgejo.local.jracon.xyz` answers `user git` and `port 222` (the transport record on issue 166).
3. Check the host key: `~/.ssh/forge_known_hosts` holds the entry under the name with the port (forge-known-hosts).
4. Open one connection and read the Forgejo greeting. One naming chain resolves the name: the router override on the LAN, the split DNS through the tailnet off the LAN (docs/adr/forge-naming-chain.md).

## Store an SSH Key Passphrase in the Keychain on Darwin

On macOS, the ssh agent forgets each key at reboot. Its option `UseKeychain` (ssh.nix) makes ssh read the passphrase from the Keychain. Store the passphrase once for each key that has one.

1. Run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`, and enter the passphrase.
2. Repeat step 1 for each other key that has a passphrase. Use `ssh-keygen -y -P '' -f <key>` to test a key: the command fails when the key has a passphrase.
3. Check the result: `ssh -G github.com` shows `usekeychain yes`.
4. Reboot, then open one ssh connection. ssh must not ask for the passphrase.

## Read the Log of a Container and Restart It

1. Run `lgs <service>` to follow the journal of the podman unit.
2. Restart a container with `systemctl restart podman-<service>`, because each container is a systemd service of its host.
3. Quirks of each service sit in docs/containers.md. Two need the owner most often: the invidious app container restarts on a daily timer, and the vaultwarden backup lands daily under `/mnt/vaultwarden-backups`.

## Add a Secret

1. Put the public key of a new recipient under `.ssh/agenix/` first, when the recipient is new (docs/secrets.md).
2. Add the entry to agenix-rules.nix and name the recipients: user keys or host keys.
3. Create the encrypted file with `agenix -e <path>`. Inside an ide window, the editor pane opens it.
4. Reference the file in the module of the consumer with `age.secrets.<name>.file`, and read the decrypted path through `config.age.secrets.<name>.path`.
5. Commit the encrypted file and the rule in one commit. Each named host decrypts it on its next rebuild.
6. Check the plaintext before you commit: agenix verifies the recipients, not the content, so an empty plaintext passes (the audit record on issue 218, part 2, entry 19).

## Onboard a Machine to the Forge

1. Create one scoped token of the claude-bot login for the machine, and one push key. Token scopes are user read, repository write, and issue write, because the hook reads the login with tea whoami. A wider role is never the answer (least privilege per identity, docs/agent-context.md). These scopes rest on the record of the old docs tree and on the forge; no code of this repository states them.
2. Log the tea of the machine in with the token. Its login state is machine state, outside this repository.
3. One push key sits at `~/.ssh/claude-bot` of the machine, beside the login key. Register its public half on the claude-bot account and on no other account. Never commit it under `.ssh/authorized/`: that directory authorizes logins to machines, and the push key is no login key.
4. Add the public login key of the machine under `.ssh/authorized/<machine>.pub`, so the hosts accept it (common/ssh.nix).
5. Set the git config key `forge.humanLabels` of the clone by hand. No step of a repository writes it, and the hook asks on every label edit without it (forge-hook.py).
6. Commit the public key of the host under `.ssh/agenix/hosts/<host>.pub` when the host consumes system secrets (docs/secrets.md).

## Run a Produced Project

1. A produced project, for example Minecraft_Recomposed, owns its git allow rules. A move of the rules needs its own issue in that repository; this repository holds no tracking entity for it (the audit record on issue 218, part 2, entry 8).
2. Set `forge.humanLabels` by hand in each clone of a produced project, or a spawned session there stops at the label-edit prompt (the audit record on issue 218, part 2, entry 11).

## Give a Machine the Forge Name Without the Chain

A machine that cannot hold the naming chain, for example a host with no DNS path to the router, keeps a hand-edited `/etc/hosts` entry for the forge name. Workaround record, the hand-edited hosts entry (docs/adr/earlier-records-clause-scope.md). Context: a background session there runs in a process chain that holds no macOS Local Network grant, and the grant follows the code signature, which changes at each Nix build. Decision: the owner edits the hosts entry by hand on each such machine. Options that lost: the committed hosts pin, because the naming chain carries the name and the pin adds no reachability in any state (docs/adr/forge-naming-chain.md, which supersedes the committed-pin form). Consequences: the entry lives outside this repository, and declarativization stays an option of the owner. Status: keep as a stated design. Reopen trigger: a declarative path that holds the entry across Nix builds.

## Read a Go Gate Result

1. A bare `go test` in a session of this repository can fail for environment reasons: the main package needs a C compiler that the devShell holds no gcc for on some hosts, and the tests read the git identity of the account (the audit record on issue 218, part 2, entry 21).
2. Treat a green `nix flake check --impure` as the authoritative run: its check phase builds and runs the same tests in the sandbox (lib/project-package.nix).
3. CI runs the same check on every pull request. Do not retry a failed local run with changed environment variables; quote the failures as environmental and leave the run to the gate.
