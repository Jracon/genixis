# The tmux server on Darwin

The launchd agent that starts and keeps the tmux server on Darwin, the environment of its panes, and the re-source of the server at each switch.

On Darwin, the launchd agent `launchd.agents.tmux` in `tmux.nix` starts the tmux server. Its label is `org.nix-community.home.tmux`. NixOS does not use this agent. docs/secrets.md gives the reason.

**The agent:**

- The agent runs `tmux -D`. The server stays in the foreground and uses the default socket, so the `tmux` function, `ide`, `project`, and `wezterm-attach` connect to it.
- `-D` also turns off the tmux option `exit-empty`. So the server keeps running when it has no sessions.
- `KeepAlive` and `RunAtLoad` are true. launchd starts the server at login. It also starts a new server after `tmux kill-server`.
- The server writes errors to `~/Library/Logs/tmux-server.log`.
- `newSession` is off on every platform. Home Manager writes `new-session -A -s 0` into the tmux configuration when the option is on. That line creates a stray session 0 at every server start, and it attaches each client that sources the configuration to that session (issue #163). So `tmux attach` fails when no session exists. Bare `tmux` still makes the session `main`.

**The re-source at each switch:**

- A tmux server reads its configuration once, at its start. The server outlives every rebuild, so the switch itself must load the new configuration into the running server.
- The activation hook `tmuxSourceConfig` in `tmux.nix` runs at every Home Manager switch, after `linkGeneration` links the new `tmux.conf`. When a server runs, the hook runs `tmux -N source-file -q` on the deployed configuration. The module runs on every platform, so the hook also runs on NixOS.
- `-N` stops the command from starting a server when none runs, the same guard as the `tmux` function. An error of the re-source never fails the switch.
- A re-source adds and replaces bindings. A binding that the new configuration removed stays until the next server restart, because a restart is the only removal and it ends every pane. `cmd_ide.go` documents the same limit.
- The configuration therefore writes full sets for `terminal-features` and `update-environment`, and each set keeps the stock defaults of tmux 3.8. A re-source is idempotent: two re-sources in a row leave both options with the same value after the second as after the first.

**The plist:**

- The agent names tmux through `home.profileDirectory`, not through a store path. So a tmux update does not change the plist.
- Home Manager stops an agent when its plist changes. This ends the server and every pane, and also a rebuild that runs in a pane.
- Do not start a rebuild from a tmux pane when the rebuild changes the plist. Use a WezTerm window without tmux.

**The environment of the panes:**

- launchd gives the server a minimal environment. So the agent sets `LANG`, `PATH`, and a soft limit of 61440 open files.
- The server itself uses this `PATH` for `run-shell`, hooks, and popups.
- `programs.tmux.shell` sets `default-shell` to fish. `default-command` stays empty, so each pane starts a login shell.
- Each pane runs fish, and fish loads the nix-darwin environment, the Home Manager session variables, and the direnv hook.
- The agent does not set `SSH_AUTH_SOCK`. The tmux option `update-environment` copies it from each client that attaches to a session. New panes of that session get it.

**No second server:**

- The fish function `tmux-server` runs `tmux -N start-server`. The `-N` flag stops a client from starting a server, so the command only tests for a server.
- Bare `tmux` and `ide` check for a server first (the fish function for `tmux`, the same test inside the `project` binary for `ide`). `ide close`, `ide pop`, and `ide reload` do not, because they run inside tmux. If no server runs, they print a `launchctl kickstart` command and fail. They have no fallback, because a server that a WezTerm starts loses the LAN.
- The `tmux` function adds `-N` to every other command. If the first argument is `-L` or `-S`, the function does not add it, because launchd does not own that socket.
- A script that calls the `tmux` executable skips the function. On Darwin, do not run `tmux new-session` in a script unless a server runs.
- If another server holds the socket, `tmux -D` exits with an error, and launchd tries again every 10 seconds. To end this loop, run `tmux kill-server` once.
