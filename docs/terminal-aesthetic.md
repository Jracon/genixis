# The terminal aesthetic

The rules of the four terminal surfaces and the terminal frame: the starship prompt, the tmux status bar, the fish greeting, the fastfetch panel, and the frame of the terminal. Issue #104 asks for these rules before any surface changes. The owner settled the open points and the aesthetic direction on 2026-11-10. The change to the surfaces lands in stage 4 of #166.

## The shared basis

1. Four surfaces exist: the starship prompt, the tmux status bar, the fish greeting, and the fastfetch panel. No surface is added to the terminal layer.
2. Each surface names ANSI colours. A fill names a background ANSI colour. No hex value lives outside the themes flake (see docs/flake.md). The terminal defines the ANSI palette, so each surface follows the active scheme. A colour name selects the hue of that name from the active palette, through the ANSI slot of the terminal.
3. The signature colour of the active palette marks the machine and the current tab: the os icon of the prompt and the current window of the bar.
4. The surfaces share the Nerd Font glyphs of `Maple Mono NF`. Use one glyph for one concept. Use no emoji, because emoji render through a second font chain and break the alignment. A counter stays plain digits, and it follows its glyph.
5. The prompt spans two lines. Every other surface spans one line.
6. The fish greeting and the fastfetch panel run no network call. Each module reads local state only.
7. The fastfetch panel runs once, in the home tab of the host window, and in no other pane. The home tab of #101 exists, so the rules for the panel apply now.
8. The rules also cover the terminal frame: the font, the ligatures, the caret, the pane dimming, and the window transparency.

## The starship prompt

The prompt tells identity, place, work, and readiness. The modules and their order:

1. Line one: `os`, `username`, the separator `@`, `hostname`, `localip`, `directory`, `git_branch`, `git_status`.
2. Line two: the language slot, `cmd_duration`, `character`.
3. The right edge holds no module.

Rules:

- Line one renders as filled segments, and line two renders without fills. The right-arrow glyph joins two segments, in the fill of the left segment on the fill of the right segment. Each join lives on the segment that follows it, so it hides with that segment. The join after the git status points onto the transparent background. A segment that no segment follows ends flat.
- The os segment shows the icon of the operating system alone, in the signature colour, with no fill.
- The username and the hostname are always visible. The username, the separator, the hostname, and the local IP form one segment. Its fill is purple and its text is bright white. For root, the username shows on a red fill. The separator, the hostname, and the local IP keep the purple fill, because starship styles no root variant for them.
- The prompt always shows the local IPv4 address of the host.
- The directory is one segment, with a cyan fill and bright white text. The path shows in full. A read-only directory adds the marker `ro`.
- The git branch and the git status form one segment, with a green fill and bright white text. Each state shows its glyph, and each count follows its glyph as plain digits.
- The language slot shows only the interpreters of the active environment. Python shows its glyph and its version, with no fill.
- The command duration shows after the language slot, with no fill.
- The character is `>` in bold green after a success, and in bold red after a failure.
- The prompt is transient. Before fish runs a command, it prints a final rendering of the prompt. The final rendering shows the character alone, in its status colour. Set `fish_transient_prompt` to 1, and wrap the prompt function of starship so it answers the final-rendering argument (fish 4.1 or later).
- The prompt adds no clock, no battery, and no cloud context.

## The tmux status bar

The status bar is a pure tab bar.

- Set no `status-left` and no `status-right`. The bar holds no clock, no host name, and no session name. The session name is pinned in the tab title of the host window and in the terminal title, so a status-left would repeat it. The window list is the content of the bar.
- The bar sits at the top.
- Each window shows its index, its name, and its flags, in one cell: `index:name flags`.
- The current window shows as a filled segment in the signature colour, with the same arrow glyphs as the prompt joins, and with bold text. The fill uses reverse video, so the text keeps the terminal background colour and stays legible in dark and light.
- Every other window shows in bright black on a transparent background. Two spaces sit between two cells, so each cell stands alone.

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
- Each key shows the glyph of its concept and its label. The keys keep the stock colours and the stock separator of fastfetch. Both name ANSI colours.
- The OS logo stays at its side, at its stock size. The logo keeps its own colours, because the logo is artwork of the OS and not a palette consumer.
- The panel defines no hex value.
- The panel runs no network call.

## The terminal frame

- The terminal font is `Maple Mono NF` on every host, and the editors use the same font. The ligatures of the font are on, through `calt`.
- The caret is a bar that blinks.
- An unfocused pane of a split renders dimmed.
- The window background is slightly transparent. On macOS, a blur sits behind it. A small padding holds between the text and the edge of the window.

## The settled points of #104

The owner settled the open points on 2026-11-10:

| Point | Decision |
| --- | --- |
| Does the prompt show the local IP when no ssh session runs? | Yes. The prompt always shows the local IP. |
| Does the status bar stay a pure tab bar, or does it get a status-left? | It stays a pure tab bar. Both sides hold no content. |
| Which symbol set do the surfaces share? | The Nerd Font glyphs of `Maple Mono NF`. One glyph for one concept, and no emoji. |

The same talk set the rest of the direction: filled segments with arrow joins, icons with counts, the os segment, the command duration on line two, the transient prompt, the frame rules, and the panel keys with glyphs. The palette coverage of the whole toolchain is the work of #291. The switch of the terminal emulator is the investigation of #290.

## Sources

- #104: the task and the open points.
- #166: stage 2 places this document in the tree. Stage 4 applies it to the surfaces.
- #290: the investigation of a switch of the terminal emulator.
- #291: the palette coverage of the terminal toolchain.
- docs/design-philosophy.md: the terminal law and the colour rule.
- The starship preset catalog: the reference of the segment vocabulary.
- The fish 4.1 release notes: the transient prompt mechanism.
- The current surfaces: `modules/programs/cli/starship.nix`, `modules/programs/cli/tmux.nix`, `modules/programs/cli/fish.nix`, and `modules/programs/cli/fastfetch.nix`.
