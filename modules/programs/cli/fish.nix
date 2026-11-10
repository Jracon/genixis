{
  config,
  lib,
  osConfig ? null, # the NixOS/nix-darwin config; absent in standalone homeConfigurations
  pkgs,
  ...
}:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  os = if osConfig == null then { } else osConfig;

  # plain-word commands are gated on the tool actually being there, not just the platform
  hasGraphicalDesktop = !isDarwin && (os.services.graphical-desktop.enable or false);
  hasPodman = os.virtualisation.podman.enable or false;

  # on Darwin only launchd starts the tmux server (tmux.nix): a server that a WezTerm starts loses the
  # LAN when that WezTerm quits. -N makes a client fail instead of starting one
  tmuxLabel = config.launchd.agents.tmux.config.Label;
  tmuxNoStart = lib.optionalString isDarwin "-N ";
  tmuxServerCheck = lib.optionalString isDarwin "tmux-server; or return";

  # nh shows a package diff before switching and elevates with sudo itself; `nh os` refuses to
  # run as root (servers log in as root), so skip elevation there instead
  rebuildFrom = flake: extraArgs: ''
    ${
      if isDarwin then
        "nh darwin switch ${flake} --hostname $argv[1] --impure ${extraArgs}"
      else
        ''
          set -l elevation
          fish_is_root_user; and set elevation --elevation-strategy none
          nh os switch ${flake} --hostname $argv[1] --impure $elevation ${extraArgs}''
    }
  '';
  rehomeFrom = flake: extraArgs: ''
    nh home switch ${flake} --configuration $argv[1] --backup-extension backup --impure ${extraArgs}
  '';

  # Forgejo is the origin, reachable on the LAN. The name also resolves off the LAN, through the
  # subnet route of the tailnet. Forgejo is unreachable from WSL behind the work VPN, so fall
  # back to the GitHub mirrors. The mirrors use git+https, since github: refs go through the
  # rate-limited GitHub API.
  # The lock still points themes at Forgejo, so redirect it to its mirror at the locked revision.
  # Nix caches which commit a branch URL points to for an hour (tarball-ttl), so --refresh makes a
  # rebuild right after a push build that push, not the commit an earlier rebuild saw
  remoteFlake = ''
    set -l flake git+https://forgejo.local.jracon.xyz/jracon/genixis
    set -l extra_args --refresh
    if not ${lib.getExe pkgs.curl} --head --max-time 3 --silent https://forgejo.local.jracon.xyz >/dev/null
      echo "Forgejo is unreachable; using the GitHub mirror" >&2
      set flake git+https://github.com/jracon/genixis
      set -l themes_rev (nix flake metadata --refresh $flake --json | ${lib.getExe pkgs.jq} --exit-status --raw-output .locks.nodes.themes.locked.rev)
      or return
      set extra_args --refresh -- --override-input themes "git+https://github.com/jracon/themes?rev=$themes_rev"
    end
  '';
in
{
  # default for every program's enableFishIntegration option
  home.shell.enableFishIntegration = true;

  programs.fish = {
    enable = true;

    functions = {
      # in an ide window, edit secrets in its nvim pane (ide-edit blocks until the buffer closes)
      agenix = ''
        if set -q IDE_NVIM_SOCK
          EDITOR=ide-edit command agenix $argv
        else
          command agenix $argv
        end
      '';
      # the tell side of the ask plumbing (issue #189): a fact for the claude
      # pane of this checkout; with no pane it lands in the shared memory of
      # the project. The binary owns the pane search and the paste
      btw = "command project btw $argv";
      cln = "nh clean all --keep 5 --keep-one";
      # with no file, open nvim's file picker
      e = ''
        if test (count $argv) -eq 0
          nvim +"FzfLua files"
        else
          nvim $argv
        end
      '';
      # fish calls this for the pane title: push the working directory, so the
      # home tab of a host window shows where its shell works and the title
      # follows a cd (issue #135); the tilde keeps the home directory short
      fish_title = ''
        if test "$PWD" = "$HOME"
            echo "~"
        else
            echo (string replace -- "$HOME/" "~/" "$PWD")
        end
      '';
      # the Go binary builds the ide window (`project ide`, see AGENTS.md); this stub adds the one
      # thing a child process cannot do: when a lone-pane window becomes the ide window, the shell
      # of the caller changes into the directory, which the binary writes to PROJECT_CD_FILE and
      # this stub reads after the binary ends
      ide = ''
        set -l cdfile (mktemp)
        set -lx PROJECT_CD_FILE $cdfile
        command project ide $argv
        set -l st $status
        if test -s $cdfile
            cd (cat $cdfile)
        end
        command rm -f $cdfile
        return $st
      '';
      # the standalone quick question (issue #189): one claude --print in this
      # checkout answers it, no pane and no live session involved; piped
      # stdin is its context
      lmk = "command project lmk $argv";
      # Nix refuses a git checkout that another user owns (root rebuilding from dev's checkout), so
      # read it as plain files there; a path: flake also takes untracked files and needs the repo root
      local-rebuild = ''
        set -l flake .
        test -O .; or set flake path:$PWD
      ''
      + rebuildFrom "$flake" "";
      rebuild = remoteFlake + rebuildFrom "$flake" "$extra_args";
      # unified search of the interactive prompt (issue #189): refresh the qmd
      # index, then fan out grouped over rg, qmd (BM25, no models), and semble,
      # each section truncated. The scores of the three are not comparable, so
      # results stay grouped, never fused. --deep runs qmd query with the
      # models, for when the fast tier finds nothing. Agents keep the routing
      # of the search skill; this wrapper serves the prompt only
      search = ''
        set -l deep no
        if set -q argv[1]; and contains -- $argv[1] --deep -d
            set deep yes
            set argv $argv[2..-1]
            if not set -q argv[1]
                echo "search: --deep needs a question" >&2
                return 2
            end
        end
        if not set -q argv[1]
            echo "search: give a query; --deep runs qmd query with the models" >&2
            return 2
        end
        set -l query (string join ' ' -- $argv)

        # qmd itself finds a project-local config by walking up from the cwd
        # (.qmd/index.yaml before .qmd/index.yml, first hit wins) and resolves
        # a relative collection path at the directory that holds .qmd, so the
        # wrapper walks the same way: the refresh and the empty wording of the
        # qmd section then also work from a subdirectory of a checkout, and
        # qmd update and qmd embed run in place, at the cwd
        set -l qmd_index
        set -l qmd_dir (pwd -P)
        while true
            if test -f $qmd_dir/.qmd/index.yaml
                set qmd_index $qmd_dir/.qmd/index.yaml
                break
            else if test -f $qmd_dir/.qmd/index.yml
                set qmd_index $qmd_dir/.qmd/index.yml
                break
            end
            test $qmd_dir = /; and break
            set qmd_dir (dirname $qmd_dir)
        end

        # a per-request refresh (issue #189), before both tiers: qmd update and
        # qmd embed are cheap (about 0.2 s, 1.5 s after a change), and a stale
        # or empty index is the silent failure this wrapper exists to end. A
        # cold first build pays model time per chunk, so one line says the
        # refresh runs before it goes quiet
        if command -q qmd; and set -q qmd_index[1]
            echo "search: refreshing the qmd index" >&2
            qmd update >/dev/null 2>&1; or echo "search: qmd update failed; qmd results can be stale" >&2
            qmd embed >/dev/null 2>&1; or echo "search: qmd embed failed; recent text stays out of the deep tier" >&2
        end

        if test $deep = yes
            if not command -q qmd
                echo "search: --deep runs qmd query, and qmd is not installed" >&2
                return 1
            end
            qmd query $query
            return
        end

        set -l hits 0
        set -l out

        echo (set_color --bold)'rg'(set_color normal)
        if not command -q rg
            set out "rg is not installed"
        else
            set out (command rg --smart-case --line-number --no-heading --max-count 3 -- $query | head -n 12)
            if set -q out[1]
                set hits (math $hits + 1)
            else
                set out "(no matches)"
            end
        end
        printf '%s\n' $out

        echo (set_color --bold)'qmd'(set_color normal)
        if not command -q qmd
            set out "qmd is not installed"
        else
            set out (qmd search $query -n 10)
            # qmd answers an empty index with its "No results found" marker,
            # not with silence (issue #189); the current qmd ends the marker
            # with a period (issue #275), and the period-less form of an older
            # qmd stays accepted; drop it, so it never counts as one result
            if set -q out[1]; and contains -- "$out[1]" "No results found" "No results found."
                set -e out[1]
            end
            if set -q out[1]
                set hits (math $hits + 1)
            else if set -q qmd_index[1]
                set out "(no matches)"
            else
                set out "(no matches; this tree holds no .qmd index)"
            end
        end
        printf '%s\n' $out

        echo (set_color --bold)'semble'(set_color normal)
        if not command -q semble
            set out "semble is not installed"
        else
            set out (semble search $query --content all -k 5 --format text)
            if set -q out[1]
                set hits (math $hits + 1)
            else
                set out "(no matches)"
            end
        end
        printf '%s\n' $out

        if test $hits -eq 0
            echo (set_color yellow)"no fast results; try the deep tier:"(set_color normal) "search --deep $query" >&2
            return 1
        end
      '';
      # bare `tmux` attaches to (or creates) session main, or ssh over ssh so a remote login doesn't
      # join the local terminal's session; subcommands like `tmux ls` pass through. launchd doesn't own
      # a socket that -L or -S names, so those stay free to start a server on Darwin
      tmux = ''
        if test (count $argv) -eq 0
          ${tmuxServerCheck}
          command tmux ${tmuxNoStart}new -As (set -q SSH_CONNECTION; and echo ssh; or echo main)
        ${lib.optionalString isDarwin ''
          else if not contains -- "$argv[1]" -L -S
            command tmux -N $argv
        ''}
        else
          command tmux $argv
        end
      '';
    }
    // lib.optionalAttrs isDarwin {
      # pipe stdin to the clipboard: inside tmux, `load-buffer -w` fills the paste buffer and also
      # pushes it to the outer terminal with OSC 52 (set-clipboard is on in tmux.nix), so through a
      # session tab the text lands on the Mac that shows the window; pbcopy covers the rest
      clip = ''
        if set -q TMUX
          command tmux load-buffer -w -
        else
          command pbcopy
        end
      '';
      # pbpaste sees what OSC 52 wrote and what Cmd+C copied
      paste = "command pbpaste";
      # succeeds when the default socket has a server; `start-server` with -N only asks
      tmux-server = ''
        command tmux -N start-server 2>/dev/null; and return
        echo "tmux: no server; launchd starts it. Run `launchctl kickstart gui/$(id -u)/${tmuxLabel}`, or read ~/Library/Logs/tmux-server.log" >&2
        return 1
      '';
    }
    # no pbcopy/pbpaste on Linux: clip emits the OSC 52 sequence itself, and paste reads the tmux
    # paste buffer
    // lib.optionalAttrs (!isDarwin) {
      # only a terminal takes the escape bytes: a headless session has none, and a redirected pipe
      # would pass them on as data. The three writes keep base64 on the function's stdin: a fish
      # command substitution does not see the pipe into the caller
      clip = ''
        if set -q TMUX
          command tmux load-buffer -w -
        else if test -t 1
          printf '\033]52;c;'
          command base64 -w0
          printf '\007'
        else
          echo "clip: no tmux session and stdout is no terminal" >&2
          return 1
        end
      '';
      # WezTerm answers no OSC 52 read query, so outside tmux no clipboard is readable
      paste = ''
        if set -q TMUX
          command tmux save-buffer -
        else
          echo "paste: no tmux session; OSC 52 cannot read a clipboard" >&2
          return 1
        end
      '';
    }
    // lib.optionalAttrs hasPodman {
      lgs = "journalctl --follow --unit podman-$argv[1]";
    }
    # NixOS/Darwin hosts apply Home Manager through rebuild; only standalone setups need rehome
    // lib.optionalAttrs (!config.submoduleSupport.enable) {
      local-rehome = rehomeFrom "." "";
      rehome = remoteFlake + rehomeFrom "$flake" "$extra_args";
    };
    generateCompletions = true;
    # plain-word commands: abbreviations expand to the real command as you type, so you still
    # learn the underlying tool and history records it; they only apply at the start of a command
    shellAbbrs = {
      b = "y"; # yazi
      dl = "delta";
      g = "z"; # zoxide; `zi` for an interactive picker
      iss = "gh issue list";
      json = "jq";
      l = "fd";
      lg = "lazygit";
      monitor = "btm";
      prc = "gh pr checkout";
      prs = "gh pr list";
      r = "bat";
    }
    // lib.optionalAttrs config.programs.lazydocker.enable {
      ld = "lazydocker";
    }
    // lib.optionalAttrs hasGraphicalDesktop {
      open = "xdg-open"; # macOS has its own open
    };
    interactiveShellInit = ''
      # the default greeting stays off: the fastfetch panel at the end of
      # this init is the greeting (docs/terminal-aesthetic.md)
      set fish_greeting

      # the transient prompt of fish 4.1 (docs/terminal-aesthetic.md): before
      # fish runs a command, it re-renders the prompt with a final-rendering
      # argument, and that rendering prints the character alone in its status
      # colour. Home Manager writes this init before the starship integration,
      # so the starship init runs here first and the wrapper copies the prompt
      # it defined; the copy keeps its timing handlers for the command
      # duration. __genixis_restore puts the exit status back, because starship
      # reads the status at its entry and every command of the wrapper
      # overwrites it
      if test "$TERM" != dumb
          ${lib.getExe pkgs.starship} init fish | source
          functions --copy fish_prompt __genixis_full_prompt
          function __genixis_restore
              return $argv[1]
          end
          function fish_prompt
              set -l st $status
              if set -q argv[1]; and test $argv[1] = --final-rendering
                  if test $st -eq 0
                      set_color --bold green
                  else
                      set_color --bold red
                  end
                  printf '> '
                  set_color normal
              else
                  __genixis_restore $st
                  __genixis_full_prompt $argv
              end
          end
          set -g fish_transient_prompt 1
      end

      # WezTerm types Enter + Ctrl-D into a pane it closes (Cmd+Q); under tmux the client forwards them
      # to the focused pane, so there Ctrl-D only deletes and never exits the shell (use `exit`)
      if set -q TMUX
        bind ctrl-d delete-char
      end

      # word movement of the Tool layer of the keymap (see docs/keymap.md): inside tmux, Option+arrows
      # move between panes, so these Shift+arrows carry the word movement that replaces the
      # directory-history keys (WezTerm's CSI-u encoding keeps the modifier through tmux)
      bind shift-left backward-word
      bind shift-right forward-word
    ''
    + lib.optionalString (!isDarwin) ''
      # automatically start tmux session; PROJECT_HOME_TAB marks a tab that must
      # keep a plain shell and join no session (issue #134), and a detach in a
      # session tab must not start a second attach (issue #142)
      if not set -q TMUX; and not set -q PROJECT_HOME_TAB
        tmux
      end
    ''
    # the fastfetch panel is the greeting of every interactive shell
    # (docs/terminal-aesthetic.md, issue #297). It runs after the tmux
    # block above: an attach redraws the pane, so a print before it would
    # wipe the panel of the outer shell, and the shell that a detach
    # returns to greets too. A dumb terminal and a host without fastfetch
    # skip the panel.
    + ''
      if test "$TERM" != dumb; and type -q fastfetch
          fastfetch
      end
    '';
    # drop-in replacements keep the familiar name (ls/ll/la/lt come from programs.eza)
    shellAliases.cat = "bat";
  };
}
