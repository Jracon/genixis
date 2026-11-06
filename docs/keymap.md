# The keymap

The modifier layers of every host and the one table of the key bindings.

One modifier per layer, on every host: Meta operates the OS and the terminal application (WezTerm), Option operates tmux, Ctrl operates the tool in the pane (nvim, yazi, fish, claude). A key with no modifier, or with Shift only, goes to the tool in the pane. The bindings live in `modules/programs/gui/wezterm.nix`, `modules/programs/cli/tmux.nix`, and `modules/programs/cli/fish.nix`. This table is the one list of the bindings. When you add a binding, add its row to the table and record the conflict check of the key (issue #145).

The transport of the layers:

- Left Option sends Alt, and right Option composes special characters. Left Option carries the Option layer (`wezterm.nix`). On desktop, the key is labelled Alt. The table names both keys Option.
- tmux asks the outer terminal for extended keys. WezTerm then sends a modified digit as one key, so Option+1 does not arrive as Escape and 1 (`extended-keys` in `tmux.nix`).
- A session tab of a remote login adds two links to the chain: ssh, then the tmux server of the remote host. ssh copies `TERM` unchanged and passes each byte unchanged, so ssh drops no chord (issue #158).
- A tmux server loads its configuration once, at its start. A server older than the last rebuild holds no binding that the rebuild added, so the Option layer went dead in a session tab while a local session worked. The command of a session tab re-sources the configuration into the running server before it attaches (issue #158).
- Each layer holds one chord that works on every host and through a session tab: `Cmd+T` for Meta, the prefix with a digit for Option, `Ctrl+D` for Tool. WezTerm keeps the `Cmd+T` key, the prefix digits are tmux defaults, and `Ctrl+D` is one byte.
- WezTerm disables its own `Ctrl+Tab` binding, so `Ctrl+Tab` reaches tmux and the tool.
- No Meta key reaches a pane. Every Meta key stays in the application.
- Exception on desktop: the window manager owns Meta, so the application keeps its WezTerm defaults at Ctrl+Shift. The new-tab key is `Ctrl+Shift+T` there (issue #142).

| Layer | Key | Action | Conflict check |
| --- | --- | --- | --- |
| Meta | `Cmd+T` | Open a new tab in the window of the key. In the window of a remote login, the new tab runs a shell on that host (issue #142). The chord works on every host and through a session tab, because WezTerm keeps the key. On desktop, the key is `Ctrl+Shift+T`. | A WezTerm default, rebound for the per-window behavior. |
| Meta | `Cmd+W` | Close the tab. | A WezTerm default. |
| Meta | `Cmd+N` | Open a new window. | A WezTerm default. |
| Meta | `Cmd+1..9` | Switch the tabs of the host window. One tmux session is one tab. | A WezTerm default. |
| Meta | `Cmd+Enter` | In a yazi pane, open the hovered file with the default application of the OS. On desktop, the same physical key is `Super+Enter`. | No WezTerm default holds the key. The key stays in WezTerm, so no pane sees a Meta modifier. WezTerm sends `Shift+F1` into the pane only when the pane runs yazi. tmux holds no binding on `Shift+F1`. The default yazi keymap holds no shifted F-key; it binds `F1` alone, for help. On desktop, the window manager must pass `Super+Enter` to WezTerm. |
| Option | Option+arrows | Move between panes. | No nvim map and no yazi keymap holds an Alt+arrow. fish loses its directory history on Option+Left and Option+Right, and its token search on Option+Up and Option+Down, inside tmux. Outside tmux, fish keeps these keys. Shift+arrows keep the word movement. |
| Option | Option+0..9 | Switch the tmux window. Option+0 selects the tenth window, as Ctrl+0 selects the tenth nvim tab. Through a session tab, the prefix with a digit does the same: prefix `1..9` selects the first to the ninth window. The tenth window needs the prefix, then `'`, then `10`. | No nvim map, no yazi keymap, and no default fish binding holds an Alt+digit. The prefix digits are tmux defaults, so they work on a server of any age and need no extended keys. |
| Option | Option+g | Open the lazygit popup. | No nvim map, no yazi keymap, and no default fish binding holds an Alt+g. |
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
| Tool | Space `D` + `b`/`c`/`i`/`o`/`O`/`t` | In nvim, debug the program: toggle a breakpoint, continue or start, step into, step over, step out, and toggle the debug UI of nvim-dap-ui. delve serves Go through nvim-dap-go. | A leader key of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>D`; the line diagnostics stay on the lowercase `<leader>d`. The debug UI closes its own views with `q`. |
| Tool | Space `f` + `a` | In nvim, find and replace across the project through grug-far. The search buffer previews every match, and only its replace actions write files. | A leader key of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>fa`; the find group holds `d`, `f`, `g`, `h`, `k`, `r`, and `s` today. |
| Tool | Space `v` + `q`/`d`/`g`/`h`/`t` | In nvim, read a worktree against its base branch: the quickfix of the files that differ (`q`), one file beside its base version (`d`), and the branch in a tmux popup through lazygit with delta (`g`), hunk (`h`), and tuicr (`t`). | A leader key of nvim, so no other layer or tool sees the key. No nvim map holds `<leader>v`. The popup keys need tmux; the popups close with `q`, which never leaves the popup. |

The checks above read the default bind table of fish (the `bind` builtin), the nvim maps under `modules/programs/cli/neovim/`, and the yazi keymap in `yazi.nix`.
