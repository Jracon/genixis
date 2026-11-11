# secrets

How the repository stores secrets and key material, and which key decrypts what.

Domain: what. Reader: a session that adds a secret or a key, or finds a decrypt failure.
Code: agenix-rules.nix, common/agenix.nix, common/ssh.nix, modules/programs/cli/ssh.nix, .ssh/, modules/programs/cli/forge-known-hosts.

## What is the topic?

The repository holds two key channels, and no key crosses them:

1. The system channel. Each host that consumes a system secret holds one host key, and the key decrypts only the secrets of that host. The identity is `/root/.ssh/genixis_host` on Linux and `/Users/<primary user>/.ssh/genixis_host` on Darwin (common/agenix.nix:10-20). A host that declares no system secret holds no host key, so the file need not exist there.
2. The user channel. The user key `~/.ssh/genixis_user` is the only key a Home Manager layer reads (modules/programs/cli/ssh.nix:8-11). It decrypts the two user secrets, so both name every user key.

The user `nixos` holds no key yet. Its entry is pending until its public half exists (agenix-rules.nix:9-14).

## How is the topic realized?

The rules file maps each encrypted file to its recipients (agenix-rules.nix:17-77):

1. User secrets, for every user key (`dev`, `jademeskill`, `root`): `.ssh/config.age` and `modules/programs/cli/claude/zai_token.age`.
2. Secrets of the host `services`: the dispatcher webhook, the caddy environment, the dawarich pair, the forgejo runner token, the invidious triple, the mealie, monica, and vaultwarden environments, the monica database, the radicale pair, the wger pair.
3. Secrets of the host `media`: the gluetun environment, the recyclarr config, the gamevault pair, the romm pair.
4. One secret crosses two hosts: the tailscale client secret names both `media` and `services` (agenix-rules.nix:20-23).

The public halves sit in the repository: `.ssh/agenix/hosts/<host>.pub` for the two hosts and `.ssh/agenix/users/<user>.pub` for the three users. The reader strips the trailing newline, so it never reaches agenix as an empty recipient (agenix-rules.nix:1-6).

The token of the plan is a user secret. The module decrypts it to `~/.config/project/plans/zai.token` only when the encrypted file is committed, and the session reads it through the helper of the plan, never from a settings value (modules/programs/cli/claude.nix:132-140, 215-231).

The ssh layer:

1. `programs.ssh` runs with no default config, and it includes the decrypted `~/.ssh/genixis_config` (modules/programs/cli/ssh.nix:21-28).
2. The hand-managed `~/.ssh/known_hosts` stays first and writable. The committed `forge_known_hosts` only supplements it (modules/programs/cli/ssh.nix:32-33).
3. The host key of the forge is public material, pinned under `[forgejo.local.jracon.xyz]:222` (modules/programs/cli/forge-known-hosts:1). The pin makes each client fail closed when the forge rotates its host key, and a rotation is a one-line commit of the new public key.
4. The login keys of the machines sit in `.ssh/authorized/<machine>.pub`, authorized for root and for each Home Manager user (common/ssh.nix:22-26). The repository holds two: `m2pro-mbp.pub` and `services-dev.pub`.
5. The ssh daemon of each NixOS host accepts no password, and root logs in with a key only (common/ssh.nix:9-16).

The agenix CLI is a system package on each host that loads the agenix module (common/agenix.nix:22-24). The fish wrapper of agenix opens a secret in the editor pane of an ide window (modules/programs/cli/fish.nix:68-74).

## Why is the topic that way?

1. No secret sits in the clear, and no key is inlined in a module (Security law item 1, docs/design-philosophy.md).
2. The two channels keep a host breach from reaching the user secrets, and the reverse (Security law item 2).
3. A token reaches a process only through a file that the process reads, so no token sits in a command argument or a plan file (Security law item 3, docs/design-philosophy.md). Record 10 of docs/decisions.md states the origin of the token rule.
4. Each machine holds one scoped forge token and one push key, and the agent login holds no admin role (Security law item 4, docs/design-philosophy.md).
5. A secret that agenix cannot decrypt fails every secret of that user, so a missing key stops the whole home, not one service (modules/programs/cli/claude.nix:132-134).

## What does the topic enable?

The end of the topic: the repository carries its full secret inventory in the clear, as public keys and encrypted files, and each host opens only its own share. The Security law of docs/design-philosophy.md states the criterion.

## How does a reader use and change the topic?

The procedure for a new secret crosses topics, so it lives in docs/runbook.md. The ssh route to the forge lives there too.

To find which hosts decrypt a secret, read the entry of the secret in agenix-rules.nix. To find which secrets a host decrypts, read the entries that name it.
