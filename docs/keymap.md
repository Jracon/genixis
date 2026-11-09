# The keymap

The modifier layers of every host and the one table of the key bindings.

## What is the keymap?

One modifier per layer, on every host: Meta operates the OS and the terminal application (WezTerm), Option operates tmux, Ctrl operates the tool in the pane (nvim, yazi, fish, claude). A key with no modifier, or with Shift only, goes to the tool in the pane. This table is the one list of the bindings: every binding of the sources holds one row.

| Layer | Key | Action | Conflict check |
| --- | --- | --- | --- |
| Meta | `Cmd+T` | Open a new tab in the window of the key. In the window of a remote login, the new tab runs a shell on that host (issue #142). The chord works on every host and through a session tab, because WezTerm keeps the key. On desktop, the key is `Ctrl+Shift+T`. | A WezTerm default, rebound for the per-window behavior. |
| Meta | `Cmd+W` | Close the tab. | A WezTerm default. |
| Meta | `Cmd+N` | Open a new window. | A WezTerm default. |
| Meta | `Cmd+1..9` | Switch the tabs of the host window. One tmux session is one tab. | A WezTerm default. |
| Option | Option+arrows | Move between panes. | No nvim map and no yazi keymap holds an Alt+arrow. fish loses its directory history on Option+Left and Option+Right, and its token search on Option+Up and Option+Down, inside tmux. Outside tmux, fish keeps these keys. Shift+arrows keep the word movement. |
| Option | Option+0..9 | Switch the tmux window. Option+0 selects the tenth window, as Ctrl+0 selects the tenth nvim tab. Through a session tab, the prefix with a digit does the same: prefix `1..9` selects the first to the ninth window. The tenth window needs the prefix, then `'`, then `10`. | No nvim map, no yazi keymap, and no default fish binding holds an Alt+digit. The prefix digits are tmux defaults, so they work on a server of any age and need no extended keys. |
| Option | Option+Tab and Option+Shift+Tab | Switch to the next and the previous tmux window. | tmux names the shifted Tab BTab, as the Ctrl+Shift+Tab row below shows. The chords ride the extended-keys path that carries Ctrl+Tab today. No default fish binding holds an Alt+Tab, nvim holds no Alt map, and the yazi keymap binds no Tab at all. On a desktop, the window manager owns Alt+Tab before WezTerm sees the key, so there the Option+digits and the prefix digits switch windows. |
| Option | Option+W | Close the tmux window, with no prompt. | The middle-click on the status bar closes a window the same way. No nvim map and no yazi keymap holds an Alt+W. fish binds alt-w to the description of the token under the cursor; inside tmux the tmux binding shadows the key, and outside tmux fish keeps it, as the Option+arrows row documents. |
| Option | Option+g | Open the lazygit popup. | No nvim map, no yazi keymap, and no default fish binding holds an Alt+g. |
| Option | Option+K | Open this table in a tmux popup, from any pane. The popup shows a rendered copy of the table: key to action, in wrapped plain text, without the conflict-check column and without the transport notes. The pager is less; `q` closes the popup. | An entry of `genixis.tmux.popups`, as the lazygit and lazydocker popups. No default fish binding holds an Alt+k (the nearest are alt-w and alt-l), no nvim map holds an Alt key, and the default yazi keymap holds no Alt key. |
| Option | Option+Shift+D | Open the lazydocker popup, only where `programs.lazydocker.enable` is true. | Alt+d without Shift is fish kill-word, so the key takes Shift. No nvim map and no yazi keymap holds an Alt+d. |
| Option | Option+drag | Select a rectangle (columns of output). | A tmux mouse binding. No tool sees a drag. |
| Option | Option+wheel | Scroll ten lines at a time in copy mode. | A tmux mouse binding. No tool sees the wheel in copy mode. |
| Option | Mouse on the status bar | Middle-click closes the window. A double-click renames the window or opens a new one. | A tmux mouse binding with no modifier. |
| Option | Prefix (`Ctrl+B`), then `"` or `%` or `c` | Split the window, or open a new window, in the directory of the current pane. The prefix also keeps the tmux defaults, for example detach and copy mode. | The prefix starts with a Ctrl key. tmux keeps it for the rare tmux commands. |
| Tool | Ctrl+arrows | The tool in the pane applies its own maps and defaults. | Free after the pane movement moved to Option+arrows. The nvim maps hold no Ctrl+arrow. |
| Tool | Ctrl+0..9 | In an `ide` window, select that tab of nvim (Ctrl+0 selects the tenth), from any pane. Elsewhere the tool gets the key. | The nvim maps in `neovim/lua/genixis/keymaps.lua` hold these keys. tmux routes them. |
| Tool | `Ctrl+Tab` and `Ctrl+Shift+Tab` | In an `ide` window, select the next or the previous nvim tab. Elsewhere the tool gets the key. | The nvim maps hold these keys. WezTerm disables its own binding. |
| Tool | Ctrl+D | In fish under tmux, delete a character. Ctrl+D never exits the shell. The chord crosses ssh and tmux unchanged, because it is one byte. | A fish binding. WezTerm types Enter and Ctrl+D into a pane that it closes. |
| Tool | Shift+arrows | Move by word at the fish prompt. | A fish binding. The modifier survives tmux. |
| Tool | Shift+Enter | In yazi, read the hovered file in the viewer (`ide-view`). tmux rewrites the key to Alt+Enter in yazi panes only. | Alt+Enter stays the viewer trigger in yazi panes only. No other pane sees the rewrite. |
| Tool | Enter, in a yazi pane | In yazi, enter the hovered directory, or open the hovered file in the editor pane of the ide window (`smart-enter`). | A yazi prepend over the default open. An unmodified key, so the Tool layer owns it. |
| Tool | Shift+F12 | In nvim, list the references of the symbol under the cursor in the fzf-lua picker. | A Shift-only key, so the Tool layer owns it. The F-key with its modifier is one legacy sequence (CSI 24;2~), which crosses ssh and tmux unchanged. No nvim map, no default fish binding, and no yazi keymap holds the key; yazi binds F1 alone, for help. The built-in grr keeps the quickfix of the references. |
| Tool | `gd`, and the built-in LSP maps | `gd` jumps to the definition of the symbol under the cursor. nvim keeps its built-in LSP maps: `grr` references, `gri` implementation, `grn` rename, `gra` code action, `gO` symbols, `K` hover, `[d` and `]d` diagnostics, Ctrl+S signature help. | `gd` is a buffer-local map that LspAttach sets. The built-ins are nvim defaults. Unmodified keys, so the Tool layer owns them. |
| Tool | `gD` | In nvim, list the definitions of the symbol under the cursor in the fzf-lua picker. | An unmodified key, so the Tool layer owns it. The map shadows the nvim default `gD`, the jump to the declaration; gopls and lua_ls report the declaration of a Go or Lua symbol as its definition, and `gd` keeps the direct jump. No yazi keymap holds a `g` chord with `D`. |
| Tool | Ctrl+click | In nvim, jump to the definition of the symbol under the click, as `gd` does. | Ctrl operates the tool in the pane, so the click is a tool key where it is added: nvim sets `mouse=a`, and tmux forwards a click with its modifier to a pane whose program asked for mouse events. The map replaces the nvim default that jumps to the tag under the click (Ctrl+]). A click with no modifier, or with Shift, stays with the tool: nvim moves the cursor, yazi selects. No Meta click reaches a pane, because every Meta key stays in the application. |
| Tool | Ctrl+F | In nvim, search in the open file through the fzf-lua live grep of the buffer. It replaces the former `\` `/` chord. | A Tool-layer chord of nvim only: fish keeps its Ctrl+F forward-char at the prompt, and yazi binds no Ctrl+F. The map shadows the nvim default that pages one screen forward; Ctrl+B keeps paging back. The chord is one byte, so it crosses ssh and tmux unchanged. |
| Tool | Ctrl+Shift+F | In nvim, search the contents of all files in the working directory through the fzf-lua live grep, also on `\` `f` `g` (issue #193). Finding files by name stays on `\` `f` `f` and in yazi. | WezTerm disables its own Ctrl+Shift+F search default, so the chord reaches tmux; tmux copy-mode covers the search of the scrollback. A pane cannot read Shift on a control key without the kitty protocol, which tmux does not forward, so tmux rewrites the chord to M-F in nvim panes only, as it rewrites Shift+Enter for yazi. nvim holds the M-F map and a C-S-f map for a pane without tmux. No nvim default and no default fish binding holds the key. Every other pane gets Ctrl+F. |
| Tool | Ctrl+W | In nvim, close the file and keep nvim open: a file in a tab of its own closes the tab, otherwise the window stays. The same action as `\` `x`. In the file tree, the key closes the tree. | A Tool-layer chord of nvim only: fish keeps its Ctrl+W, which deletes the path component before the cursor, and the yazi keymap binds no Ctrl+W. The map shadows the window-command prefix of nvim; `:wincmd` still moves between the split of a diff or of an inccommand preview. The chord is one byte, so it crosses ssh and tmux unchanged. |
| Tool | `Esc` | In nvim, clear the highlight of the last search. | An unmodified key of nvim. The map adds the clear to the nvim default of the key, which only ends a pending operation in normal mode. |
| Tool | `j`, `k`, the arrows, `Home`, `End` | In nvim, move by screen line in wrapped text; a count moves by real line. `Home` and `End` go to the start and the end of the screen line. In insert mode the arrows, `Home`, and `End` do the same screen-line moves, but the arrows still drive the completion menu. | Unmodified keys of nvim. The maps give the keys their screen-line forms in place of the nvim defaults. No other tool sees a plain key. |
| Tool | `<` and `>` in visual mode | In nvim, indent the selection and keep it selected, so a second indent applies again. | Unmodified keys of nvim. The maps keep the indent of the nvim defaults and add the reselect. |
| Tool | `aa`/`ia`, `ac`/`ic`, `af`/`if`, `[f`/`]f`, `[F`/`]F` | In nvim, select an argument, a class, or a function of the syntax tree (`a` takes the whole object, `i` the inside), and jump to the start and the end of the previous and the next function. | Unmodified keys of nvim, mapped to the treesitter text objects. nvim holds no default for them; the python ftplugin keeps its own buffer-local `]m`. |
| Tool | `\` (the leader of nvim) | The first key of every nvim chord that the rows below write as `\` plus a key. The owner rejected the spacebar as the leader (issue #165). | A key with no modifier, so the Tool layer owns it. No nvim default uses the backslash: it is the historic leader key of vim. No default fish binding and no yazi keymap holds the key, so it shadows nothing. |
| Tool | `\` `\` | In nvim, switch the open buffers through the fzf-lua picker. | A leader chord of nvim, so no other layer or tool sees the key. No nvim map holds a doubled leader. |
| Tool | `\` `d`, `\` `q`, `\` `w`, `\` `x` | In nvim, read the diagnostics of the line (`d`), collect the diagnostics in the loclist (`q`), write the file (`w`), and close the file but keep nvim open (`x`, also Ctrl+W). In the file tree, `x` closes the tree. | Leader chords of nvim, so no other layer or tool sees the keys. No nvim map holds `<leader>d`, `<leader>q`, `<leader>w`, or `<leader>x`; the debug group keeps the uppercase `D`. |
| Tool | `\` `e` and `\` `E` | In nvim, open yazi at the current file (`e`) or at the working directory (`E`). Picked files open as buffers, and several go to the quickfix list. | Leader chords of nvim, so no other layer or tool sees the keys. No nvim map holds `<leader>e` or `<leader>E`. |
| Tool | `\` `f` + `d`/`f`/`g`/`h`/`k`/`r`/`s` | In nvim, find through fzf-lua: workspace diagnostics (`d`), files (`f`), text across the project (`g`, also Ctrl+Shift+F), help tags (`h`), the nvim keymaps (`k`), the last search again (`r`), and workspace symbols (`s`). Ctrl+F carries the search of the open file. | Leader chords of nvim, so no other layer or tool sees the keys. which-key names the group `find`. No nvim map holds these `<leader>f` keys. |
| Tool | `\` `f` + `a` | In nvim, find and replace across the project through grug-far. The search buffer previews every match, and only its replace actions write files. | A leader chord of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>fa`. |
| Tool | `\` `h` + `b`/`p`/`r`/`s`, and `]h`/`[h` | In nvim, read the git hunk under the cursor: blame (`b`), preview (`p`), reset (`r`), stage (`s`). `]h` and `[h` jump to the next and the previous hunk. | Leader chords and unmodified keys of nvim. No nvim map holds `<leader>h`, and nvim holds no default for `]h` or `[h`. |
| Tool | `\` `r` + `f`/`l`/`o`/`r`/`s`/`x` | In nvim, run the test file (`f`), run the last test again (`l`), open the output of the nearest test (`o`), run the nearest test (`r`), toggle the summary (`s`), and stop the nearest test (`x`), through neotest. | Leader chords of nvim, so no other layer or tool sees the keys. which-key names the group `test`. |
| Tool | `\` `t` + `h` | In nvim, turn the inlay hints of every buffer on and off. | A leader chord of nvim, so no other layer or tool sees the key. which-key names the group `toggle`. |
| Tool | `\` `t` + `t` | In nvim, hide and show the file tree (neo-tree) in a left split of the editor. A bare nvim start opens the tree by itself (issue #196). | A leader chord of nvim, so no other layer or tool sees the key. No nvim map holds a doubled `t` after the leader; the toggle group keeps `h` for the inlay hints. |
| Tool | `\` `t` + `f` | In nvim, focus the file tree and reveal the file of the current tab. From the tree, the key goes back to the editor. A file outside the working directory reveals nothing, because the reveal would ask for a change of the tree root. | A leader chord of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>tf`. |
| Tool | Enter and `l`, in the tree window | In the file tree of nvim, expand a folder, collapse an expanded one, and open a file into its own tab, under the tab rules of `ide-open`: a file that is already open switches to its tab, and a blank fresh buffer is reused. | Buffer-local maps of the tree window. They shadow the neo-tree defaults there, and no map outside the tree window applies to it. Unmodified keys, so the Tool layer owns them; Enter keeps the smart-enter of yazi panes. |
| Tool | `h`, in the tree window | In the file tree of nvim, collapse the folder of the row, or the parent of a row inside one. | A buffer-local map of the tree window; it shadows the neo-tree default there. The `h` of yazi keeps its own meaning in yazi. |
| Tool | `H`, in the tree window | In the file tree of nvim, hide the dotfiles and the gitignored rows, and show them again. The tree shows both by default (issue #196). | The neo-tree default of the key; the config keeps it. A buffer-local key of the tree window, so it shadows the nvim window-top motion of `H` there only. A Shift-only key, so the Tool layer owns it. |
| Tool | `q`, in the tree window | Close the tree window. | A buffer-local map of the tree window; it shadows the macro-record key of nvim there only. The popups of the Option layer keep their own `q`. |
| Tool | `\` `D` + `b`/`c`/`i`/`o`/`O`/`t` | In nvim, debug the program: toggle a breakpoint, continue or start, step into, step over, step out, and toggle the debug UI of nvim-dap-ui. delve serves Go through nvim-dap-go. | A leader key of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>D`; the line diagnostics stay on the lowercase `<leader>d`. The debug UI closes its own views with `q`. |
| Tool | `\` `v` + `q`/`d`/`g`/`h`/`t` | In nvim, read a worktree against its base branch: the quickfix of the files that differ (`q`), one file beside its base version (`d`), and the branch in a tmux popup through lazygit with delta (`g`), hunk (`h`), and tuicr (`t`). | A leader key of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>v`. The popup keys need tmux; the popups close with `q`, which never leaves the popup. |
| Tool | Ctrl+Y, Ctrl+N, Ctrl+P, Ctrl+Space, in insert mode | In nvim, drive the completion of blink.cmp: accept the entry (Ctrl+Y), select the next and the previous entry (Ctrl+N, Ctrl+P), and open the menu (Ctrl+Space). Ctrl+S keeps the signature help of the built-in LSP maps. | The default preset of blink.cmp, so the insert-mode completion of nvim answers below it. The chords stay in nvim: no other tool sees an insert-mode key. |

## How is the keymap realized?

The bindings live in these sources: `modules/programs/gui/wezterm.nix`, `modules/programs/cli/tmux.nix`, `modules/programs/cli/fish.nix`, `modules/programs/cli/yazi.nix`, and the Lua files under `modules/programs/cli/neovim/lua/genixis/`.

The renderer runs at build time. `tmux.nix` runs `keymap-table.awk` over the store copy of this file. The renderer prints the title line, the first sentence of the layer rule, and one block per row. A block holds the layer and the key on one line, and the wrapped Action cell under them. The renderer prints no other text of this file. Text that leaves the Action cell of a row leaves the popup at the next rebuild of each host.

The build writes the rendered table into the Nix store of the host that runs the tmux server. The Option+K popup pages that copy, so every host shows the table of its own build, and a session tab shows the table of the remote host. This file stays the single source.

The transport of the layers:

- Left Option sends Alt, and right Option composes special characters. Left Option carries the Option layer (`wezterm.nix`). On desktop, the key is labelled Alt. The table names both keys Option.
- tmux asks the outer terminal for extended keys. WezTerm then sends a modified digit as one key, so Option+1 does not arrive as Escape and 1 (`extended-keys` in `tmux.nix`).
- A pane learns a held modifier only from a key event, and a bare modifier press sends bytes only under the kitty keyboard protocol. That protocol cannot run in this stack (issue #193): WezTerm carries it only behind its own option, which the fixterms encoding above replaces; tmux forwards a CSI-u key event but implements no push, pop, or query of the protocol; and nvim asks the protocol for disambiguation and event types only, never for the reporting of all keys, which a bare modifier press needs. The editor therefore cannot underline text while Ctrl is held.
- A session tab of a remote login adds two links to the chain: ssh, then the tmux server of the remote host. ssh copies `TERM` unchanged and passes each byte unchanged, so ssh drops no chord (issue #158).
- A tmux server loads its configuration once, at its start. A server older than the last rebuild holds no binding that the rebuild added, so the Option layer went dead in a session tab while a local session worked. The command of a session tab re-sources the configuration into the running server before it attaches (issue #158).
- Each layer holds one chord that works on every host and through a session tab: `Cmd+T` for Meta, the prefix with a digit for Option, `Ctrl+D` for Tool. WezTerm keeps the `Cmd+T` key, the prefix digits are tmux defaults, and `Ctrl+D` is one byte.
- WezTerm disables its own `Ctrl+Tab` binding, so `Ctrl+Tab` reaches tmux and the tool.
- No Meta key reaches a pane. Every Meta key stays in the application.
- Exception on desktop: the window manager owns Meta, so the application keeps its WezTerm defaults at Ctrl+Shift. The new-tab key is `Ctrl+Shift+T` there (issue #142).

## Why is the keymap that way?

### #142 — the new-tab key of a window of a remote login

**Decision.** The new-tab key works per window. In a window whose title names a remote login, the key opens a tab of the same login. The new tab runs the ssh command of the home tab of that window. A session tab ends only when its shell on the remote host exits. On desktop, the window manager owns Meta, so the new-tab key is `Ctrl+Shift+T` there.

**Alternatives that lost.** The default program for each new tab. The tab of a window of a remote login then ran a local shell, and the window names a remote login. A session tab that ended on detach. The tmux attach command ended, the ssh connection ended with it, and the tab closed.

**Reopening event.** No reopening event is known.

### #145 — one modifier per layer

**Decision.** The keymap moved to one modifier per layer. tmux moved its pane keys and its window keys onto Option chords, and the pane tools got Ctrl back. The prefix stays for the rare tmux commands that keep it. Each row of the table names the conflict check of its key.

**Alternatives that lost.** The keymap as it grew, with shared modifiers. Pane movement sat on Ctrl+arrows, window keys sat on the prefix, and only a read of three files showed which layer a key serves. fish with its Alt keys inside tmux. The layer rule takes all four arrows, so fish loses its directory history and its token search inside tmux. The rows of Option+arrows and Option+W record the losses.

**Reopening event.** No reopening event is known.

### #158 — one chord of each layer through the whole chain

**Decision.** Each layer keeps one chord that works on every host and through a session tab. The transport section names the three chords. The command of a session tab re-sources the tmux configuration into the running server before it attaches.

**Alternatives that lost.** A fix of the transport. `TERM` crosses ssh unchanged, and ssh passes each byte unchanged. tmux parses the CSI-u input forms unconditionally, so the chord reached the remote server in every encoding path. The drop sat in the running tmux server on services: the server loads its configuration once, at its start, and it predated the rebuild that carried the Option+digit bindings.

**Reopening event.** No reopening event is known.

### #165 — the re-derivation of the map

**Decision.** The audit re-derived each binding from the layer rules, and precedent alone kept no binding. It filled the gaps: Shift+F12 opens the references picker, gD opens the definitions picker, Ctrl+Click jumps to a definition, and Option+K opens the keymap popup. The leader of the nvim chords is the backslash.

**Alternatives that lost.** The spacebar as the leader of nvim. The owner rejected it on 2026-11-06. Precedent as the measure of a binding. The audit kept, moved, or dropped each binding on the layer rules alone.

**Reopening event.** No reopening event is known.

### #193 — the follow-ups after living with the map

**Decision.** The Option+K popup pages a rendered key-to-action table, built at rebuild time from this file, which stays the single source. Ctrl+Shift+F searches the contents of all files in the working directory, and find-by-name stays on leader `f` `f` and in yazi. The editor cannot underline text while Ctrl is held, and the transport section records the cause.

**Alternatives that lost.** Raw markdown in the popup. The pipes and the dashes of the source are hard to read. fzf.files on Ctrl+Shift+F. It finds files by name, and the request asked for a search of file contents. The kitty keyboard protocol for held modifiers. The transport section records why it cannot run in this stack.

**Reopening event.** The underline hint reopens when the kitty keyboard protocol runs end to end in this stack. For the other decisions, no reopening event is known.

### #196 — the file tree in the editor pane

**Decision.** The file tree lives in a left split of the nvim pane, through neo-tree, and the ide window holds no yazi pane. A bare nvim start opens the tree by itself. The tree shows the dotfiles and the gitignored rows by default, and `H` hides them.

**Alternatives that lost.** nvim-tree. Its roadmap adds no new major features, neo-tree ships active releases, and the socket of nvim drives the refresh of neo-tree. A single-pane tree in yazi. Yazi has none, as a check of its core, its official plugins, and its community plugins showed. A shell column at the left edge. The shell spans under the tree split instead, and the editor keeps its left-edge anchor. A watchdog process for the git marks. Neo-tree watches the tree directories and the git directory by itself.

**Reopening event.** No reopening event is known.

## What does the keymap enable?

The keymap gives every host the same chords. A reader who learns the chords on one host drives every other host, also behind a session tab of a remote login. The three layers keep the terminal application, tmux, and the pane tool out of the keys of each other. WezTerm keeps its window keys, tmux keeps its panes, its windows, and its popups, and nvim, yazi, and fish keep their own maps. The conflict checks of the table let a person or an agent add a binding without breaking another tool.

## How does a reader use and change the keymap?

Read the table:

1. Press Option+K in any pane. The popup lists each binding as key to action.
2. Read the row of the key in this file for its conflict check.

Add a binding:

1. Pick the layer of the key under the layer rule of the what section.
2. Check the key against each source of the conflict check below. The key must be free in every tool that sees the layer.
3. Write the binding in the source file of its layer.
4. Add one row to the table: the layer, the key, the action, and the conflict check.
5. Land the binding and its row in one commit.

Before a rebuild, probe the Lua of `modules/programs/gui/wezterm.nix` outside the GUI. Run `wezterm --config-file` with a copy of the `extraConfig` and the `ls-fonts` subcommand: the command loads the config and prints syntax and runtime errors. The `show-keys` subcommand ignores config files and proves nothing. For behavior, prepend a stub `wezterm` table (`config_builder`, `action`, `action_callback`, `on`, `hostname`, `font`, `mux`) and append assertions that call the callbacks with stub objects. End the probe with `return {}` so the converter accepts the file. Keep probe files in `.scratch/`, and replace the two Nix interpolations, `color_schemes` and `palette.name`, with plain values.

Change a binding:

1. Change the binding in its source file.
2. Write its row again: the action, and the conflict check of the new key.
3. Land both in one commit.

Remove a binding:

1. Remove the binding from its source file.
2. Remove its row in the same commit.

A conflict check reads these sources: the default bind tables of fish (`fish_default_key_bindings.fish` and `__fish_shared_key_bindings.fish` of the fish source), the nvim maps under `modules/programs/cli/neovim/lua/genixis/`, the default yazi keymap (`keymap-default.toml` of the yazi source) beside the prepend of `yazi.nix`, and the default key tables of WezTerm and tmux.
