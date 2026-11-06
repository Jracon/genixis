# The terminal aesthetic

The rules of the four terminal surfaces: the starship prompt, the tmux status bar, the fish greeting, and the fastfetch panel. Issue #104 asks for these rules before any surface changes. The change to the surfaces lands in stage 4 of #166, after the owner approves this document.

Each answer to an open point of #104 carries the marker **proposal**. The owner approves or edits each proposal in the review of this document. No surface module changes before that approval.

## The shared basis

1. Four surfaces exist: the starship prompt, the tmux status bar, the fish greeting, and the fastfetch panel. No surface is added to the terminal layer.
2. Each surface names ANSI colours. No hex value lives outside the themes flake (see docs/flake.md). The terminal defines the ANSI palette, so each surface follows the active scheme.
3. The signature colour of the active palette marks the current thing: the current tab in the status bar.
4. **Proposal** for the symbol set: the surfaces share the Nerd Font glyphs of the configured terminal font, `FiraCode Nerd Font`. Use one glyph for one concept. Use no emoji, because emoji render through a second font chain and break the alignment. Keep plain ASCII words for counters and states, for example the git counters of the prompt.
5. The prompt spans two lines. Every other surface spans one line.
6. The fish greeting and the fastfetch panel run no network call. Each module reads local state only.
7. The fastfetch panel runs once, in the home tab of the host window, and in no other pane. The home tab of #101 exists, so the rules for the panel apply now.

## The starship prompt

The prompt tells identity, place, work, and readiness. The modules and their order:

1. Line one: `username`, the separator `@`, `hostname`, `localip`, `directory`, `git_branch`, `git_status`.
2. Line two: the language slot, then `character`.
3. The right edge holds `cmd_duration`.

Rules:

- The username is always visible. Root shows in bright red, and every other user shows in bright white.
- The hostname is always visible, in purple.
- **Proposal** for the local IP: the prompt shows the local IP only inside an ssh session. Set `localip.ssh_only = true`. The IP of the local host adds width to every prompt and changes no decision. In an ssh session, the IP tells the network of the remote host when the hostname alone stays unclear. The fastfetch panel of the home tab holds the local IP of the machine.
- The directory shows the full path. A read-only directory adds the marker `ro`.
- The git status shows counts in ASCII words only: ahead, behind, staged, renamed, deleted, conflicted.
- The language slot shows only the interpreters of the active environment. Python shows its Nerd Font glyph and its version.
- The character is `>` in bold green after success, and in bold red after a failure.
- The prompt adds no clock, no battery, and no cloud context.

## The tmux status bar

The status bar is a pure tab bar.

- **Proposal** for the shape: the bar stays a pure tab bar. Set no `status-left` and no `status-right`. The session name is already pinned in the tab title of the host window and in the terminal title, so a status-left would repeat it. The window list is the content of the bar.
- The bar sits at the top.
- Each window shows its index, its name, and its flags, in one cell: `index:name flags`.
- The current window shows in the signature colour of the palette, reversed and bold.
- Every other window shows in bright black on a transparent background.
- The bar holds no clock, no host name, and no session name.

## The fish greeting

The fish greeting is empty. Set `fish_greeting` to an empty value. The fastfetch panel of the home tab greets once, so a second greeting in every shell adds noise. The greeting runs no command and no network call.

## The fastfetch panel

The panel answers: what machine is this, what does it run, and how full is it. The modules and their order:

1. `title` — the login and the host.
2. `separator` — one rule under the title.
3. `os` — the system and its version.
4. `host` — the model of the machine.
5. `kernel` — the running kernel.
6. `uptime` — the time since the last boot.
7. `packages` — the count of the system packages.
8. `shell` — the login shell.
9. `display` — the displays and their scale.
10. `cpu` — the processor and its load.
11. `gpu` — the graphics units.
12. `memory` — the used and the total memory.
13. `disk` — the root file system only.
14. `localip` — the IPv4 addresses of the machine.

Rules:

- The panel holds exactly these modules, in this order. A module that a host lacks is skipped, not replaced.
- The OS logo stays at its side. The logo keeps its own colours, because the logo is artwork of the OS and not a palette consumer.
- The keys name ANSI colours. The panel defines no hex value.
- The panel runs no network call.

## The open points of #104

| Open point | Proposal | Reason |
| --- | --- | --- |
| Does the prompt show the local IP when no ssh session runs? | No. The prompt shows the IP only inside an ssh session. | The local IP adds width to every prompt and changes no decision. The panel of the home tab holds the local IP once. |
| Does the status bar stay a pure tab bar, or does it get a status-left? | It stays a pure tab bar. | The session name is pinned in the tab title and the terminal title. A status-left would repeat known text. |
| Which symbol set do the surfaces share? | The Nerd Font glyphs of `FiraCode Nerd Font`. One glyph for one concept, and no emoji. | The font is installed on every host. Emoji render through a second font chain and break the alignment. |

## Sources

- #104: the task and the open points.
- #166: stage 2 places this document in the tree; stage 4 applies it to the surfaces.
- docs/design-philosophy.md: the terminal law and the colour rule.
- The current surfaces: `modules/programs/cli/starship.nix`, `modules/programs/cli/tmux.nix`, `modules/programs/cli/fish.nix`, and `modules/programs/cli/fastfetch.nix`.
