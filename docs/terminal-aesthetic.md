# terminal-aesthetic

The rules of the four terminal surfaces and of the frame around them.

Domain: what. Reader: a session that changes a surface, or a person who sets the look.
Code: modules/programs/cli/starship.nix, modules/programs/cli/tmux.nix, modules/programs/cli/fish.nix, modules/programs/cli/fastfetch.nix, modules/programs/gui/fonts.nix, modules/programs/gui/wezterm.nix.

## What is the topic?

One aesthetic binds four surfaces and the frame (issue 104): the prompt, the status bar, the greeting, the fetch panel, and the frame of the terminal window. The rules below are standing: the code follows them today, and the modules cite this file. The work that changes the surfaces continues in stage 4 of issue 166, after the owner approves each change.

## How is the topic realized?

The shared basis of every surface:

1. Four surfaces exist, and no surface is added to the terminal layer.
2. Each surface names ANSI colours. A fill names a background ANSI colour. No hex value lives outside the themes flake, and the terminal defines the ANSI palette, so each surface follows the active scheme (Terminal law item 7, docs/design-philosophy.md).
3. The signature colour of the palette marks the machine and the current tab: the os icon of the prompt and the current window of the bar (starship.nix:37-38, 109-121; tmux.nix:10).
4. The surfaces share the Nerd Font glyphs of Maple Mono NF. One glyph serves one concept. No emoji renders in a surface, because emoji run through a second font chain and break the alignment. A counter stays plain digits behind its glyph (starship.nix:19-32, 80-95; fastfetch.nix:14-27).
5. The prompt spans two lines, and every other surface spans one.
6. The greeting and the panel run no network call (fastfetch.nix:34-38).

The prompt (modules/programs/cli/starship.nix):

1. Line one holds the filled segments in this order: username, at, hostname, localip, directory, git branch, git status (starship.nix:57).
2. Line two holds the unfilled ones: the os icon, the language slot, the command duration, the character (starship.nix:57).
3. A join is a right arrow in the fill of the segment that follows it, so it hides with that segment. Outside a git repository, no green arrow dangles after the directory segment. The line opens with the round left cap on the fill of the first segment. It closes with the round right cap after the git status, in the green fill on the transparent background. Each cap rides its own segment, so outside a git repository the line ends flat at the directory (starship.nix:50-56, 88, 130).
4. The os icon shows alone, in the signature colour, with no fill (starship.nix:109-121).
5. The username, the at, the hostname, and the local IP form one identity segment on purple with bright white text. The username shows always, and root keeps the purple fill (starship.nix:96-108, 127-134).
6. The local IPv4 address shows always, with no ssh-only rule (starship.nix:102-108).
7. The directory shows the full path on cyan, and a read-only directory adds the marker ro (starship.nix:68-74).
8. The git branch and the git status form one segment on green. The branch name follows the branch glyph. Each state shows its glyph, and each count follows its glyph as plain digits (starship.nix:75-95).
9. The command duration shows from zero milliseconds, in milliseconds, with no fill (starship.nix:63-67).
10. The character is a plain angle bracket: bold green after success, bold red after failure (starship.nix:59-62).
11. The prompt is transient. The finished line of fish prints the character alone, in its status colour (fish.nix:342-373).
12. The prompt adds no clock, no battery, and no cloud context.

The status bar (modules/programs/cli/tmux.nix): the bar is a pure tab bar.

1. `status-left` and `status-right` stay empty, so the window list is the only content (tmux.nix:234-236). The session name sits in the tab title and the terminal title, so a status-left would repeat it.
2. The bar sits at the top (tmux.nix:200).
3. The plain window cells fill in black with white text, and they touch with no separator, so the list forms one band (tmux.nix:259-260). The band opens with the round left cap at window one, and it closes with the round right cap at the last window. Each edge cap draws in the fill of its own cell on the transparent bar (tmux.nix:17-20, 257, 259).
4. The current window nests into the band as one segment in the accent colour, reversed and bold, capped by the arrow bytes U+E0B2 and U+E0B0 inside the band. At an edge of the band, the round cap of that edge replaces the arrow, in the accent fill on the transparent bar (tmux.nix:11-20, 257).
5. The accent is the signature ANSI slot, so the bar follows the dark and the light scheme (tmux.nix:10).

The greeting and the panel (modules/programs/cli/fish.nix, fastfetch.nix):

1. The fish greeting text is off. The fastfetch panel is the greeting of every interactive shell, in every pane (fish.nix:338-341, 401-405; issue 297).
2. The panel runs after the tmux block, because an attach redraws the pane, and the shell that a detach returns to greets too (fish.nix:395-400). A dumb terminal and a host without fastfetch skip the panel (fish.nix:401-405).
3. The panel holds exactly these modules, in this order: title, separator, os, host, kernel, uptime, packages, shell, display, cpu, gpu, memory, disk, localip. A module that a host lacks is skipped, not replaced (fastfetch.nix:48-103).
4. The disk module reads the root filesystem only. The localip module shows IPv4, no IPv6, no loopback (fastfetch.nix:94-101).
5. Each key shows the glyph of its concept and its label, with the stock colours and the stock separator. The keys stay left-aligned in one fixed-width column (fastfetch.nix:14-47).
6. The OS logo stays at its side at its stock size with its own colours, because the logo is artwork of the system and no palette consumer.

The frame:

1. The terminal font is Maple Mono NF on every host, and the editors use the same font. The unhinted build keeps the infinite-arrow ligatures, and calt turns them on (fonts.nix:9-13; wezterm.nix:38-39).
2. The caret is a bar that blinks at 500 ms (wezterm.nix:44-45).
3. The window background holds an opacity of 0.95, with a macOS blur of 20 (wezterm.nix:46-47). The tab bar hides with one tab, and the scrollback holds 10000 lines (wezterm.nix:48-49).
4. The colour scheme follows the OS appearance from the themes flake (wezterm.nix:21-35).
5. Pane dimming is no part of the frame rules: the splits live in tmux, so the terminal never renders an unfocused pane of a split (issue 303).

## Why is the topic that way?

The owner settled the open points of issue 104 on 2026-11-10:

| Point | Decision |
| --- | --- |
| Does the prompt show the local IP with no ssh session? | Yes, always (starship.nix:106). |
| Does the status bar stay a pure tab bar? | Yes. Both sides hold no content (tmux.nix:234-236). |
| Do the window cells stand alone or form one band? | One band. The bright black fill left the plain text below legible contrast in both schemes, and the black fill with white text passes, so the band returned (tmux.nix:259). |
| Which symbol set do the surfaces share? | The Nerd Font glyphs of Maple Mono NF, one glyph for one concept, and no emoji (starship.nix:19-32). |

The same talk set the direction: the filled segments with arrow joins, the icons with counts, the os segment, the duration on line two, the transient prompt, the frame rules, and the panel keys with glyphs. The palette coverage of the toolchain is the work of issue 291, and the switch of the terminal emulator is the investigation of issue 290.

On 2026-11-11 the owner set four more points. The prompt line ends round, in the manner of the gruvbox-rainbow preset of starship, and the status band ends round in the same way. Root keeps the purple fill. The os icon leads line two. The branch name follows its glyph.

## What does the topic enable?

The end of the topic: one person reads the same surfaces on every host, in dark and in light, and the surfaces carry the identity of the machine with no noise between. Terminal law item 1 of docs/design-philosophy.md states the criterion of the terminal interface.

## How does a reader use and change the topic?

Change a surface:

1. Edit the module of the surface, in the code list above.
2. Keep the rules of this file, or change a rule here in the same commit.

Add a panel line: add the module with its glyph to fastfetch.nix, keep the fixed order, and keep the key width aligned with the widest key.

Add a prompt segment: add it to the format string with its join on the module that follows it, and name an ANSI slot, not a hex value.

## Sources

- Issue 104: the task and the settled points.
- Issue 166: stage 2 placed this document in the tree, and stage 4 applies it to the surfaces.
- Issue 297: the panel at every interactive shell start. Issue 290: the emulator switch investigation. Issue 291: the palette coverage. Issue 303: the pane dimming exclusion.
- docs/design-philosophy.md: the Terminal law.
