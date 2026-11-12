# secrets

How the repository stores secrets and key material, and which key decrypts what.

## What Is the Topic?

This repository holds two key channels, and no key crosses them:

1. System channel. Each host that consumes a system secret holds one host key, and the key decrypts only the secrets of that host. Its identity is `/root/.ssh/genixis_host` on Linux and `/Users/<primary user>/.ssh/genixis_host` on Darwin (common/agenix.nix:10-20). A host that declares no system secret holds no host key, so the file need not exist there.
2. User channel. User key `~/.ssh/genixis_user` is the only key a Home Manager layer reads (modules/programs/cli/ssh.nix:8-11). It decrypts the two user secrets, so both name every user key.

User `nixos` holds no key yet. Its entry is pending until its public half exists (agenix-rules.nix:9-14).

## How Is the Topic Realized?

One rules file maps each encrypted file to its recipients (agenix-rules.nix:17-77):

1. User secrets, for every user key (`dev`, `jademeskill`, `root`): `.ssh/config.age` and `modules/programs/cli/claude/zai_token.age`.
2. Secrets of the host `services`: the dispatcher webhook, the caddy environment, the dawarich pair, the forgejo runner token, the invidious triple, the mealie, monica, and vaultwarden environments, the monica database, the radicale pair, the wger pair.
3. Secrets of the host `media`: the gluetun environment, the recyclarr config, the gamevault pair, the romm pair.
4. One secret crosses two hosts: the tailscale client secret names both `media` and `services` (agenix-rules.nix:20-23).

Public halves sit in the repository: `.ssh/agenix/hosts/<host>.pub` for the two hosts and `.ssh/agenix/users/<user>.pub` for the three users. That reader strips the trailing newline, so an empty recipient never reaches agenix (agenix-rules.nix:1-6).

Plan tokens are user secrets. Claude.nix decrypts the token to `~/.config/project/plans/zai.token` only when the encrypted file is committed, and a session reads it through the helper of the plan, never from a settings value (modules/programs/cli/claude.nix:132-140, 215-231).

Rules of the ssh layer:

1. `programs.ssh` runs with no default config, and it includes the decrypted `~/.ssh/genixis_config` (modules/programs/cli/ssh.nix:21-28).
2. A hand-managed `~/.ssh/known_hosts` stays first and writable, and the committed `forge_known_hosts` only supplements it (modules/programs/cli/ssh.nix:32-33).
3. One host key of the forge is public material, pinned under `[forgejo.local.jracon.xyz]:222` (modules/programs/cli/forge-known-hosts:1). A pin makes each client fail closed when the forge rotates its host key, and a rotation is a one-line commit of the new public key.
4. Login keys of the machines sit in `.ssh/authorized/<machine>.pub`, authorized for root and for each Home Manager user (common/ssh.nix:22-26). This repository holds two: `m2pro-mbp.pub` and `services-dev.pub`.
5. Each ssh daemon of a NixOS host accepts no password, and root logs in with a key only (common/ssh.nix:9-16).

Each host that loads the agenix module gets the agenix CLI as a system package (common/agenix.nix:22-24). A fish wrapper of agenix opens a secret in the editor pane of an ide window (modules/programs/cli/fish.nix:68-74).

## Why Is the Topic That Way?

Security Law of this topic, at its application (docs/design.md holds the map):

1. No secret in the clear. Every secret is an agenix file. No plaintext secret is committed, and no key is inlined in a module.
2. Two key channels, and no key crosses them. A host key decrypts only the secrets that its host consumes, and a user key decrypts the user secrets. A host that declares no system secret holds no host key. Separation keeps a host breach from the user secrets, and the reverse.
3. A token reaches a process only through a file that the process reads. No token sits in a command argument, where a process list shows it. No token sits in a plan file, because the store is readable by every user of the machine. Record 10 of docs/decisions.md states the origin of the token rule.
4. A forwarded socket is a trust grant. A grant reaches every process of the login that holds it, so each forward serves one connection and ends with it.
5. A secret that agenix cannot decrypt fails every secret of that user, so a missing key stops the whole home, not one service (modules/programs/cli/claude.nix:132-134).
6. Secrets topology is security spine: it stays human-authored with agent assist.

## What Does the Topic Enable?

Purpose of the topic: this repository carries its full secret inventory in the clear, as public keys and encrypted files, and each host opens only its own share. Security Law in the Why section of this file states the criterion.

## How Does a Reader Use and Change the Topic?

A procedure for a new secret crosses topics, so it lives in docs/runbook.md. An ssh route to the forge lives there too.

To find which hosts decrypt a secret, read the entry of the secret in agenix-rules.nix. To find which secrets a host decrypts, read the entries that name it.
