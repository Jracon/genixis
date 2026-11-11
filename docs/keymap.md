# keymap

The bindings of the modifier layers across the terminal surfaces, with the conflict check of each key.

Domain: what. Reader: a session that adds a binding, or a person who asks which chord does what.
Code: modules/programs/gui/wezterm.nix, modules/programs/cli/tmux.nix, modules/programs/cli/fish.nix, modules/programs/cli/neovim/lua/genixis/, modules/programs/cli/keymap-table.awk.

One modifier per layer. Meta operates the OS and the terminal application, Option operates tmux, and Ctrl operates the tool in the pane. A key with no modifier, or with Shift only, goes to the tool in the pane. Terminal law item 2 of docs/design-philosophy.md states the rule.

| Layer | Key | Action | Conflict check |
| --- | --- | --- | --- |
| Meta | Super+T | Open a new tab. In a delegated login window, the new tab runs a remote login. | WezTerm only. No Meta chord reaches a pane (wezterm.nix:131-132). |
| Meta | Ctrl+Shift+T | Open a new tab, the same action as Super+T. | WezTerm holds the chord. tmux binds no Ctrl+Shift+T (wezterm.nix:131). |
| Option | 1 to 9, 0 | Select the window of the number. 0 selects the tenth window. | tmux only. No pane reads window numbers (tmux.nix:148-150, 185). |
| Option | Down, Left, Right, Up | Select the pane in that direction. | tmux only. Word movement moved off Option to Shift (tmux.nix:178-181; fish.nix:381-385). |
| Option | Tab | Select the next window. | tmux. Ctrl+Tab is the ide tab chord, a different key (tmux.nix:191). |
| Option | Shift+Tab | Select the previous window. | tmux (tmux.nix:192). |
| Option | t | Open a new window, in the working directory of the pane. | tmux. fish keeps its alt-t, transpose-words, outside tmux; nvim holds no M-t map, and the yazi keymap adds no t chord (tmux.nix:194-196). |
| Option | w | Kill the window. tmux asks no confirmation. | tmux. The bare key never reaches a pane (tmux.nix:111, 201). |
| Option | Enter | A yazi pane receives M-Enter. Any other pane receives Shift+Enter. | tmux rewrites the chord. The kitty protocol limit applies (tmux.nix:157). |
| Option | k | Open the keymap popup. The popup renders this file. | tmux. nvim holds no M-k map (tmux.nix:40-43). |
| Option | g | Open the lazygit popup in the working directory of the pane. | tmux (tmux.nix:52-55). |
| Option | D | Open the lazydocker popup. | tmux. The key takes Shift, because Option+d stays the fish kill-word (tmux.nix:45-50). |
| Ctrl | 0 to 9 | Inside an ide window, select the ide tab of the number. Outside an ide window, send the chord to the pane. | tmux routes. nvim maps Ctrl+0 to Ctrl+9 to the same tabs (tmux.nix:145-147; keymaps.lua:63-67). |
| Ctrl | Tab | Inside an ide window, select the next ide tab. Outside, send the chord to the pane. | tmux routes. The released WezTerm default lets the chord reach tmux (tmux.nix:153; wezterm.nix:125-129). |
| Ctrl | Shift+Tab | Inside an ide window, select the previous ide tab. Outside, send the chord to the pane. | same path (tmux.nix:152). |
| Ctrl | Shift+F | Search the contents of all files in the working directory. An nvim pane receives the chord as M-F. Any other pane receives Ctrl+F. | tmux rewrites the chord, because a pane cannot read Shift on a control key without the kitty protocol (tmux.nix:163; editing.lua:52-59). |
| Ctrl | Shift+H | Replace text in the open file. An nvim pane receives the chord as M-H. Any other pane receives Ctrl+H. | the same limit (tmux.nix:168; editing.lua:96-97). |
| Ctrl | Shift+P | Open the command palette. An nvim pane receives the chord as M-P. Any other pane receives Ctrl+P. | the same limit. WezTerm releases its own Ctrl+Shift+P default (tmux.nix:172; editing.lua:99-104; wezterm.nix:125-129). |
| Ctrl | D | Delete one character forward. Inside tmux the shell never exits on it. | fish inside tmux. WezTerm types Enter and Ctrl+D when it closes a pane (fish.nix:375-379). |
| Ctrl | F | In nvim, search the open file. In fish, move one character forward. | The tool in the pane owns the key. nvim shadows its page-forward default (editing.lua:48-51). |
| None | Shift+Left, Shift+Right | Move one word back or forward. | fish. The chord carries the word movement that Option+arrows held before tmux took them (fish.nix:381-385). |
| Tool | Ctrl+S | In nvim, write the file, and format it on save. | nvim only. fish keeps its Ctrl+S. The insert-mode map replaces the signature-help default, because blink.cmp shows the window by itself (keymaps.lua:9-16; editing.lua:18-33; issue 195). |
| Tool | Ctrl+T | In nvim, open a new editor tab with an empty buffer. | nvim only. WezTerm releases the legacy alias of the key, so it reaches the pane (keymaps.lua:74-80; wezterm.nix:120; issue 195). |
| Tool | Ctrl+W | In nvim, close the file and keep nvim open. In the file tree, do nothing. | nvim only. The map shadows the window-command prefix, and :wincmd still moves in a split (keymaps.lua:56-59). A buffer-local no-op holds the map inert in the tree buffer, so the tree closes only through the toggle, q, and leader x (tree.lua:154-165; issues 165 and 325). |
| Tool | Ctrl+Y, Ctrl+N, Ctrl+P, Ctrl+Space, in insert mode | In nvim, drive the completion: accept, next, previous, open. | The blink.cmp preset, below the insert-mode completion of nvim (editing.lua:5-8). |
| Tool | gd, gD, Shift+F12, Ctrl+click | In nvim, jump to the definition, list the definitions, list the references, jump with the mouse. | Buffer-local maps of LspAttach beside the nvim built-ins (lsp.lua:71-98; keymaps.lua:1-2; issue 165). |
| Tool | Backslash, the leader | The first key of every nvim chord below. The spacebar lost as the leader. | A key with no modifier, so the tool owns it (options.lua:3-5; issue 165). |
| Tool | Leader d, q, w, x | In nvim, read the diagnostics of the line, collect them in the loclist, write the file, close the file. | Leader chords, so no other tool sees them (keymaps.lua:5-8, 55-59). |
| Tool | Leader f, then a key | In nvim, the find group: diagnostics, files, grep, help, keymaps, resume, symbols, and the replace across the project. | The pickers of fzf-lua and grug-far (editing.lua:60-83). |
| Tool | Leader f, then q | In nvim, the unified search of the fast tier over rg, qmd, and semble. | The editor side of the search command (search.lua:1, 294; issue 189). |
| Tool | Tab, Shift+Tab, in the grug-far panel | Step through the fields of the panel, forward and back. The steps cycle at each end, and no field is skipped. | The plugin maps the bare key inside the buffer of the panel, in insert and normal mode. A bare key with no modifier belongs to the tool (editing.lua:70-80; issue 316). |
| Tool | Leader t, then t or f | In nvim, toggle the file tree of every editor tab, or focus it on the current file. | The toggle state is shared by every tab (tree.lua:1-5, 244-245; issues 196 and 234). |
| Tool | H, in the tree window | In the file tree, hide the dotfiles and the gitignored rows, and show them again. | The neo-tree default of the key, kept by the config (tree.lua:63-70; issue 196). |
| Tool | Leader e, E | In nvim, open yazi in the working directory, or at the current file. | The yazi command of nvim (editing.lua:110-111). |
| Tool | Leader v, then a key | In nvim, the review group: diff the file against the base, lazygit, hunk, the file list, tuicr. | The review flow of the branch (review.lua:125-129). |
| Tool | Leader r, then a key | In nvim, the test group: file, last, output, nearest, summary, stop. | neotest with the go adapter (test.lua:18-33). |
| Tool | Leader D, then a key | In nvim, the debug group: breakpoint, continue, into, out, over, the debug UI. | nvim-dap with dap-go (dap.lua:23-28). |
| Prefix | " | Split the window vertically, in the working directory of the pane. | The stock prefix stays for rare commands. The Option layer holds the frequent ones (tmux.nix:135, 210-211). |
| Prefix | % | Split the window horizontally, in the working directory of the pane. | same rule (tmux.nix:136). |
| Prefix | c | Open a new window, in the working directory of the pane. | same rule (tmux.nix:137). |
| Mouse | Middle click on the status bar | Kill the window under the pointer. | tmux (tmux.nix:205). |
| Mouse | Double click on the status bar | Rename the window under the pointer. | tmux (tmux.nix:206). |
| Mouse | Double click past the last window | Open a new window. | tmux (tmux.nix:207). |
| Mouse | Option and drag in a pane | Select a rectangle. | tmux copy mode (tmux.nix:221). |
| Mouse | Wheel in copy mode | Scroll ten lines per step. | tmux (tmux.nix:224-225). |

## How is the topic realized?

Each surface holds its own bindings:

1. WezTerm: the new-tab chords, and the release of its Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+Shift+F, Ctrl+Shift+P, and Ctrl+T defaults, so the chords reach tmux (wezterm.nix:125-132).
2. tmux: the Option layer through `bind -n`, the routed Ctrl+Shift chords, the prefix table, the mouse bindings, and the popups (modules/programs/cli/tmux.nix).
3. fish: the Ctrl+D and Shift+arrows bindings inside the pane (modules/programs/cli/fish.nix:374-385).
4. nvim: the receiver maps of the routed chords, inside the lua modules (modules/programs/cli/neovim/lua/genixis/).

The transport of a chord runs through this chain:

1. WezTerm encodes keys with CSI-u, and it sends the left Alt key raw and the right Alt key composed (wezterm.nix:20, 51-52).
2. tmux turns extended-keys on and reads the terminal features `extkeys` (tmux.nix:114, 128).
3. A pane cannot read Shift on a control key without the kitty protocol, so tmux rewrites the three Ctrl+Shift chords to their Meta forms for nvim (tmux.nix:159-171; editing.lua:52-59). The kitty protocol cannot run in this stack: WezTerm carries it only behind its own option, which the CSI-u encoding replaces, and tmux forwards a CSI-u event but implements no push, pop, or query of the protocol. The editor therefore cannot underline text while Ctrl is held, and a terminal sends Ctrl+H and Backspace as the same byte, which is why the replace chord takes Shift (editing.lua:76-77; issues 193 and 195).
4. The Shift+Enter row shows the same limit: tmux rewrites it for a yazi pane and passes it through to any other pane (tmux.nix:153).
5. A session tab of a remote login adds ssh and the tmux server of the remote host to the chain. ssh copies TERM unchanged and passes each byte unchanged, so it drops no chord (issue 158).
6. A tmux server loads its configuration once, at its start. The activation hook of each switch re-sources the configuration into the running server, and a binding that a new configuration removed stays until the next server restart (tmux.nix:56-67; issue 191).
7. On desktop, the window manager owns Meta, so WezTerm keeps its window keys at Ctrl+Shift there (issue 142).

The popup: tmux renders this file at build time with keymap-table.awk into plain text, and Option+K shows the result in less (tmux.nix:23-28, 36-39; keymap-table.awk:1-5). The popup shows the title, the layer sentence, and the layer, key, and action of each row. The conflict-check column stays in this file only. The build writes the rendered table into the Nix store of the host that runs the server, so every host shows the table of its own build, and a session tab shows the table of the remote host.

## Why is the topic that way?

1. One modifier per layer, and no Meta key reaches a pane, so each surface keeps a closed set of chords (Terminal law items 2 and 3, docs/design-philosophy.md; issue 145 set the boundary at tmux.nix:135).
2. Each layer keeps one universal chord that works on every host and through every remote hop, so no layer strands the user (Terminal law item 4, docs/design-philosophy.md; issue 158).
3. The new-tab key serves the window it is pressed in, so a window of a remote login opens tabs on that host (issue 142; wezterm.nix:88).
4. The re-derivation of the map set the leader, the close chords, and the window keys of the Option layer. The spacebar lost as the leader, because the leader must shadow nothing (issue 165; options.lua:3-5).
5. The editor chords came next: Ctrl+S writes the file, Ctrl+T opens an empty tab, and the palette and replace chords take the Meta form through the rewrite (issue 195; keymaps.lua:9-16, 74-80; editing.lua:76-96).
6. The project-wide search chord and the format cap of a quarter second landed with the picker work (issue 193; editing.lua:21, 52-59).
7. The file tree lives in a left split with the toggle state shared by every editor tab (issues 196 and 234; tree.lua:1-5).
8. The re-source at each switch writes full sets, never appended lists, because a re-source runs again and again (issue 191; tmux.nix:113-124).

The reopening events: the underline hint and the replace chord reopen when the kitty keyboard protocol runs end to end in this stack. The transport section records why it cannot run today. For the other decisions, no reopening event is known.

## What does the topic enable?

The end of the keymap: one person drives the OS, the terminal, and the tool in the pane with one hand position, on macOS and on Linux, through a remote hop too. Terminal law item 1 of docs/design-philosophy.md states the criterion of the terminal interface.

## How does a reader use and change the topic?

Read the table above, or press Option+K in tmux for the popup.

A change that adds a binding follows the add-a-row rule of Terminal law item 5 of docs/design-philosophy.md. The rule lives there, not here.

A new row states its action and its conflict check. The renderer drops the conflict-check column, and the popup needs no pipe character in a cell, so keep both column rules when a row changes.
