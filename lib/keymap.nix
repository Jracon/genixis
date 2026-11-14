{
  lib,
}:

# The one list of the terminal bindings (docs/keymap.md holds the law, the transport chain,
# and the conflict check of each binding). Each row states its layer, its key, its action,
# and the payload of each surface it touches:
#
#   tmuxLines    the bind lines that tmux.nix writes, with the comment of the row above them
#   weztermKeys  the entries that wezterm.nix writes into config.keys
#   fishLines    the bind lines that fish.nix writes; fishInTmux wraps them in the TMUX guard
#   popup        the name of the genixis.tmux.popups entry of the row; popupKeys gives
#                tmux.nix the key letter, so the row is the one home of the key
#   nvim         the lua module that holds the map: a supplement row, an explicit mirror
#
# The nvim rows generate nothing. The lua modules stay plain lua (the plain-lua criterion of
# docs/cli.md), a change of the lua drags its row along, and the record
# docs/adr/no-load-bearing-docs-interface.md states why no documentation file is
# load-bearing for an interface.
#
# The row order is the layer order of the law: Meta, Option, Ctrl, None, Tool, Prefix, Mouse.
# The generated lines bake the indent of their consumer: eight spaces for the tmux
# configuration, six for the fish init.
let
  # wraps one text: every line indented, at most 92 columns wide, so the popup stays readable
  wrap =
    indent: text:
    let
      pad = lib.concatStrings (lib.genList (_: " ") indent);
      limit = 92 - indent;
      step =
        acc: word:
        if acc.line == "" then
          acc // { line = word; }
        else if lib.stringLength acc.line + 1 + lib.stringLength word <= limit then
          acc // { line = acc.line + " " + word; }
        else
          {
            lines = acc.lines ++ [ acc.line ];
            line = word;
          };
      final = lib.foldl' step {
        lines = [ ];
        line = "";
      } (lib.splitString " " text);
      all = final.lines ++ lib.optional (final.line != "") final.line;
    in
    lib.concatStringsSep "\n" (map (line: pad + line) all);

  # one block per row that writes tmux bind lines: a blank line, the why-comment, the lines
  tmuxConfig = lib.concatStrings (
    map (
      row:
      lib.optionalString (row ? tmuxLines) (
        "\n"
        + lib.optionalString (row ? comment) "        # ${row.comment}\n"
        + lib.concatMapStrings (line: "        ${line}\n") row.tmuxLines
      )
    ) rows
  );

  # the fish bind lines: the TMUX-guarded rows under one if block, then the plain rows
  fishConfig =
    let
      withLines = lib.filter (row: row ? fishLines) rows;
      guarded = lib.filter (row: row.fishInTmux or false) withLines;
      plain = lib.filter (row: !(row.fishInTmux or false)) withLines;
      commentOf = row: lib.optionalString (row ? comment) "      # ${row.comment}\n";
    in
    lib.optionalString (guarded != [ ]) (
      "\n"
      + lib.concatStrings (map commentOf guarded)
      + "      if set -q TMUX\n"
      + lib.concatMapStrings (row: lib.concatMapStrings (line: "        ${line}\n") row.fishLines) guarded
      + "      end\n"
    )
    + lib.concatStrings (
      map (row: "\n" + commentOf row + lib.concatMapStrings (line: "      ${line}\n") row.fishLines) plain
    );

  # the lua entries of config.keys, in row order
  weztermKeys = lib.flatten (map (row: row.weztermKeys or [ ]) rows);

  # the tmux key letter of each popup row, by popup name: the row is the one
  # home of the key, and tmux.nix reads its bind key from here, so the popup
  # text and the bind line cannot drift apart
  popupKeys = lib.listToAttrs (
    lib.concatMap (
      row:
      lib.optional (row ? popup) {
        name = row.popup;
        value = row.key;
      }
    ) rows
  );

  # the text of the Option+K popup: the layer sentence, then one block per row
  popupText =
    "keymap\n\nOne modifier per layer.\n\n"
    + lib.concatStrings (
      map (
        row: lib.fixedWidthString 6 " " row.layer + "  " + row.key + "\n" + wrap 8 row.action + "\n\n"
      ) rows
    )
    + "The conflict check of each key is docs/keymap.md.\n";

  digits0to9 = map toString (lib.range 0 9);
  digits1to9 = map toString (lib.range 1 9);

  rows = [
    {
      layer = "Meta";
      key = "Super+T";
      action = "Open a new tab. In a delegated login window, the new tab runs a remote login.";
      weztermKeys = [ ''{ key = "T", mods = "SUPER", action = newTabAction() }'' ];
    }
    {
      layer = "Meta";
      key = "Ctrl+Shift+T";
      action = "Open a new tab, the same action as Super+T.";
      weztermKeys = [ ''{ key = "T", mods = "CTRL|SHIFT", action = newTabAction() }'' ];
    }

    {
      layer = "Option";
      key = "1 to 9, 0";
      action = "Select the window of the number. 0 selects the tenth window.";
      comment = "Option digits select the tmux window; := picks the window by its number, which honors base-index 1 (the stock prefix 0 is dead there), and Option+0 selects the tenth window, as Ctrl+0 selects the tenth nvim tab";
      tmuxLines = map (n: "bind -n M-${n} select-window -t :=${n}") digits1to9 ++ [
        "bind -n M-0 select-window -t :=10"
      ];
    }
    {
      layer = "Option";
      key = "Down, Left, Right, Up";
      action = "Select the pane in that direction.";
      comment = "Option operates tmux (left Option sends Alt; issue #145): Option+arrows move between panes, so Ctrl+arrows reach the tool in the pane. fish loses its directory history and its token search on the alt+arrows inside tmux; Shift+arrows keep the word movement";
      tmuxLines = [
        "bind -n M-Down select-pane -D"
        "bind -n M-Left select-pane -L"
        "bind -n M-Right select-pane -R"
        "bind -n M-Up select-pane -U"
      ];
    }
    {
      layer = "Option";
      key = "Tab";
      action = "Select the next window.";
      comment = "Option+(Shift+)Tab switches windows (issue #165). A desktop window manager owns Alt+Tab before WezTerm sees it, so there the digits keep the window switching";
      tmuxLines = [ "bind -n M-Tab next-window" ];
    }
    {
      layer = "Option";
      key = "Shift+Tab";
      action = "Select the previous window.";
      tmuxLines = [ "bind -n M-BTab previous-window" ];
    }
    {
      layer = "Option";
      key = "t";
      action = "Open a new window, in the working directory of the pane.";
      comment = "Option+T opens a new window in the working directory of the pane (issue #317), the same action as the prefix c; fish keeps its alt-t, transpose-words, outside tmux";
      tmuxLines = [ ''bind -n M-t new-window -c "#{pane_current_path}"'' ];
    }
    {
      layer = "Option";
      key = "w";
      action = "Kill the window. tmux asks no confirmation.";
      comment = "Option+W closes the window with no prompt (issue #165), as the middle-click on the status bar does; fish keeps its alt-w, the description of the token under the cursor, outside tmux";
      tmuxLines = [ "bind -n M-w kill-window" ];
    }
    {
      layer = "Option";
      key = "k";
      action = "Open the keymap popup. Its popup renders the rows of lib/keymap.nix.";
      popup = "keymap";
    }
    {
      layer = "Option";
      key = "g";
      action = "Open the lazygit popup in the working directory of the pane.";
      popup = "lazygit";
    }
    {
      layer = "Option";
      key = "D";
      action = "Open the lazydocker popup.";
      popup = "lazydocker";
    }

    {
      layer = "Ctrl";
      key = "0 to 9";
      action = "Inside an ide window, select the ide tab of the number. Outside an ide window, send the chord to the pane.";
      nvim = "keymaps.lua";
      comment = "Ctrl operates the tool in the pane (issue #145; docs/keymap.md holds the law): Ctrl+0..9 in an ide window go to that tab of its nvim (0 = 10th), from any pane. Elsewhere the key goes to the program. The stock prefix digits keep their tmux default action";
      tmuxLines = map (
        n:
        ''bind -n C-${n} if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} ${n}'" "send-keys C-${n}"''
      ) digits0to9;
    }
    {
      layer = "Ctrl";
      key = "Tab";
      action = "Inside an ide window, select the next ide tab. Outside, send the chord to the pane.";
      nvim = "keymaps.lua";
      comment = "Ctrl+Tab and Ctrl+Shift+Tab (C-BTab to tmux) step the ide tabs; elsewhere the chord goes to the program";
      tmuxLines = [
        ''bind -n C-Tab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} next'" "send-keys C-Tab"''
      ];
      weztermKeys = [
        ''{ key = "Tab", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment }''
      ];
    }
    {
      layer = "Ctrl";
      key = "Shift+Tab";
      action = "Inside an ide window, select the previous ide tab. Outside, send the chord to the pane.";
      nvim = "keymaps.lua";
      tmuxLines = [
        ''bind -n C-BTab if -F "#{@ide_editor}" "run-shell -b 'ide-tab #{window_id} prev'" "send-keys C-BTab"''
      ];
      weztermKeys = [
        ''{ key = "Tab", mods = "CTRL|SHIFT", action = wezterm.action.DisableDefaultAssignment }''
      ];
    }
    {
      layer = "Ctrl";
      key = "Shift+F";
      action = "Search the contents of all files in the working directory. An nvim pane receives the chord as M-F. Any other pane receives Ctrl+F.";
      nvim = "editing.lua";
      comment = "Ctrl+Shift+F opens the project-wide search of nvim (issues #165, #193): a pane cannot read Shift on a control key without the kitty protocol, the same limit as the Shift+Enter rewrite, so an nvim pane gets the key as M-F. Every other pane gets the C-f of the legacy encoding";
      tmuxLines = [
        "bind -n C-S-f if -F '#{==:#{pane_current_command},nvim}' 'send-keys M-F' 'send-keys C-f'"
      ];
      weztermKeys = [
        ''{ key = "F", mods = "CTRL|SHIFT", action = wezterm.action.DisableDefaultAssignment }''
      ];
    }
    {
      layer = "Ctrl";
      key = "Shift+H";
      action = "Replace text in the open file. An nvim pane receives the chord as M-H. Any other pane receives Ctrl+H.";
      nvim = "editing.lua";
      comment = "Ctrl+Shift+H replaces in the open file of nvim (issue #195): the same Shift-on-a-control-key limit and the same rewrite as Ctrl+Shift+F, so an nvim pane gets the key as M-H. Every other pane gets the legacy plain key";
      tmuxLines = [
        "bind -n C-S-h if -F '#{==:#{pane_current_command},nvim}' 'send-keys M-H' 'send-keys C-h'"
      ];
    }
    {
      layer = "Ctrl";
      key = "Shift+P";
      action = "Open the command palette. An nvim pane receives the chord as M-P. Any other pane receives Ctrl+P.";
      nvim = "editing.lua";
      comment = "Ctrl+Shift+P opens the command palette of nvim (issue #195): the same limit and rewrite as Ctrl+Shift+H; WezTerm releases its own Ctrl+Shift+P default";
      tmuxLines = [
        "bind -n C-S-p if -F '#{==:#{pane_current_command},nvim}' 'send-keys M-P' 'send-keys C-p'"
      ];
      weztermKeys = [
        ''{ key = "P", mods = "CTRL|SHIFT", action = wezterm.action.DisableDefaultAssignment }''
      ];
    }
    {
      layer = "Ctrl";
      key = "D";
      action = "Delete one character forward. Inside tmux the shell never exits on it.";
      comment = "WezTerm types Enter + Ctrl-D into a pane it closes (Cmd+Q); under tmux the client forwards them to the focused pane, so there Ctrl-D only deletes and never exits the shell (use exit)";
      fishLines = [ "bind ctrl-d delete-char" ];
      fishInTmux = true;
    }
    {
      layer = "Ctrl";
      key = "F";
      action = "In nvim, search the open file. In fish, move one character forward.";
      nvim = "editing.lua";
    }

    {
      layer = "None";
      key = "Shift+Enter";
      action = "A yazi pane receives M-Enter. Any other pane receives Shift+Enter.";
      comment = "Shift+Enter reads the hovered file in yazi (ide-view). yazi only understands the kitty keyboard protocol, which tmux doesn't forward, so it can't see Shift+Enter; send it Alt+Enter instead";
      tmuxLines = [
        "bind -n S-Enter if -F '#{==:#{pane_current_command},yazi}' 'send-keys M-Enter' 'send-keys S-Enter'"
      ];
    }
    {
      layer = "None";
      key = "Shift+Left";
      action = "Move one word back.";
      comment = "word movement of the Tool layer of the keymap (docs/keymap.md holds the law): inside tmux, Option+arrows move between panes, so these Shift+arrows carry the word movement that replaces the directory-history keys (WezTerm's CSI-u encoding keeps the modifier through tmux)";
      fishLines = [ "bind shift-left backward-word" ];
    }
    {
      layer = "None";
      key = "Shift+Right";
      action = "Move one word forward.";
      fishLines = [ "bind shift-right forward-word" ];
    }

    {
      layer = "Tool";
      key = "Ctrl+S";
      action = "In nvim, write the file, and format it on save.";
      nvim = "keymaps.lua";
    }
    {
      layer = "Tool";
      key = "Ctrl+T";
      action = "In nvim, open a new editor tab with an empty buffer.";
      nvim = "keymaps.lua";
      weztermKeys = [
        ''{ key = "T", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment }''
      ];
    }
    {
      layer = "Tool";
      key = "Ctrl+W";
      action = "In nvim, close the file and keep nvim open. In the file tree, do nothing.";
      nvim = "keymaps.lua";
    }
    {
      layer = "Tool";
      key = "Ctrl+Y, Ctrl+N, Ctrl+P, Ctrl+Space, in insert mode";
      action = "In nvim, drive the completion: accept, next, previous, open.";
      nvim = "editing.lua";
    }
    {
      layer = "Tool";
      key = "gd, gD, Shift+F12, Ctrl+click";
      action = "In nvim, jump to the definition, list the definitions, list the references, jump with the mouse.";
      nvim = "lsp.lua";
    }
    {
      layer = "Tool";
      key = "Backslash, the leader";
      action = "First key of every nvim chord below. Spacebar lost as the leader.";
      nvim = "options.lua";
    }
    {
      layer = "Tool";
      key = "Leader d, q, w, x";
      action = "In nvim, read the diagnostics of the line, collect them in the loclist, write the file, close the file.";
      nvim = "keymaps.lua";
    }
    {
      layer = "Tool";
      key = "Leader f, then a key";
      action = "In nvim, the find group: diagnostics, files, grep, help, keymaps, resume, symbols, and the replace across the project.";
      nvim = "editing.lua";
    }
    {
      layer = "Tool";
      key = "Leader f, then q";
      action = "In nvim, the unified search of the fast tier over rg, qmd, and semble.";
      nvim = "search.lua";
    }
    {
      layer = "Tool";
      key = "Tab, Shift+Tab, in the grug-far panel";
      action = "Step through the fields of the panel, forward and back. Its steps cycle at each end, and no field is skipped.";
      nvim = "editing.lua";
    }
    {
      layer = "Tool";
      key = "Leader t, then t or f";
      action = "In nvim, toggle the file tree of every editor tab, or focus it on the current file.";
      nvim = "tree.lua";
    }
    {
      layer = "Tool";
      key = "H, in the tree window";
      action = "In the file tree, hide the dotfiles and the gitignored rows, and show them again.";
      nvim = "tree.lua";
    }
    {
      layer = "Tool";
      key = "Leader e, E";
      action = "In nvim, open yazi in the working directory, or at the current file.";
      nvim = "editing.lua";
    }
    {
      layer = "Tool";
      key = "Leader v, then a key";
      action = "In nvim, the review group: diff the file against the base, lazygit, hunk, the file list, tuicr.";
      nvim = "review.lua";
    }
    {
      layer = "Tool";
      key = "Leader r, then a key";
      action = "In nvim, the test group: file, last, output, nearest, summary, stop.";
      nvim = "test.lua";
    }
    {
      layer = "Tool";
      key = "Leader D, then a key";
      action = "In nvim, the debug group: breakpoint, continue, into, out, over, the debug UI.";
      nvim = "dap.lua";
    }

    {
      layer = "Prefix";
      key = "\"";
      action = "Split the window vertically, in the working directory of the pane.";
      comment = "the stock prefix stays for rare commands, the Option layer holds the frequent ones; open splits and windows in the current pane's directory";
      tmuxLines = [ ''bind '"' split-window -v -c "#{pane_current_path}"'' ];
    }
    {
      layer = "Prefix";
      key = "%";
      action = "Split the window horizontally, in the working directory of the pane.";
      tmuxLines = [ ''bind % split-window -h -c "#{pane_current_path}"'' ];
    }
    {
      layer = "Prefix";
      key = "c";
      action = "Open a new window, in the working directory of the pane.";
      tmuxLines = [ ''bind c new-window -c "#{pane_current_path}"'' ];
    }

    {
      layer = "Mouse";
      key = "Middle click on the status bar";
      action = "Kill the window under the pointer.";
      comment = "status bar as a tab bar, at the top: middle-click closes, double-click renames or opens a window";
      tmuxLines = [ "bind -n MouseDown2Status kill-window -t=" ];
    }
    {
      layer = "Mouse";
      key = "Double click on the status bar";
      action = "Rename the window under the pointer.";
      tmuxLines = [ ''bind -n DoubleClick1Status command-prompt -I "#W" "rename-window -- '%%'"'' ];
    }
    {
      layer = "Mouse";
      key = "Double click past the last window";
      action = "Open a new window.";
      tmuxLines = [ ''bind -n DoubleClick1StatusDefault new-window -c "#{pane_current_path}"'' ];
    }
    {
      layer = "Mouse";
      key = "Option and drag in a pane";
      action = "Select a rectangle.";
      comment = "Alt+drag selects a rectangle (columns of output)";
      tmuxLines = [
        "bind -n M-MouseDrag1Pane if -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -M ; send-keys -X rectangle-toggle'"
      ];
    }
    {
      layer = "Mouse";
      key = "Wheel in copy mode";
      action = "Scroll ten lines per step.";
      comment = "Alt+wheel scrolls ten lines at a time in copy mode";
      tmuxLines = [
        "bind -T copy-mode-vi M-WheelUpPane send-keys -N 10 -X scroll-up"
        "bind -T copy-mode-vi M-WheelDownPane send-keys -N 10 -X scroll-down"
      ];
    }
  ];
in
{
  inherit
    rows
    tmuxConfig
    fishConfig
    weztermKeys
    popupKeys
    popupText
    ;
}
