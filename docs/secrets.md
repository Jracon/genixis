# secrets

How the repository stores secrets and key material, and which key decrypts what.

## Key Channels

This repository holds two key channels, and no key crosses them:

1. System channel. Each host that consumes a system secret holds one host key, and the key decrypts only the secrets of that host. Its identity is `/root/.ssh/genixis_host` on Linux and `/Users/<primary user>/.ssh/genixis_host` on Darwin, set by common/agenix.nix. A host that declares no system secret holds no host key, so the file need not exist there.
2. User channel. User key `~/.ssh/genixis_user` is the only key a Home Manager layer reads, set by ssh.nix of modules/programs/cli. It decrypts the two user secrets, so both name every user key.

## Rules File and Inventory

One rules file, agenix-rules.nix, maps each encrypted file to its recipients:

1. User secrets, for every user key (`dev`, `jademeskill`, `root`): `.ssh/config.age` and `modules/programs/cli/claude/zai_token.age`.
2. Secrets of the host `services`: the dispatcher webhook, the caddy environment, the dawarich pair, the forgejo runner token, the invidious triple, the mealie, monica, and vaultwarden environments, the monica database, the radicale pair, the wger pair.
3. Secrets of the host `media`: the gluetun environment, the recyclarr environment, the gamevault pair, the romm pair.
4. One secret crosses two hosts: the tailscale client secret names both `media` and `services`.

Public halves sit in the repository: `.ssh/agenix/hosts/<host>.pub` for the two hosts and `.ssh/agenix/users/<user>.pub` for the three users. readKey in agenix-rules.nix strips the trailing newline, so an empty recipient never reaches agenix.

## Plan Tokens

Plan tokens are user secrets, and the inventory above lists the encrypted token of the plan. docs/agent-context.md states when the plan is on, where the token lands, and how a session reads it. The token rule lives in the Security Law below.

## SSH Layer Rules

1. `programs.ssh` runs with no default config, and it includes the decrypted `~/.ssh/genixis_config`.
2. A hand-managed `~/.ssh/known_hosts` stays first and writable, and the committed `forge_known_hosts` only supplements it.
3. One host key of the forge is public material, pinned under `[forgejo.local.jracon.xyz]:222` in forge-known-hosts. A pin makes each client fail closed when the forge rotates its host key, and a rotation is a one-line commit of the new public key.
4. Login keys of the machines sit in `.ssh/authorized/<machine>.pub`, authorized for root and for each Home Manager user by common/ssh.nix. This repository holds two: `m2pro-mbp.pub` and `services-dev.pub`.
5. Each ssh daemon of a NixOS host accepts no password, and root logs in with a key only.

Each host that loads the agenix module gets the agenix CLI as a system package. A fish wrapper of agenix opens a secret in the editor pane of an ide window.

## Agenix on Darwin

On Darwin, the agenix Home Manager module decrypts the secrets of a user in a launchd agent, `activate-agenix`. The module puts the decrypted files into the per-user temp directory by default. macOS treats that directory as scratch space, so the decrypted files disappeared while the user stayed logged in (issue 698). modules/programs/darwin/default.nix sets `age.secretsDir` to `~/.local/state/agenix` and `age.secretsMountPoint` to `~/.local/state/agenix.d`. No cleanup of the system removes that directory, so the decrypted files stay readable for the full life of the login session.

The module sets `KeepAlive` on the agent, and launchd starts the script again every 10 seconds, also after exit code 0. Each run replaces the secrets directory, so a reader can find no token file. modules/programs/darwin/default.nix overrides `KeepAlive` to `false` and keeps `RunAtLoad`, so the agent runs once per login. To decrypt the secrets again without a new login, start the agent by hand:

```console
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.activate-agenix
```

The module sets each decrypted file to mode 0400, so only the owner reads it. The directory that holds the decrypted files has mode 0751, so no other user lists it.

## Security Law

Security Law of this topic, at its application (docs/design.md holds the map):

1. No secret in the clear. Every secret is an agenix file. No plaintext secret is committed, and no key is inlined in a module.
2. Two key channels, and no key crosses them. A host key decrypts only the secrets that its host consumes, and a user key decrypts the user secrets. A host that declares no system secret holds no host key. Separation keeps a host breach from the user secrets, and the reverse.
3. A token reaches a process only through a file that the process reads. No token sits in a command argument, where a process list shows it. No token sits in a plan file, because the store is readable by every user of the machine. The record docs/adr/project-tool-plan-tokens.md states the origin of the token rule.
4. A forwarded socket is a trust grant. A grant reaches every process of the login that holds it, so each forward serves one connection and ends with it.
5. A secret that agenix cannot decrypt fails every secret of that user, so a missing key stops the whole home, not one service.
6. Secrets topology is security spine: an agent writes it, and the owner reviews it line by line and merges it.
7. No rotation cadence binds the tokens and keys of the inventory. The rotation of a single secret stays a manual step that its own cause starts, because the repository holds no mechanism that makes a swap of keys across machines easy. The record docs/adr/no-rotation-cadence.md states the reason and the event that reopens the decision.
8. A capture that moves coordination text into repository content runs only after a content rule for it sits in this tree. The rule of the thread store: a thread holds only text that the forge already shows in the clear, and no secret and no session transcript enters it (docs/threads.md).

## Purpose of the Secrets

Purpose of the topic: this repository carries its full secret inventory in the clear, as public keys and encrypted files, and each host opens only its own share. Security Law above states the criterion.

## Find a Secret

A procedure for a new secret crosses topics, so it lives in docs/runbook.md. An ssh route to the forge lives there too.

To find which hosts decrypt a secret, read the entry of the secret in agenix-rules.nix. To find which secrets a host decrypts, read the entries that name it.
