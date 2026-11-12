# tmux-darwin

Tmux server on Darwin: one server, started by launchd, and the clients that must never start a second one.

## What Is the Topic?

On Darwin, launchd owns the tmux server. A client never starts one: the fish function `tmux` and each activation hook run with `-N`, which makes a client fail when no server answers (modules/programs/cli/fish.nix:17-21; modules/programs/cli/tmux.nix:56-59).

## How Is the Topic Realized?

Launchd agent (modules/programs/cli/tmux.nix:71-100):

1. Program runs `tmux -D`, the foreground server, with the fish of the profile as the default shell (tmux.nix:92-95, 281).
2. `KeepAlive` and `RunAtLoad` keep the server up from login (tmux.nix:90, 96). `ProcessType` is Interactive (tmux.nix:91).
3. Soft limit of open files rises to 61440 (tmux.nix:97).
4. Environment names the locale, an explicit path, and the log file `~/Library/Logs/tmux-server.log` (tmux.nix:76-98).

Guards:

1. Fish function `tmux` attaches with `-N` after it probes the server, and the probe prints the restart path on failure: `launchctl kickstart gui/<uid>/<label>`, and the log file (fish.nix:246-257, 273-277).
2. An activation hook of a switch re-sources the configuration with `tmux -N source-file -q`, and a failure costs nothing (tmux.nix:56-59, 63-67). A re-source adds and replaces bindings; a binding that the new configuration removed stays until the next server restart, because a restart ends every pane. A configuration therefore writes full sets for `terminal-features` and `update-environment` (tmux.nix:113-124; issue 191).
3. A popup starts in the working directory of the tmux server, not of the caller. Every popup command carries `-d` with the working directory of the pane (tmux.nix:206-211).
4. A script that calls the tmux executable skips the fish function, so on Darwin no script runs `tmux new-session` unless a server runs. A test or probe server needs its own socket: pass `-L` with a name on every command of that server. A shell inside tmux exports `TMUX`, and tmux prefers the socket of that variable, so a `kill-server` that aims at a temporary directory can end the server of the user (fish.nix:246-257).
5. When another server holds the socket, `tmux -D` exits with an error and launchd tries again every ten seconds. One `tmux kill-server` ends the loop.

## Why Is the Topic That Way?

1. A server that a WezTerm starts loses the LAN when that WezTerm quits, because the macOS Local Network grant follows the process chain of the server. A launchd server keeps the grant (fish.nix:17-18).
2. Its grant also follows the code signature, which changes at each Nix build, so no fix inside this repository holds it for every chain (workaround record in docs/runbook.md).
3. An activation hook reaches only the socket that the switch environment resolves. A switch from a context without `TMUX_TMPDIR` silently misses the server (the review of pull request 238, verified on services).

## What Does the Topic Enable?

Purpose of the topic: one tmux server on the Mac, up from login, reachable from every process chain, with no second server and no split socket. Text as the interface, in docs/cli.md, states the criterion.

## How Does a Reader Use and Change the Topic?

Attach with the fish function `tmux`. Never run bare `tmux` by hand on Darwin: without `-N` it starts a second server.

When no server answers, run `launchctl kickstart gui/<uid>/<label>` with the label of the agent, then read `~/Library/Logs/tmux-server.log`.

Change the server settings: edit the agent block in modules/programs/cli/tmux.nix, and rebuild the machine.
