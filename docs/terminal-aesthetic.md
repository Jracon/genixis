# terminal-aesthetic

The rules of the four terminal surfaces and of the frame around them.

Domain: what. Reader: a session that changes a surface, or a person who sets the look.
Code: modules/programs/cli/starship.nix, modules/programs/cli/tmux.nix, modules/programs/cli/fish.nix, modules/programs/cli/fastfetch.nix, modules/programs/gui/fonts.nix, modules/programs/gui/wezterm.nix.

## What is the topic?

One aesthetic binds four surfaces and the frame (issue 104):

1. The prompt: starship, two lines.
2. The status bar: a pure tab bar in tmux.
3. The greeting: the fastfetch panel, no fish greeting text.
4. The fetch panel: the fastfetch module list.
5. The frame: the font, the cursor, and the window glass of WezTerm.

The rules settled three open points of issue 104: the prompt shows the local IP also with no ssh session (starship.nix:94-100); the status bar carries no status-left, and the window list is its only content (tmux.nix:230-232); the surfaces share one symbol set of private-use Nerd Font bytes (starship.nix:16-26; fastfetch.nix:14-27).

## How is the topic realized?

The prompt (modules/programs/cli/starship.nix):

1. Line one holds the filled segments, and line two holds the unfilled ones (starship.nix:44-49). The order: os, username, at, hostname, localip, directory, git branch, git status, then python, command duration, and the character (starship.nix:49).
2. A join lives on the module that follows it, so it hides with that module. Outside a git repository, no green arrow dangles after the directory segment (starship.nix:45-48).
3. The character is a plain angle bracket: bold green after success, bold red after failure (starship.nix:51-54).
4. The command duration shows from zero milliseconds, in milliseconds (starship.nix:55-59).
5. The directory never truncates, and a read-only directory gains the suffix ro (starship.nix:60-66).
6. The git status uses one glyph for one concept, with counts as plain digits behind the glyph (starship.nix:72-87).
7. The hostname and the local IP show always, not only over ssh (starship.nix:88-100).
8. The os symbol rides in the signature colour, inline in the format string, because the style key of the os module applies nothing in starship 1.27 (starship.nix:101-113).
9. The username shows always, and root gains a red segment (starship.nix:119-124).
10. The transient prompt of fish 4.1 keeps the full prompt on the working line and prints only the character on a finished line (modules/programs/cli/fish.nix:342-373).

The status bar (modules/programs/cli/tmux.nix):

1. `status-left` and `status-right` stay empty, so the window list is the only content (tmux.nix:230-232).
2. The current window cell renders in the accent colour, reversed and bold, capped by the private-use bytes U+E0B2 on the left and U+E0B0 on the right (tmux.nix:12-16, 251).
3. The other window cells render white on black, with no separator between them (tmux.nix:253-254).
4. The accent is the signature ANSI slot of the palette, so the bar follows the dark and the light scheme (tmux.nix:10).

The greeting and the panel (modules/programs/cli/fish.nix, fastfetch.nix):

1. The fish greeting text is off. The fastfetch panel is the greeting of every interactive shell (fish.nix:338-341, 401-405).
2. The panel runs after the tmux block, because an attach redraws the pane, and the shell that a detach returns to greets too (fish.nix:395-400).
3. A dumb terminal and a host without fastfetch skip the panel (fish.nix:401-405).
4. The panel holds one aligned value column of key width 13 (fastfetch.nix:47), with these modules in order: title, separator, os, host, kernel, uptime, packages, shell, display, cpu, gpu, memory, disk, localip (fastfetch.nix:48-103).
5. The disk module reads the root filesystem only, and the localip module shows IPv4, no IPv6, no loopback (fastfetch.nix:94-101).
6. Each key is a Nerd Font glyph with a label, and the panel uses the stock colours (fastfetch.nix:14-38).

The frame:

1. The font is Maple Mono NF, unhinted, because the hinted build drops the infinite-arrow ligatures (modules/programs/gui/fonts.nix:9-13).
2. WezTerm turns the calt feature on for the ligatures (modules/programs/gui/wezterm.nix:39).
3. The cursor is a blinking bar at 500 ms (wezterm.nix:44-45).
4. The window background holds an opacity of 0.95, with a macOS blur of 20 (wezterm.nix:46-47). The tab bar hides with one tab, and the scrollback holds 10000 lines (wezterm.nix:48-49).
5. The colour scheme follows the OS appearance, dark or light, from the themes flake (wezterm.nix:21-35).

## Why is the topic that way?

1. The rules landed before the changes to the surfaces, so each surface cites one document (issue 104).
2. Colour lives in the themes flake. Each surface names an ANSI slot, and no hex value lives outside the flake (Terminal law item 7, docs/design-philosophy.md). The accent of the bar and the signature colour of the prompt both read the palette (tmux.nix:10; starship.nix:31).
3. The greeting and the panel run no network call (issue 104, acceptance; fastfetch.nix:34-38).
4. The work on the surfaces continues in stage 4 of issue 166, after the owner approves each change. The rules above are standing, and the code follows them today.

## What does the topic enable?

The end of the topic: one person reads the same surfaces on every host, in dark and in light, and the surfaces carry the identity of the machine with no noise between. Terminal law item 1 of docs/design-philosophy.md states the criterion of the terminal interface.

## How does a reader use and change the topic?

Change a surface:

1. Edit the module of the surface, in the code list above.
2. Keep the rules of this file, or change a rule here in the same commit.

Add a panel line: add the module with its glyph to fastfetch.nix, and keep the key width aligned with the widest key.

Add a prompt segment: add it to the format string with its join on the module that follows it, and name an ANSI slot, not a hex value.
