# keymap

Bindings of the modifier layers across the terminal surfaces, with the conflict check of each key.

## Modifier Layers

One modifier per layer. Meta operates the OS and the terminal application, Option operates tmux, and Ctrl operates the tool in the pane. A key with no modifier, or with Shift only, goes to the tool in the pane. No Meta key passes into a pane, even when the application could forward it.

The rows of lib/keymap.nix are the one list of the bindings. Each row states its layer, its key, its action, and the payload of each surface it touches. The bind lines of tmux, WezTerm, and fish derive from the rows, and the Option+K popup renders them. The nvim rows generate nothing: they mirror the lua modules as an explicit supplement, and a change of the lua drags its row along (docs/adr/no-load-bearing-docs-interface.md).

## Conflict Checks

The conflict check of each binding, by layer. A new binding adds its row in lib/keymap.nix and its check here.

Meta layer:

1. Super+T: WezTerm only. No Meta chord reaches a pane (wezterm.nix).
2. Ctrl+Shift+T: WezTerm holds the chord. tmux binds no Ctrl+Shift+T (wezterm.nix).

Option layer:

1. 1 to 9, 0: tmux only. No pane reads window numbers (tmux.nix).
2. Down, Left, Right, Up: tmux only. Word movement moved off Option to SHIFT (tmux.nix; fish.nix).
3. Tab: tmux. Ctrl+Tab is the ide tab chord, a different key (tmux.nix).
4. Shift+Tab: tmux (tmux.nix).
5. t: tmux. fish keeps its alt-t, transpose-words, outside tmux; nvim holds no M-t map, and the yazi keymap adds no t chord (tmux.nix).
6. w: tmux. A bare key never reaches a pane (tmux.nix).
7. k: tmux. nvim holds no M-k map (tmux.nix).
8. g: tmux (tmux.nix).
9. D: tmux. This key takes Shift, because Option+d stays the fish kill-word (tmux.nix).

Ctrl layer:

1. 0 to 9: tmux routes. nvim maps Ctrl+0 to Ctrl+9 to the same tabs (tmux.nix; keymaps.lua).
2. Tab: tmux routes. A released WezTerm default lets the chord reach tmux (tmux.nix; wezterm.nix).
3. Shift+Tab: the same path (tmux.nix).
4. Shift+F: tmux rewrites the chord, because a pane cannot read Shift on a control key without the kitty protocol (tmux.nix; editing.lua).
5. Shift+H: the same limit (tmux.nix; editing.lua).
6. Shift+P: the same limit. WezTerm releases its own Ctrl+Shift+P default (tmux.nix; editing.lua; wezterm.nix).
7. D: fish inside tmux. WezTerm types Enter and Ctrl+D when it closes a pane (fish.nix).
8. F: a tool in the pane owns the key. nvim shadows its page-forward default (editing.lua).

Keys with no modifier:

1. Shift+Enter: tmux rewrites the chord, under the kitty protocol limit (tmux.nix).
2. Shift+Left, Shift+Right: fish. This chord carries the word movement that Option+arrows held before tmux took them (fish.nix).

Tool layer, nvim only:

1. Ctrl+S: nvim only. fish keeps its Ctrl+S. Its insert-mode map replaces the signature-help default, because blink.cmp shows the window by itself (keymaps.lua; editing.lua; issue 195).
2. Ctrl+T: nvim only. WezTerm releases the legacy alias of the key, so it reaches the pane (keymaps.lua; wezterm.nix; issue 195).
3. Ctrl+W: nvim only. A map shadows the window-command prefix, and :wincmd still moves in a split (keymaps.lua). A buffer-local no-op holds the map inert in the tree buffer, so the tree closes only through the toggle, q, and leader x (tree.lua; issues 165 and 325).
4. Ctrl+Y, Ctrl+N, Ctrl+P, Ctrl+Space, in insert mode: a blink.cmp preset, below the insert-mode completion of nvim (editing.lua).
5. gd, gD, Shift+F12, Ctrl+click: buffer-local maps of LspAttach beside the nvim built-ins (lsp.lua; keymaps.lua; issue 165).
6. Backslash, the leader: a key with no modifier, so the tool owns it (options.lua; issue 165).
7. Leader d, q, w, x: leader chords, so no other tool sees them (keymaps.lua).
8. Leader f, then a key: pickers of fzf-lua and grug-far (editing.lua).
9. Leader f, then q: editor side of the search command (search.lua; issue 189).
10. Tab, Shift+Tab, in the grug-far panel: one plugin maps the bare key inside the buffer of the panel, in insert and normal mode. A bare key with no modifier belongs to the tool (editing.lua; issue 316).
11. Leader t, then t or f: toggle state is shared by every tab (tree.lua; issues 196 and 234).
12. H, in the tree window: a neo-tree default of the key, kept by the config (tree.lua; issue 196).
13. Leader e, E: a yazi command of nvim (editing.lua).
14. Leader v, then a key: review flow of the branch (review.lua).
15. Leader r, then a key: neotest with the go adapter (test.lua).
16. Leader D, then a key: nvim-dap with dap-go (dap.lua).

Prefix table:

1. Quotation mark, percent, c: the stock prefix stays for rare commands. The Option layer holds the frequent ones (tmux.nix).

Mouse layer:

1. Middle click on the status bar: tmux (tmux.nix).
2. Double click on the status bar: tmux (tmux.nix).
3. Double click past the last window: tmux (tmux.nix).
4. Option and drag in a pane: tmux copy mode (tmux.nix).
5. Wheel in copy mode: tmux (tmux.nix).

## Surfaces and Transport

Each surface holds its own bindings:

1. WezTerm: the new-tab chords, and the release of its Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+Shift+F, Ctrl+Shift+P, and Ctrl+T defaults, so the chords reach tmux. The entries of config.keys derive from the rows (wezterm.nix of modules/programs/gui; lib/keymap.nix).
2. tmux: an Option layer through `bind -n`, the routed Ctrl+Shift chords, the prefix table, the mouse bindings, and the popups. The bind lines derive from the rows (modules/programs/cli/tmux.nix; lib/keymap.nix).
3. fish: the Ctrl+D and Shift+arrows bindings inside the pane. The bind lines derive from the rows (modules/programs/cli/fish.nix; lib/keymap.nix).
4. nvim: the receiver maps of the routed chords stay in the lua modules (modules/programs/cli/neovim/lua/genixis/), and the supplement rows mirror them.

Transport of a chord runs through this chain:

1. WezTerm encodes keys with CSI-u, and it sends the left Alt key raw and the right Alt key composed (wezterm.nix).
2. tmux turns extended-keys on and reads the terminal feature `extkeys` (tmux.nix).
3. A pane cannot read Shift on a control key without the kitty protocol, so tmux rewrites the three Ctrl+Shift chords to their Meta forms for nvim (tmux.nix; editing.lua). This stack cannot run the kitty protocol: WezTerm carries it only behind its own option, which the CSI-u encoding replaces, and tmux forwards a CSI-u event but implements no push, pop, or query of the protocol. An editor therefore cannot underline text while Ctrl is held, and a terminal sends Ctrl+H and Backspace as the same byte, which is why the replace chord takes Shift (editing.lua; issues 193 and 195).
4. Shift+Enter shows the same limit: tmux rewrites it for a yazi pane and passes it through to any other pane (tmux.nix).
5. A session tab of a remote login adds ssh and the tmux server of the remote host to the chain. ssh copies TERM unchanged and passes each byte unchanged, so it drops no chord (issue 158).
6. A tmux server loads its configuration once, at its start. An activation hook of each switch re-sources the configuration into the running server, and a binding that a new configuration removed stays until the next server restart (tmux.nix; issue 191).
7. On desktop, the window manager owns Meta, so WezTerm keeps its window keys at Ctrl+Shift there (issue 142).

Popup: lib/keymap.nix renders its rows at build time into plain text, and Option+K shows the result in less (tmux.nix; lib/keymap.nix). Its popup shows the layer sentence and the layer, key, and action of each row. The conflict checks stay in this file. Each build writes the rendered text into the Nix store of the host that runs the server, so every host shows the rows of its own build, and a session tab shows the rows of the remote host.

## Terminal Law

Terminal Law of this topic, at its application (docs/design.md holds the map):

1. One modifier per layer. Meta operates the OS and the terminal application, Option operates tmux, and Ctrl operates the tool in the pane. A key with no modifier, or with Shift only, goes to the tool in the pane. No Meta key passes into a pane, even when the application could forward it. Issue 145 set the boundary at the first prefix binding, so each surface keeps a closed set of chords.
2. Each layer keeps one universal chord that works on every host and through every remote hop, so no layer strands the user (issue 158).
3. The rows of lib/keymap.nix are the one list of the bindings. The bind lines of tmux, WezTerm, and fish derive from the rows, the popup renders the rows, and this file holds the law and the conflict checks. A change that adds a binding adds its row there and its conflict check here. No documentation file is load-bearing for an interface (docs/adr/no-load-bearing-docs-interface.md).

Decisions behind the chords:

4. A new-tab key serves the window it is pressed in, so a window of a remote login opens tabs on that host (issue 142; wezterm.nix).
5. Re-derivation of the map set the leader, the close chords, and the window keys of the Option layer. Spacebar lost as the leader, because the leader must shadow nothing (issue 165; options.lua).
6. Editor chords came next: Ctrl+S writes the file, Ctrl+T opens an empty tab, and the palette and replace chords take the Meta form through the rewrite (issue 195; keymaps.lua; editing.lua).
7. A project-wide search chord and the format cap of a quarter second landed with the picker work (issue 193; editing.lua).
8. File tree lives in a left split with the toggle state shared by every editor tab (issues 196 and 234; tree.lua).
9. Each re-source at a switch writes full sets, never appended lists, because a re-source runs again and again (issue 191; tmux.nix).

Reopening events: the underline hint and the replace chord reopen when the kitty keyboard protocol runs end to end in this stack. A transport section above records why it cannot run today. For the other decisions, no reopening event is known.

## Purpose of the Keymap

Purpose of the keymap: one person drives the OS, the terminal, and the tool in the pane with one hand position, on macOS and on Linux, through a remote hop too. Text as the interface, in docs/cli.md, states the criterion.

## Read and Change the Bindings

Read the popup with Option+K in tmux, or read the rows of lib/keymap.nix. The conflict checks sit in this file.

A new binding adds its row in lib/keymap.nix, with the comment that states why the row holds its key, and its conflict check in this file. A row of the Option layer that opens a popup is one entry of genixis.tmux.popups, and tmux.nix takes the key letter of the entry from the row, so the row is the one home of the key. A change of a lua map of nvim drags its supplement row along.
