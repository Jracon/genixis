# terminal-aesthetic

Rules of the four terminal surfaces and of the frame around them.

## What Is the Topic?

One aesthetic binds four surfaces and the frame (issue 104): the prompt, the status bar, the greeting, the fetch panel, and the frame of the terminal window. Rules below are standing: the code follows them today, and the modules cite this file. Work that changes the surfaces continues in stage 4 of issue 166, after the owner approves each change.

## How Is the Topic Realized?

Shared basis of every surface:

1. Four surfaces exist, and no surface is added to the terminal layer.
2. Each surface names ANSI colours. A fill names a background ANSI colour. No literal hex value appears outside the themes flake, and a terminal defines the ANSI palette, so each surface follows the active scheme.
3. Signature colour of the palette marks the machine and the current tab: the os icon of the prompt and the current window of the bar (starship.nix:37-38, 109-121; tmux.nix:10).
4. Surfaces share the Nerd Font glyphs of Maple Mono NF. One glyph serves one concept. No emoji renders in a surface, because emoji run through a second font chain and break the alignment. A counter stays plain digits behind its glyph (starship.nix:19-32, 80-95; fastfetch.nix:14-27).
5. One prompt spans two lines, and every other surface spans one.
6. Greeting and panel run no network call (fastfetch.nix:34-38).

Prompt (modules/programs/cli/starship.nix):

1. Line one holds the filled segments in this order: username, at, hostname, localip, directory, git branch, git status (starship.nix:57).
2. Line two holds the unfilled ones: the os icon, the language slot, the command duration, the character (starship.nix:57).
3. A join is a right arrow in the fill of the segment that follows it, so it hides with that segment. Outside a git repository, no green arrow dangles after the directory segment. A round left cap opens the line, on the fill of the first segment. A round right cap closes it after the git status, in the green fill on the transparent background. Each cap rides its own segment, so outside a git repository the line ends flat at the directory (starship.nix:50-56, 88, 130).
4. Os icon shows alone, in the signature colour, with no fill (starship.nix:109-121).
5. Username, at, hostname, and local IP form one identity segment on purple with bright white text. Username shows always, and root keeps the purple fill (starship.nix:96-108, 127-134).
6. Local IPv4 address shows always, with no ssh-only rule (starship.nix:102-108).
7. Directory shows the full path on cyan, and a read-only directory adds the marker ro (starship.nix:68-74).
8. Git branch and git status form one segment on green. Branch name follows the branch glyph. Each state shows its glyph, and each count follows its glyph as plain digits (starship.nix:75-95).
9. Command duration shows from zero milliseconds, in milliseconds, with no fill (starship.nix:63-67).
10. Character is a plain angle bracket: bold green after success, bold red after failure (starship.nix:59-62).
11. Prompt is transient. A finished line of fish prints the character alone, in its status colour (fish.nix:342-373).
12. Prompt adds no clock, no battery, and no cloud context.

Status bar (modules/programs/cli/tmux.nix): the bar is a pure tab bar.

1. `status-left` and `status-right` stay empty, so the window list is the only content (tmux.nix:234-236). Session name sits in the tab title and the terminal title, so a status-left would repeat it.
2. Bar sits at the top (tmux.nix:200).
3. Plain window cells fill in black with white text, and they touch with no separator, so the list forms one band (tmux.nix:259-260). Band opens with the round left cap at window one, and it closes with the round right cap at the last window. Each edge cap draws in the fill of its own cell on the transparent bar (tmux.nix:17-20, 257, 259).
4. Current window nests into the band as one segment in the accent colour, reversed and bold, capped by the arrow bytes U+E0B2 and U+E0B0 inside the band. At an edge of the band, the round cap of that edge replaces the arrow, in the accent fill on the transparent bar (tmux.nix:11-20, 257).
5. Accent is the signature ANSI slot, so the bar follows the dark and the light scheme (tmux.nix:10).

Greeting and panel (modules/programs/cli/fish.nix, fastfetch.nix):

1. Fish greeting text is off. Fastfetch panel is the greeting of every interactive shell, in every pane (fish.nix:338-341, 401-405; issue 297).
2. Panel runs after the tmux block, because an attach redraws the pane, and the shell that a detach returns to greets too (fish.nix:395-400). A dumb terminal and a host without fastfetch skip the panel (fish.nix:401-405).
3. Panel holds exactly these modules, in this order: title, separator, os, host, kernel, uptime, packages, shell, display, cpu, gpu, memory, disk, localip. A module that a host lacks is skipped, not replaced (fastfetch.nix:48-103).
4. Disk module reads the root filesystem only. Localip module shows IPv4, no IPv6, no loopback (fastfetch.nix:94-101).
5. Each key shows the glyph of its concept and its label, with the stock colours and the stock separator. Keys stay left-aligned in one fixed-width column (fastfetch.nix:14-47).
6. OS logo stays at its side at its stock size with its own colours, because the logo is artwork of the system and no palette consumer.

Frame:

1. Terminal font is Maple Mono NF on every host, and the editors use the same font. An unhinted build keeps the infinite-arrow ligatures, and calt turns them on (fonts.nix:9-13; wezterm.nix:38-39).
2. Caret is a bar that blinks at 500 ms (wezterm.nix:44-45).
3. Window background holds an opacity of 0.95, with a macOS blur of 20 (wezterm.nix:46-47). Its tab bar hides with one tab, and the scrollback holds 10000 lines (wezterm.nix:48-49).
4. Colour scheme follows the OS appearance from the themes flake (wezterm.nix:21-35).
5. Pane dimming is no part of the frame rules: the splits live in tmux, so the terminal never renders an unfocused pane of a split (issue 303).

## Why Is the Topic That Way?

Terminal Law of this topic, at its application (docs/design.md holds the map):

1. Colour lives in the themes flake. A literal hex value appears there only. Every tool in this repository names ANSI colours and follows the active scheme.

On 2026-11-10, the owner settled the open points of issue 104:

| Point | Decision |
| --- | --- |
| Does the prompt show the local IP with no ssh session? | Yes, always (starship.nix:106). |
| Does the status bar stay a pure tab bar? | Yes. Both sides hold no content (tmux.nix:234-236). |
| Do the window cells stand alone or form one band? | One band. A bright black fill left the plain text below legible contrast in both schemes, and the black fill with white text passes, so the band returned (tmux.nix:259). |
| Which symbol set do the surfaces share? | Nerd Font glyphs of Maple Mono NF, one glyph for one concept, and no emoji (starship.nix:19-32). |

That talk also set the direction: the filled segments with arrow joins, the icons with counts, the os segment, the duration on line two, the transient prompt, the frame rules, and the panel keys with glyphs. Palette coverage of the toolchain is the work of issue 291, and the switch of the terminal emulator is the investigation of issue 290.

On 2026-11-11 the owner set four more points. Prompt line ends round, in the manner of the gruvbox-rainbow preset of starship, and the status band ends round in the same way. Root keeps the purple fill. Os icon leads line two. Branch name follows its glyph.

## What Does the Topic Enable?

Purpose of the topic: one person reads the same surfaces on every host, in dark and in light, and the surfaces carry the identity of the machine with no noise between. Text as the interface, in docs/cli.md, states the criterion.

## How Does a Reader Use and Change the Topic?

Change a surface:

1. Edit the module of the surface.
2. Keep the rules of this file, or change a rule here in the same commit.

Add a panel line: add the module with its glyph to fastfetch.nix, keep the fixed order, and keep the key width aligned with the widest key.

Add a prompt segment: add it to the format string with its join on the module that follows it, and name an ANSI slot, not a hex value.
