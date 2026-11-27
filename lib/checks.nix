{
  self,
  pkgs,
  caddy ? pkgs.caddy,
  nixosSystem,
}:
let
  # one gate check: the script fails its derivation on a finding, so the gate
  # step of the workflow and nix flake check run it as a gate (docs/ci.md)
  check =
    name: tools: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = tools;
      }
      ''
        ${script}
        touch $out
      '';

  # one report check: the script writes the report to the derivation output
  # and never fails, so the gate stays green and the reports job prints it
  report =
    name: tools: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = tools;
      }
      ''
        ${script}
      '';

  # the three workflow files of the forge, the subset of the yaml rows
  # that actionlint gates
  workflowFiles = [
    "${self}/.forgejo/workflows/check-commit-subjects.yaml"
    "${self}/.forgejo/workflows/ci.yaml"
    "${self}/.forgejo/workflows/update-flake.yaml"
  ];

  # the yaml files of the format and lint rows: the workflows of the
  # forge, the docs index, and the one deployed service config of the
  # container tree. The qmd index of a checkout stays out, because a
  # tool config file carries the format of its tool, and the ruling on
  # those files is open (issue 426)
  yamlFiles = workflowFiles ++ [
    "${self}/mkdocs.yml"
    "${self}/modules/virtualisation/oci-containers/media-servers/romm/config.yaml"
  ];

  # the one script of the forge: the shellcheck and shfmt rows gate it
  # beside the scripts of the media-servers group
  forgeScript = "${self}/.forgejo/scripts/check-commit-subjects.sh";
in
{
  # an unused let binding is dead code; module argument names stay out of the
  # check, because a module declares its interface through them
  deadnix = check "deadnix" [ pkgs.deadnix ] ''
    deadnix --fail --no-lambda-arg --no-lambda-pattern-names ${self}
  '';

  # the empty-pattern rule is off, because the module header convention
  # writes a no-argument module as `{ ... }:` (lib/statix.toml)
  statix = check "statix" [ pkgs.statix ] ''
    statix check --config ${./statix.toml} ${self}
  '';

  # the go module imports nothing outside the standard library, so both
  # analyzers need no network (modules/programs/cli/project/go.mod); cgo
  # stays off, because the check sandbox holds no C compiler
  go-vet = check "go-vet" [ pkgs.go ] ''
    export HOME="$TMPDIR" GOCACHE="$TMPDIR/go-cache" GOTOOLCHAIN=local CGO_ENABLED=0
    cd ${self}/modules/programs/cli/project
    go vet ./...
  '';

  staticcheck =
    check "staticcheck"
      [
        pkgs.go
        pkgs.go-tools
      ]
      ''
        export HOME="$TMPDIR" GOCACHE="$TMPDIR/go-cache" GOTOOLCHAIN=local CGO_ENABLED=0
        cd ${self}/modules/programs/cli/project
        staticcheck ./...
      '';

  # the rule set stays pinned, because the default set of a new ruff
  # release carries opinion rules, and a rule upgrade must not redden
  # the gate on its own. The pydocstyle group D gates the docstrings of
  # the corpus (issue 710), and each ignore of the group names its
  # reason in one line below, the pattern of lib/yamllint.yaml: the
  # plain prose dialect of the corpus is the recorded standard (issue
  # 676, candidate line 14), and the rules that fight that dialect stay
  # off while the rest of the group shapes the docstrings. The D203 and
  # D213 ignores pin the twin choice of two rule pairs that contradict
  # each other, so a ruff release cannot flip the choice on its own.
  # The probe fixture proves the teeth, the drift fixture pattern of
  # the format rows: a module without a docstring must fail the row
  ruff = check "ruff" [ pkgs.ruff ] ''
    set -eu
    # D203 is off: the inverted twin of D211 (a blank line before a
    # class docstring), and the corpus sets no blank line
    # D205 is off: the corpus wraps each summary across lines as one
    # paragraph, and a forced blank line after the first line would cut
    # a wrapped sentence in two
    # D213 is off: the inverted twin of D212 (the summary starts on the
    # second line), and the corpus opens each summary on the first line
    # D401 is off: the corpus describes in plain prose ("The ...",
    # "True when ..."), and the imperative mood is the rejected class
    # of the standards record (issue 676, issue 710)
    flags="--select E4,E7,E9,F,D --ignore D203,D205,D213,D401"
    printf 'X = 1\n' >"$TMPDIR/probe.py"
    if ruff check $flags "$TMPDIR/probe.py" >/dev/null; then
      echo "FAIL self-test: ruff reports no missing docstring on the probe module" >&2
      exit 1
    fi
    ruff check $flags ${self}/modules/programs/cli/claude ${self}/modules/services/dispatcher
  '';

  # the python format gate of the harnesses: ruff format runs with its
  # defaults, and the flake lock pins the ruff release that carries them,
  # the same tool as the ruff lint check above. The drift fixture proves
  # that the check mode fails on a misformatted input (issue 426,
  # acceptance criterion 2)
  ruff-format =
    check "ruff-format"
      [
        pkgs.findutils
        pkgs.ruff
      ]
      ''
        set -eu
        printf 'print( "hi" )\n' >"$TMPDIR/drift.py"
        if ruff format --check "$TMPDIR/drift.py" >/dev/null; then
          echo "FAIL self-test: ruff format reports no drift on the fixture" >&2
          exit 1
        fi
        while IFS= read -r file; do
          if ! ruff format --check "$file" >/dev/null; then
            echo "FAIL formatting drift: $file" >&2
            ruff format --diff "$file" >&2 || true
            exit 1
          fi
        done < <(find ${self}/modules/programs/cli/claude ${self}/modules/services/dispatcher -name '*.py')
      '';

  # the python dead-code gate of the harnesses: vulture reads the
  # corpus in one pass, so it names a module-level function or class that
  # no file reaches, which the file-local ruff rules of the lint check
  # above cannot see. The minimum confidence and the whitelist file are
  # the pinned configuration, the pattern of the ruff rule set: the
  # whitelist holds each reference that a static read cannot see, with
  # its reason in one line (issue 434)
  vulture = check "vulture" [ pkgs.python3Packages.vulture ] ''
    vulture --min-confidence 60 \
      ${self}/modules/programs/cli/claude \
      ${self}/modules/services/dispatcher \
      ${./vulture-whitelist.py}
  '';

  # the python type gate of the harnesses: basedpyright
  # type-checks the same corpus as the ruff rows, with the checking
  # level and the python version pinned in lib/pyrightconfig.json, the
  # pattern of lib/statix.toml. The level is basic, because the
  # standard level of basedpyright raises the missing generic type
  # arguments and the unknown-type rules to errors, and the harnesses
  # carry no annotations. The devShell and the nvim language server
  # carry the same checker, so the editor and the gate use one tool
  # and a finding shows in both
  basedpyright = check "basedpyright" [ pkgs.basedpyright ] ''
    basedpyright --project ${./pyrightconfig.json} \
      ${self}/modules/programs/cli/claude \
      ${self}/modules/services/dispatcher
  '';

  # the yaml lint gate of the row files: the rules live in
  # lib/yamllint.yaml, pinned, the pattern of lib/statix.toml. The key
  # check of the truthy rule is off, because the workflows name their
  # event keys on and off, which the rule reads as booleans
  # (issue 426, acceptance criterion 3)
  yamllint = check "yamllint" [ pkgs.yamllint ] ''
    yamllint -c ${./yamllint.yaml} ${toString yamlFiles}
  '';

  # the yaml format gate of the same files: prettier prints the formatted
  # form of a file to stdout and writes nothing, so the check compares the
  # two forms. The settings live in .prettierrc.yaml at the root, pinned.
  # The drift fixture proves that the comparison fails on a misformatted
  # input (issue 426, acceptance criterion 2)
  prettier =
    check "prettier"
      [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.prettier
      ]
      ''
        set -eu
        cfg=${self}/.prettierrc.yaml
        is_formatted() {
          prettier --config "$cfg" "$1" | cmp -s - "$1"
        }
        printf 'a:   1\n' >"$TMPDIR/drift.yaml"
        if is_formatted "$TMPDIR/drift.yaml"; then
          echo "FAIL self-test: prettier reports no drift on the fixture" >&2
          exit 1
        fi
        for file in ${toString yamlFiles}; do
          if ! is_formatted "$file"; then
            echo "FAIL formatting drift: $file" >&2
            prettier --config "$cfg" "$file" | diff -u "$file" - >&2 || true
            exit 1
          fi
        done
      '';

  # the workflow structure gate: actionlint validates the action and
  # expression syntax of the three workflow files of the forge. The
  # runner label lives in lib/actionlint.yaml, pinned, the pattern of
  # lib/yamllint.yaml, and this invocation is the rest of the pinned
  # configuration, the pattern of the ruff rule set: the ignore flag
  # passes the forgejo event context, which the github schema of
  # actionlint does not know, and the empty shellcheck and pyflakes
  # values keep the row structural, because the run blocks of the
  # workflows sit outside the gap of this row and their shellcode is
  # deliberate
  actionlint = check "actionlint" [ pkgs.actionlint ] ''
    actionlint \
      -config-file ${./actionlint.yaml} \
      -ignore 'undefined variable "forgejo"' \
      -shellcheck= \
      -pyflakes= \
      ${toString workflowFiles}
  '';

  # the Caddyfile gate: caddy fmt previews the formatted form on stdout and
  # exits nonzero on a drifted input, so the check compares the two forms,
  # and caddy validate proves that the file loads as a caddy config. The
  # tool is the plugin build of flake.nix, because the file names the
  # cloudflare dns module and stock caddy refuses the file at parse time;
  # the deployed image carries the same module (issue 426, acceptance
  # criterion 2)
  caddy =
    check "caddy"
      [
        caddy
        pkgs.coreutils
      ]
      ''
        set -eu
        export XDG_DATA_HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR"
        # validate provisions the dns provider, which requires a token of
        # the deployed 40-character shape, with no network. The placeholder
        # repeats one character at runtime, because the secrets check flags
        # every token-shaped or key-shaped literal in the tree; the real
        # token stays in environment.age
        export CF_API_TOKEN="$(printf 'a%.0s' {1..40})"
        file=${self}/modules/virtualisation/oci-containers/caddy/Caddyfile
        printf ':80 {\nrespond "hi"\n}\n' >"$TMPDIR/drift.caddy"
        if caddy fmt "$TMPDIR/drift.caddy" | cmp -s - "$TMPDIR/drift.caddy"; then
          echo "FAIL self-test: caddy fmt reports no drift on the fixture" >&2
          exit 1
        fi
        if ! caddy fmt "$file" | cmp -s - "$file"; then
          echo "FAIL formatting drift: $file" >&2
          exit 1
        fi
        caddy validate --config "$file" --adapter caddyfile >/dev/null
      '';

  # the lua tree reads the api of neovim through the global `vim`
  luacheck = check "luacheck" [ pkgs.luajitPackages.luacheck ] ''
    luacheck --globals vim --max-line-length 120 ${self}/modules/programs/cli/neovim/lua
  '';

  # the bash format gate of the media-servers scripts and the commit
  # subject script: shfmt prints the formatted form to stdout and
  # writes nothing, so the check compares the two forms. The flags are
  # the pinned style, because the shfmt default moved to spaces and the
  # scripts hold tabs: -i 0 keeps the tab indent of the tree. The drift
  # fixture proves that the comparison fails on a misformatted input,
  # so a green gate also says that the check has teeth
  # (issue 426, acceptance criterion 2)
  shfmt =
    let
      scripts = "${self}/modules/virtualisation/oci-containers/media-servers/scripts";
    in
    check "shfmt"
      [
        pkgs.coreutils
        pkgs.shfmt
      ]
      ''
        set -eu
        is_formatted() {
          shfmt -i 0 "$1" | cmp -s - "$1"
        }
        printf 'if true;then echo hi;fi\n' >"$TMPDIR/drift.sh"
        if is_formatted "$TMPDIR/drift.sh"; then
          echo "FAIL self-test: shfmt reports no drift on the fixture" >&2
          exit 1
        fi
        for script in "${scripts}"/*.sh ${forgeScript}; do
          if ! is_formatted "$script"; then
            echo "FAIL formatting drift: $script" >&2
            shfmt -i 0 -d "$script" >&2 || true
            exit 1
          fi
        done
      '';

  # the bash lint gate of the media-servers scripts and the commit
  # subject script: shellcheck runs at its default severity, and this
  # invocation is the pinned configuration, the pattern of the ruff
  # rule set above. A directive inside a script states its own
  # exception, as clean.sh does for SC2053
  shellcheck = check "shellcheck" [ pkgs.shellcheck ] ''
    shellcheck ${self}/modules/virtualisation/oci-containers/media-servers/scripts/*.sh ${forgeScript}
  '';

  # the lua format gate of the nvim tree: the settings live in .stylua.toml
  # at the root, pinned to the conventions that the tree already holds, and
  # the devShell carries stylua, so a person runs the identical pass by
  # hand. The drift fixture proves that the comparison fails on a
  # misformatted input (issue 426, acceptance criterion 2)
  stylua =
    let
      luaTree = "${self}/modules/programs/cli/neovim/lua";
    in
    check "stylua"
      [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.findutils
        pkgs.stylua
      ]
      ''
        set -eu
        cfg=${self}/.stylua.toml
        is_formatted() {
          cat "$1" >"$TMPDIR/one.lua"
          stylua --config-path "$cfg" "$TMPDIR/one.lua"
          cmp -s "$1" "$TMPDIR/one.lua"
        }
        printf 'local  x  ={1,2}\n' >"$TMPDIR/drift.lua"
        if is_formatted "$TMPDIR/drift.lua"; then
          echo "FAIL self-test: stylua reports no drift on the fixture" >&2
          exit 1
        fi
        while IFS= read -r file; do
          if ! is_formatted "$file"; then
            echo "FAIL formatting drift: $file" >&2
            cat "$file" >"$TMPDIR/drift-copy.lua"
            stylua --config-path "$cfg" "$TMPDIR/drift-copy.lua"
            diff -u "$file" "$TMPDIR/drift-copy.lua" >&2 || true
            exit 1
          fi
        done < <(find "${luaTree}" -name '*.lua')
      '';

  # the documentation sweep of the gate: cited paths must resolve, the
  # files must be listed in AGENTS.md, every record file must sit in the
  # register index, and the two writing rules hold
  # (docs/adr/deep-homes-of-subsumed-products.md, docs/adr/gate-writing-rules.md)
  docs =
    check "docs"
      [
        pkgs.findutils
        pkgs.gnugrep
      ]
      ''
        set -eu
        cd "${self}"
        missing=0
        # the record files of docs/adr are exempt as citation sources,
        # because each record is append-only and names historical paths
        for p in $(grep -rhoE 'docs/([a-z0-9-]+/)?[a-z0-9-]+\.md' . \
            --include='*.nix' --include='*.go' --include='*.py' --include='*.md' \
            --exclude-dir=adr | sort -u); do
          test -f "$p" || { echo "missing: $p"; missing=1; }
        done
        for f in docs/*.md; do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        for f in docs/adr/*.md; do
          grep -q "$f" docs/decisions.md || { echo "unindexed: $f"; missing=1; }
        done
        for f in $(find modules -name README.md); do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        # a citation carries no line number, and each sub-list item is
        # lettered; docs/decisions.md is exempt, because the index and the
        # rejected list are append-only, and the record files of docs/adr
        # sit outside the glob of this loop for the same reason
        for f in docs/*.md AGENTS.md; do
          case "$f" in docs/decisions.md) continue ;; esac
          grep -nE '\.(md|nix|go|py|lua|sh|awk|json|ya?ml|toml|age|pub):[0-9]+' "$f" && missing=1 || true
          grep -nE '^ +([-*+]|[0-9]+\.) ' "$f" && missing=1 || true
        done
        test "$missing" -eq 0
      '';

  # the citation-resolution gate of the dispatcher reference: the
  # reference cites its own numbered lists by number in prose, and a
  # citation that a list change strands must fail the gate before a
  # reader follows it (issue 575 names the drift, issue 577 the row,
  # issue 587 the surfaces). The row reads the two cited lists of the
  # reference and resolves each citation back against its list: `rule N`
  # names an item of the Dispatcher rules list, and `machine decision N`
  # names an item of the Machine decisions list. Each cited number must
  # name an existing item, and each list must number its items from one
  # with no gap and no duplicate, because a citation resolves against
  # the source number, not against a rendered one. The sweep joins each
  # wrapped line with the next one, because a citation breaks at a line
  # end of the reference: the line-wrapped citation of machine decision
  # 23 sat outside the line-based inventory of the issue, so a
  # line-based row inherits the under-detection of the manual sweeps. A
  # blank line, an item start, and a heading end the join, so the join
  # cannot mint a citation that spans a boundary. The sweep is
  # case-insensitive, because a citation at a sentence head carries a
  # capital, and the missed citation of the manual sweep of issue 575
  # was the capitalized one. The row also scans each live citation
  # surface outside the reference, the inventory of issue 587: the two
  # surfaces are the dispatcher code, whose comment block cites machine
  # decision 25 across a line end and whose prompt-builder docstring
  # cites machine decision 29, and this file, whose comments cite the
  # history of the row by number. The count of the issue named one live
  # citation, and a count is no inventory: the tree-wide sweep of the
  # leg found the surfaces, and the row scans the surfaces of that
  # inventory. A surface joins under its own grammar: a blank line ends
  # the join, a comment line joins the comment line above it with its
  # marker stripped, so a citation that wraps inside one comment block
  # still resolves, and a change between comment and plain text ends
  # the join, so the join cannot mint a citation that spans a comment
  # boundary. The sweep of the whole tree stays out, because the
  # citation words also match the prose of the append-only records, and
  # that trade has no ruling (issue 587, alternative 2). The
  # stranded-citation fixtures prove the teeth, the drift fixture
  # pattern of the format rows: a copy of the reference whose Machine
  # decisions list lost its two last items strands the citations of
  # item 29, a copy of the dispatcher code whose wrapped citation
  # names a number past the end of the list strands the citation of
  # the comment block, and a copy whose docstring citation does the
  # same for the plain-text scan, and the resolver must fail on each
  # copy. The program
  # uses the gawk ARGIND and ENDFILE, because one pass collects the
  # lists, one pass scans the reference, and one pass scans each
  # surface, all in one program. The row catches no in-range drift: an
  # insertion above a citation shifts it onto the wrong item inside the
  # range of the list, and that class stays with review, as does a
  # citation on a file that the surface list of this row does not name
  dispatcher-citations =
    let
      # the live citation surfaces outside the reference, the inventory
      # of issue 587. A file that joins this list scans under the
      # citation grammar of the row
      surfaces = [
        "${self}/modules/services/dispatcher/dispatcher.py"
        "${self}/lib/checks.nix"
      ];
    in
    check "dispatcher-citations" [ pkgs.gawk ] ''
      set -eu
      ref=${self}/modules/services/dispatcher/README.md

      # the resolver: one awk program over the reference and its
      # citation surfaces. The first pass collects the items of the two
      # lists, the second pass lays the reference out flat for the
      # citation scan, and each later pass scans one citation surface
      # the same way. The flat copy of each file maps every position
      # back to its source line, so a citation that wraps names the
      # line it starts on
      resolve() {
        awk '
          ARGIND == 1 {
            if ($0 ~ /^## /) {
              section = substr($0, 4)
              if (section == "Dispatcher rules" || section == "Machine decisions")
                seen[section] = 1
              next
            }
            if (section == "Dispatcher rules" || section == "Machine decisions") {
              if (match($0, /^[0-9]+\. /)) {
                n = substr($0, 1, RLENGTH - 2) + 0
                items[section "," n]++
                if (n > top[section]) top[section] = n
              }
            }
            next
          }
          ARGIND == 2 {
            if (FNR > 1 && ($0 == "" || $0 ~ /^[0-9]+\. / || $0 ~ /^#/))
              flat = flat "\n"
            start[FNR] = length(flat) + 1
            len[FNR] = length($0)
            flat = flat $0 " "
            next
          }
          {
            text = $0
            iscom = text ~ /^[ \t]*#/
            if (iscom)
              sub(/^[ \t]*#[ \t]*/, "", text)
            if (FNR > 1 && ($0 == "" || iscom != wascom))
              flat = flat "\n"
            wascom = iscom
            start[FNR] = length(flat) + 1
            len[FNR] = length(text)
            flat = flat text " "
          }
          function line_of(pos,    i) {
            for (i = 1; i <= FNR; i++)
              if (pos <= start[i] + len[i]) return i
            return FNR
          }
          function collect(pattern, wordcut, label,    scan, word, before, abs) {
            scan = lower
            consumed = 0
            while (match(scan, pattern)) {
              word = substr(scan, RSTART, RLENGTH)
              abs = consumed + RSTART
              before = abs == 1 ? "" : substr(lower, abs - 1, 1)
              if (before !~ /[a-z]/) {
                cites++
                kind[cites] = label
                num[cites] = substr(word, wordcut) + 0
                line[cites] = line_of(abs)
                src[cites] = srcname
              }
              consumed += RSTART + RLENGTH - 1
              scan = substr(scan, RSTART + RLENGTH)
            }
          }
          ENDFILE {
            if (ARGIND > 1) {
              lower = tolower(flat)
              srcname = FILENAME
              sub(/.*\//, "", srcname)
              collect("machine decision [0-9]+", 18, "machine decision")
              collect("rule [0-9]+", 6, "rule")
              flat = ""
              delete start
              delete len
              wascom = 0
            }
          }
          END {
            bad = 0
            secs[1] = "Dispatcher rules"
            secs[2] = "Machine decisions"
            for (i = 1; i <= 2; i++) {
              sec = secs[i]
              if (!seen[sec]) {
                print "FAIL missing list: the " sec " section holds no numbered list" > "/dev/stderr"
                bad = 1
                continue
              }
              if (top[sec] + 0 < 1) {
                print "FAIL empty list: the " sec " section holds no numbered item" > "/dev/stderr"
                bad = 1
                continue
              }
              for (n = 1; n <= top[sec]; n++) {
                c = items[sec "," n] + 0
                if (c == 0) {
                  printf "FAIL list gap: the %s list numbers no item %d\n", sec, n > "/dev/stderr"
                  bad = 1
                } else if (c > 1) {
                  printf "FAIL list duplicate: the %s list numbers item %d %d times\n", sec, n, c > "/dev/stderr"
                  bad = 1
                }
              }
            }
            for (c = 1; c <= cites; c++) {
              sec = kind[c] == "rule" ? "Dispatcher rules" : "Machine decisions"
              if (!seen[sec] || num[c] < 1 || num[c] > top[sec] + 0) {
                printf "FAIL stranded citation: %s line %d cites %s %d; the list holds %d items\n", src[c], line[c], kind[c], num[c], top[sec] + 0 > "/dev/stderr"
                bad = 1
              }
            }
            exit bad
          }
        ' "$1" "$1" ''${@:2}
      }

      # the teeth of the reference: a copy of the reference whose
      # Machine decisions list lost its two last items strands the
      # citations of item 29, and the resolver must fail on the copy
      awk '
        /^## / { section = $0 }
        section == "## Machine decisions" && /^[0-9]+\. / {
          match($0, /^[0-9]+/)
          drop = substr($0, 1, RLENGTH) + 0 >= 29
          if (drop) next
        }
        drop && /^## / { drop = 0 }
        drop { next }
        { print }
      ' "$ref" >"$TMPDIR/stranded.md"
      if resolve "$TMPDIR/stranded.md" ${toString surfaces}; then
        echo "FAIL self-test: the resolver passed a stranded citation" >&2
        exit 1
      fi

      # the teeth of the surfaces: a copy of the dispatcher code whose
      # wrapped citation of machine decision 25 names a number past the
      # end of the list, and the resolver must fail on the copy, so the
      # marker-stripping join of the surface scan has teeth
      awk '{ gsub(/# 25\)/, "# 98)"); print }' \
        ${self}/modules/services/dispatcher/dispatcher.py >"$TMPDIR/stranded.py"
      if resolve "$ref" "$TMPDIR/stranded.py"; then
        echo "FAIL self-test: the resolver passed a stranded citation" >&2
        exit 1
      fi

      # the teeth of the docstring citation: a copy of the dispatcher
      # code whose docstring citation of item 29 names a number past
      # the end of the list, and the resolver must fail on the copy, so
      # the plain-text scan of a surface has teeth. The pattern reads
      # no citation words, because this file is a surface of its own
      # row: a matchable fixture literal here would strand itself
      awk '{ gsub(/decision 29 of the README/, "decision 99 of the README"); print }' \
        ${self}/modules/services/dispatcher/dispatcher.py >"$TMPDIR/stranded-docstring.py"
      if resolve "$ref" "$TMPDIR/stranded-docstring.py"; then
        echo "FAIL self-test: the resolver passed a stranded citation" >&2
        exit 1
      fi

      resolve "$ref" ${toString surfaces}
    '';

  # the wire-contract gate of the sandbox tier units (issue 607): the tier
  # module authors the two leg templates and the polkit delegation, the
  # dispatcher starts and stops their instances, and the two sides live in
  # different languages, so no import binds the shape. The leg units run on
  # the system manager, because only it enforces the IP firewall, and the
  # delegation is scoped to the two template names and the two verbs, so
  # every clause of that scope is load-bearing. The check reads the
  # evaluated unit files of the services host and the evaluated polkit
  # rules, the evaluated-tree read of port-claims, so a drift of the tier
  # side fails the gate before a rebuild ships it. The guards on the leg
  # unit: User=dev, the forking service with the cgroup exit type that
  # keeps the unit alive while the supervisor of the leg runs (issue 634),
  # the deny entry, one address prefix of each allow entry (the
  # transient-unit property path of systemd-run parses prefixes only, and
  # the symbolic token localhost killed the first tier spawn of 2026-11-21
  # 10:52 before its unit existed), the read-only agenix token bind under
  # /run/user (ProtectHome=tmpfs hides the target, and the plans check of
  # the first tier run after the rebuild of 2026-11-21 12:47 died on the
  # dangling link), the request executor in ExecStart, and the append
  # output paths of the spawn streams. Both units must carry one finite
  # MemoryHigh bound and one finite MemoryMax bound each, because the
  # units run on the system manager and the user-slice cap of the
  # spawn-storm layers bounds no leg (issue 672). The agent unit must
  # carry the deny entry with no allow entry, because both access lists
  # default to empty and the agent answers no network address. The
  # guards on the rules: the action, the subject, the unit lookup, the
  # verb lookup with the
  # start-and-stop-only gate (SetUnitProperties rides the same action with
  # the verb set-property, and a grant without the verb gate would let a
  # dev process rewrite the bounds of a running leg), and the template name
  # regex. Six fixtures prove the teeth: a symbolic allow token, a
  # tokenless bind, a rules file without the verb gate, a rules file
  # that names every unit, a leg unit without its MemoryMax bound, and
  # a leg unit with MemoryMax at infinity, the live state of the
  # incident of issue 672
  leg-units =
    let
      servicesHost = self.nixosConfigurations.services.config;
      legUnit = "${servicesHost.systemd.units."leg-unit@.service".unit}/leg-unit@.service";
      agentUnit = "${servicesHost.systemd.units."leg-agent@.service".unit}/leg-agent@.service";
      rulesFile =
        pkgs.writeText "10-nixos.rules"
          servicesHost.environment.etc."polkit-1/rules.d/10-nixos.rules".text;
    in
    check "leg-units" [ pkgs.python3 ] ''
      set -eu
      rules_names='org.freedesktop.systemd1.manage-units
      subject.user
      action.lookup("unit")
      action.lookup("verb")
      verb != "start" && verb != "stop"
      leg-(unit|agent)@'
      probe() {
        python3 -c '
          import ipaddress
          import re
          import sys
          unit = open(sys.argv[1], encoding="utf-8").read()
          agent = open(sys.argv[2], encoding="utf-8").read()
          rules = open(sys.argv[3], encoding="utf-8").read()
          for line in unit.splitlines():
              if line.startswith("IPAddressAllow="):
                  for entry in line.partition("=")[2].split():
                      try:
                          ipaddress.ip_network(entry, strict=False)
                      except ValueError:
                          sys.exit(
                              f"the allow entry {entry} of the leg unit is no address prefix"
                          )
          for name in (
              "User=dev",
              "Type=forking",
              "ExitType=cgroup",
              "IPAddressDeny=any",
              "leg-run.py",
              "spawn.out",
              "spawn.err",
          ):
              if name not in unit:
                  sys.exit(f"the leg unit names no {name}")
          if not any(
              line.startswith("BindReadOnlyPaths=")
              and "/run/user/" in line
              and "/agenix/" in line
              for line in unit.splitlines()
          ):
              sys.exit("the leg unit binds no read-only agenix token under /run/user")
          for name in ("IPAddressDeny=any", "User=dev"):
              if name not in agent:
                  sys.exit(f"the agent unit names no {name}")
          if "IPAddressAllow=" in agent:
              sys.exit("the agent unit names an allow entry")
          if not any(
              line.startswith("BindPaths=") and "/.claude-legs/" in line
              for line in agent.splitlines()
          ):
              sys.exit("the agent unit binds no leg state")
          for text, label in ((unit, "leg unit"), (agent, "agent unit")):
              for name in ("MemoryHigh", "MemoryMax"):
                  entries = [
                      line.partition("=")[2]
                      for line in text.splitlines()
                      if line.startswith(name + "=")
                  ]
                  if len(entries) != 1:
                      sys.exit(f"the {label} names {len(entries)} {name} bounds")
                  if not re.fullmatch(r"[0-9]+[KMGTPE]?", entries[0]):
                      sys.exit(
                          f"the {name} bound of the {label} is no finite size: {entries[0]}"
                      )
          for name in sys.argv[4].splitlines():
              name = name.strip()
              if name not in rules:
                  sys.exit(f"the polkit rules name no {name}")
          if "set-property" in rules:
              sys.exit("the polkit rules grant the set-property verb")
        ' "$1" "$2" "$3" "$4"
      }
      sed -e 's/IPAddressAllow=127/IPAddressAllow=localhost/' ${legUnit} >"$TMPDIR/symbolic.service"
      if probe "$TMPDIR/symbolic.service" ${agentUnit} ${rulesFile} "$rules_names"; then
        echo "FAIL self-test: the probe passed an allow entry that holds a symbolic token" >&2
        exit 1
      fi
      sed -e 's|-/run/user/[0-9]*/agenix/zai_token|-/nix/store|' ${legUnit} >"$TMPDIR/tokenless.service"
      if probe "$TMPDIR/tokenless.service" ${agentUnit} ${rulesFile} "$rules_names"; then
        echo "FAIL self-test: the probe passed a leg unit that binds no agenix token" >&2
        exit 1
      fi
      sed -e 's/verb != "start".*verb != "stop"/true/' ${rulesFile} >"$TMPDIR/verbless.rules"
      if probe ${legUnit} ${agentUnit} "$TMPDIR/verbless.rules" "$rules_names"; then
        echo "FAIL self-test: the probe passed a rules file without the verb gate" >&2
        exit 1
      fi
      # the pattern holds no parentheses: the sed of the gate treats a
      # parenthesis as a group opener, so the regex text of the rules
      # matches only through the plain prefix (verified on the gate, sed
      # 4.10: a pattern with parentheses matched nothing)
      sed -e 's/leg-.*@/.*@/' ${rulesFile} >"$TMPDIR/anyunit.rules"
      if probe ${legUnit} ${agentUnit} "$TMPDIR/anyunit.rules" "$rules_names"; then
        echo "FAIL self-test: the probe passed a rules file that names every unit" >&2
        exit 1
      fi
      sed -e '/^MemoryMax=/d' ${legUnit} >"$TMPDIR/unbounded.service"
      if probe "$TMPDIR/unbounded.service" ${agentUnit} ${rulesFile} "$rules_names"; then
        echo "FAIL self-test: the probe passed a leg unit without a memory bound" >&2
        exit 1
      fi
      sed -e 's/^MemoryMax=.*/MemoryMax=infinity/' ${legUnit} >"$TMPDIR/infinite.service"
      if probe "$TMPDIR/infinite.service" ${agentUnit} ${rulesFile} "$rules_names"; then
        echo "FAIL self-test: the probe passed an infinite memory bound" >&2
        exit 1
      fi
      probe ${legUnit} ${agentUnit} ${rulesFile} "$rules_names"
    '';

  # the spell gate of the tree: codespell sweeps the files of the
  # flake source with its bundled dictionary, so a typo in the docs
  # tree or in a comment fails the gate. The ignore list and the skip
  # list live in lib/codespellrc, pinned, the pattern of
  # lib/yamllint.yaml
  codespell = check "codespell" [ pkgs.codespell ] ''
    codespell --config ${./codespellrc} ${self}
  '';

  # an input age is a signal, not a failure: the nightly update renews the
  # lock, and a growing age names an update that stopped (issue 355, M8)
  input-age =
    report "input-age"
      [
        pkgs.gawk
        pkgs.jq
      ]
      ''
        jq -r '.nodes | to_entries[] | select(.value.locked.lastModified != null) | "\(.value.locked.lastModified) \(.key)"' ${self}/flake.lock \
          | sort -k1,1nr \
          | awk -v now="$(date +%s)" '{ printf "%4d days  %s  %s\n", int((now - $1) / 86400), strftime("%Y-%m-%d", $1), $2 }' \
          > "$out"
      '';

  # no secret in the clear, and no agenix file that decrypts to nothing
  # (docs/secrets.md, security law item 1; docs/runbook.md names the gap
  # that agenix verifies the recipients, not the content)
  secrets =
    check "secrets"
      [
        pkgs.age
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gitleaks
      ]
      ''
        set -eu
        gitleaks dir --redact ${self}
        # an agenix file with an empty plaintext carries only the age header,
        # the recipient stanzas, and the 16-byte payload tag, so its size
        # equals the size of a file that encrypts an empty plaintext with the
        # same count of recipients: the check calibrates those sizes itself,
        # for one and for two recipients, and flags every exact match up to
        # eight recipients
        age-keygen -o "$TMPDIR/key"
        pub="$(sed -n 's/^# public key: //p' "$TMPDIR/key")"
        : > "$TMPDIR/empty"
        age -r "$pub" -o "$TMPDIR/empty1.age" "$TMPDIR/empty"
        age -r "$pub" -r "$pub" -o "$TMPDIR/empty2.age" "$TMPDIR/empty"
        one=$(stat -c %s "$TMPDIR/empty1.age")
        stanza=$(($(stat -c %s "$TMPDIR/empty2.age") - one))
        while read -r size file; do
          body=$((size - one))
          if test $((body % stanza)) -eq 0 && test "$body" -ge 0 && test $((body / stanza)) -le 7; then
            echo "empty plaintext: $file ($size bytes)"
            exit 1
          fi
        done < <(find ${self} -name '*.age' -printf '%s %p\n')
      '';

  # the port-claim detector: two services that claim one host port with one
  # protocol cannot both bind it (issue 370). The claims come from the
  # evaluated tree, so the check is deterministic and cheap, and it gates
  # (docs/ci.md names the posture rule). Claims that the tree cannot name
  # stay outside: a container with host networking publishes its ports
  # directly (jellyfin today), the rnsd discovery ports ride multicast
  # packet rules, and the dispatcher receiver binds the podman bridge behind
  # an interface-scoped rule
  port-claims =
    let
      inherit (pkgs) lib;

      # the default ports of the syncthing daemon, as its own documentation
      # lists them: the gui binds 8384, transfers hold 22000 over tcp and
      # udp, and local discovery holds 21027 over udp. The module opens all
      # but the gui port through openDefaultPorts
      syncthingPorts = [
        "8384/tcp"
        "22000/tcp"
        "22000/udp"
        "21027/udp"
      ];

      # one claim line: host, port with protocol, claimant
      claim =
        host: port: claimant:
        "${host} ${port} ${claimant}";

      # the host port of one container ports entry, with the protocol from
      # the entry suffix
      containerClaim =
        host: name: entry:
        claim host "${lib.head (lib.splitString ":" entry)}/${
          if lib.hasSuffix "/udp" entry then "udp" else "tcp"
        }" "container ${name}";

      claims =
        let
          hostClaims =
            hostName:
            let
              cfg = self.nixosConfigurations.${hostName}.config;
            in
            lib.flatten (
              lib.mapAttrsToList (
                name: container: map (containerClaim hostName name) container.ports
              ) cfg.virtualisation.oci-containers.containers
              ++ lib.optionals cfg.services.syncthing.enable (
                map (port: claim hostName port "the native syncthing service") syncthingPorts
              )
              ++ lib.optionals (cfg.services.tailscale.enable && cfg.services.tailscale.openFirewall) [
                (claim hostName "${toString cfg.services.tailscale.port}/udp" "tailscale")
              ]
            );
        in
        lib.sortOn (x: x) (lib.flatten (map hostClaims (builtins.attrNames self.nixosConfigurations)));
    in
    check "port-claims" [ pkgs.gawk ] ''
      gawk '
        {
          claimant = $3
          for (i = 4; i <= NF; i++) claimant = claimant " " $i
          key = $1 " " $2
          if (key in first && first[key] != claimant) {
            printf "two services claim one port: %s %s: %s and %s\n", $1, $2, first[key], claimant
            bad = 1
          } else if (!(key in first)) {
            first[key] = claimant
          }
        }
        END { exit bad }
      ' ${pkgs.writeText "port-claims" (lib.concatStringsSep "\n" claims + "\n")}
    '';

  # the unit-generation gate of the hosts: the check forces the toplevel
  # derivation of each NixOS host, the value that a rebuild evaluates, so
  # the unit generation of the module system runs in the gate. The forcing
  # reads each timer value twice, at the warnings of the systemd module
  # and at the unit files. An import that points at no file, and a failed
  # assertion of a host, then fail the gate, the failures that a rebuild
  # hits. flake check forces no toplevel of a host, and the timer import
  # of the backup set rode that hole onto main (issue 527, acceptance
  # criteria 1 and 2)
  host-toplevels =
    let
      inherit (pkgs) lib;

      # the module of the defect shape: the import sits in a let, and the
      # eval reads it when it derives the timer, at the warnings of the
      # systemd module or at the unit file. The target arg carries the
      # import path, so one module serves the broken case and the clean
      # case
      fixture =
        { target, ... }:
        let
          oci = import target;
        in
        {
          systemd.timers.fixture = oci.dailyTimer "fixture";
        };

      # the broken target: a file of the tree that throws, which stands
      # for an import that points at no file. The git-tree error of a
      # missing path is not catchable in restricted eval, so no green
      # check can hold a real missing path: a broken import of a host
      # kills the check evaluation itself, and the gate reddens
      brokenTarget = ./host-toplevels-broken-target.nix;

      # one probe: the standard module list of NixOS with the install
      # dummy of common/dummy-configuration.nix and the fixture module on
      # top, forced to the drvPath of the toplevel. The assertion check
      # guards the toplevel value itself, so a probe without a root file
      # system fails on the assertions before the fixture proves anything
      probe =
        target:
        builtins.tryEval
          (nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit target; };
            modules = [
              ../common/dummy-configuration.nix
              fixture
            ];
          }).config.system.build.toplevel.drvPath;

      # the teeth: the broken target fails the forcing, and the clean
      # target, the shared timer shape that the defect meant, passes it
      broken = probe brokenTarget;
      clean = probe ./oci-containers.nix;

      # one line per host: the name beside the forced toplevel derivation.
      # The forcing itself is the check; the lines land in the output of
      # the derivation, so a build of the check names what it forced. The
      # context strips from the drv path, because a string that carries
      # the context of a derivation makes the build realize the outputs of
      # the whole host closure, and the desktop closure holds a kernel
      # with no binary cache. The evaluation has already run when the
      # string exists, so the teeth lose nothing
      hostLine =
        name:
        let
          drv = self.nixosConfigurations.${name}.config.system.build.toplevel.drvPath;
        in
        "${name} ${builtins.unsafeDiscardStringContext drv}";
      hostLines = map hostLine (builtins.attrNames self.nixosConfigurations);
    in
    check "host-toplevels" [ ] ''
      set -eu
      if test ${if broken.success then "1" else "0"} -eq 1; then
        echo "FAIL self-test: the toplevel forcing passed a broken import path" >&2
        exit 1
      fi
      if test ${if clean.success then "1" else "0"} -eq 0; then
        echo "FAIL self-test: the toplevel forcing failed on the clean import" >&2
        exit 1
      fi
      cat >"$out" <<EOF
      ${lib.concatStringsSep "\n" hostLines}
      EOF
    '';

  # the playlist generator fixture of the media-servers group: the sandbox
  # cannot write /mnt, so the fixture rewrites the one deployed playlist
  # prefix of a copy to a fixture tree and runs that copy through every
  # argument form. The argument resolution is the code under test, and the
  # rewrite leaves it untouched. The check lands with the fix of the
  # relative manifests directory, so no gate run held the defect (issue 401)
  playlist-fixture =
    check "playlist-fixture"
      [
        pkgs.gnugrep
        pkgs.gnused
        pkgs.xmlstarlet
      ]
      ''
        set -eu
        root=$PWD/fixture
        media=$root/media
        playlists=$media/playlists
        library=$root/library
        jellyfin=$root/jellyfin/data/data/playlists
        altplay=$root/altplay
        mkdir -p "$playlists" "$jellyfin/anime" "$jellyfin/movies" \
          "$altplay/anime" "$altplay/movies" "$library/anime" "$library/movies" "$root/empty"
        printf '<Item/>\n' >"$jellyfin/anime/playlist.xml"
        printf '<Item/>\n' >"$jellyfin/movies/playlist.xml"
        printf '<Item/>\n' >"$altplay/anime/playlist.xml"
        printf '<Item/>\n' >"$altplay/movies/playlist.xml"
        printf 'one\n' >"$library/anime/Show S01E01.mkv"
        printf 'two\n' >"$library/movies/Film.mkv"
        printf '# a comment line\n%s\n' "$library/anime/Show S01E01" >"$playlists/anime.txt"
        printf '%s\n' "$library/movies/Film" >"$playlists/movies.txt"
        sed "s|/mnt/jellyfin/data/data/playlists|$jellyfin|" \
          ${self}/modules/virtualisation/oci-containers/media-servers/scripts/playlist_generator.sh \
          >"$root/playlist_generator.sh"

        # the playlist directory of one name holds exactly one item, and
        # the item carries the library file of its manifest line
        one_item() {
          count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$1/playlist.xml")
          test "$count" = 1
          path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem/Path' "$1/playlist.xml")
          test "$path" = "$2"
        }

        # a relative manifests directory from the parent directory: the log
        # and the manifest glob resolve against the path as the caller gave
        # it, and no nested playlists tree appears
        cd "$media"
        bash "$root/playlist_generator.sh" playlists
        test -f "$playlists/playlist_generator.log"
        test ! -e "$playlists/playlists"
        grep -qx anime "$playlists/playlist_generator.log"
        grep -qx movies "$playlists/playlist_generator.log"
        grep -Fx "playlist directory: $jellyfin" "$playlists/playlist_generator.log"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # the absolute directory of the timer: a rerun replaces the items
        # instead of appending them
        bash "$root/playlist_generator.sh" "$playlists"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # a relative manifest file from the parent directory
        bash "$root/playlist_generator.sh" playlists/anime.txt
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"

        # no argument: the manifests of the current directory
        cd "$playlists"
        bash "$root/playlist_generator.sh"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # the playlists root override: PLAYLIST_DIRECTORY moves the write
        # target, the default root stays untouched, and the log names the
        # root the run used
        printf '<Item/>\n' >"$jellyfin/anime/playlist.xml"
        printf '<Item/>\n' >"$jellyfin/movies/playlist.xml"
        cd "$media"
        PLAYLIST_DIRECTORY="$altplay" bash "$root/playlist_generator.sh" playlists
        one_item "$altplay/anime" "$library/anime/Show S01E01.mkv"
        one_item "$altplay/movies" "$library/movies/Film.mkv"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems)' "$jellyfin/anime/playlist.xml")
        test "$count" = 0
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems)' "$jellyfin/movies/playlist.xml")
        test "$count" = 0
        grep -Fx "playlist directory: $altplay" "$playlists/playlist_generator.log"

        # a manifest with two entries: one run writes both items, and a
        # rerun replaces them instead of appending them
        mkdir -p "$jellyfin/shows" "$library/shows"
        printf '<Item/>\n' >"$jellyfin/shows/playlist.xml"
        printf 'one\n' >"$library/shows/Show A S01E01.mkv"
        printf 'two\n' >"$library/shows/Show B S01E01.mkv"
        printf '%s\n%s\n' "$library/shows/Show A S01E01" "$library/shows/Show B S01E01" >"$playlists/shows.txt"
        bash "$root/playlist_generator.sh" "$playlists"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/shows/playlist.xml")
        test "$count" = 2
        path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem[1]/Path' "$jellyfin/shows/playlist.xml")
        test "$path" = "$library/shows/Show A S01E01.mkv"
        path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem[2]/Path' "$jellyfin/shows/playlist.xml")
        test "$path" = "$library/shows/Show B S01E01.mkv"
        bash "$root/playlist_generator.sh" "$playlists"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/shows/playlist.xml")
        test "$count" = 2

        # the skip branches: a line with no match and a line with two
        # matches each name the error, say that the entry is skipped, and
        # the run continues and writes the resolved entries
        mkdir -p "$jellyfin/skips" "$library/mixed"
        printf '<Item/>\n' >"$jellyfin/skips/playlist.xml"
        printf 'one\n' >"$library/mixed/Keep.mkv"
        printf 'one\n' >"$library/mixed/Film.mkv"
        printf 'two\n' >"$library/mixed/Film.avi"
        printf '%s\n%s\n%s\n' "$library/mixed/Keep" "$library/mixed/Missing" "$library/mixed/Film" >"$playlists/skips.txt"
        bash "$root/playlist_generator.sh" "$playlists/skips.txt" >"$root/skips.out" 2>&1
        one_item "$jellyfin/skips" "$library/mixed/Keep.mkv"
        grep -Fx "  Skipping this entry; the run continues" "$root/skips.out"
        grep -Fx "  Skipping this entry; the run continues" "$playlists/playlist_generator.log"
        grep -qF "No valid file found for $library/mixed/Missing" "$root/skips.out"
        grep -qF "Multiple video files found for $library/mixed/Film" "$root/skips.out"

        # a library path with an XML special character: the single write
        # lands the path escaped, the raw character never reaches the
        # playlist file, and the file stays parseable. The assertions read
        # the file itself, because sel -v prints a text value escaped
        mkdir -p "$jellyfin/special" "$library/special"
        printf '<Item/>\n' >"$jellyfin/special/playlist.xml"
        printf 'one\n' >"$library/special/Film & Crew.mkv"
        printf '%s\n' "$library/special/Film & Crew" >"$playlists/special.txt"
        bash "$root/playlist_generator.sh" "$playlists/special.txt"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/special/playlist.xml")
        test "$count" = 1
        grep -qF 'Film &amp; Crew.mkv' "$jellyfin/special/playlist.xml"
        if grep -qF 'Film & Crew.mkv' "$jellyfin/special/playlist.xml"; then
          echo "the raw special character reached the playlist file" >&2
          exit 1
        fi

        # a relative empty directory: the run fails and names the anchored
        # directory
        cd "$root"
        if bash "$root/playlist_generator.sh" empty >"$root/empty.out" 2>&1; then
          echo "the empty directory did not fail"
          exit 1
        fi
        grep -Fq "No .txt files found in $root/empty" "$root/empty.out"
      '';

  # the clean script fixture of the media-servers group: it runs the
  # repository file itself, because the store install copies it
  # verbatim, and covers the probe surface of the ingestion pull and
  # the edges of the deduplication: a dry run names each candidate file
  # once and logs it once, the wet run deletes the stray files and keeps
  # the videos, the sidecars, the thumbs, and the posters, a season
  # without a video and a folder without a video keep their files, a
  # directory is never a candidate, and the season number pads to two
  # digits without grep and awk, also under a leading zero. A movie
  # folder with a bracket group in its video name keeps its sidecar,
  # its thumb, and its subtitle through the wet run, and the family
  # match of the bracket entry stays pinned. The fixture resolves its
  # tree through realpath first, because the script prints resolved
  # paths and /build of the sandbox is a symlink. The check landed with
  # the deduplication, so no gate run held the double listing (issue
  # 397). The bracket edge landed with the exact comparison of the keep
  # helper, so no gate run held the sidecar loss (issue 414)
  clean-fixture =
    check "clean-fixture"
      [
        pkgs.gnugrep
        pkgs.gnused
      ]
      ''
        set -eu
        mkdir "$PWD/fixture"
        root=$(realpath "$PWD/fixture")
        run=$root/run
        script=${self}/modules/virtualisation/oci-containers/media-servers/scripts/clean.sh
        shows=$root/media/shows
        movies=$root/media/movies
        specials=$root/media/specials
        one="$shows/Show One"
        two="$shows/Show Two"
        s1="$one/Season 1"

        # one removal candidate of the dry run: the output and the log
        # each name it exactly once; a failure names the file
        listed_once() {
          count=$(grep -cF "$2" "$1" || true)
          if test "$count" -ne 1; then
            echo "FAIL listed_once count=$count file=$2 in=$1" >&2
            cat "$1" >&2
            exit 1
          fi
        }

        # one keep file: no output line names it
        listed_never() {
          if grep -qF "$2" "$1"; then
            echo "FAIL listed_never file=$2 in=$1" >&2
            exit 1
          fi
        }

        # one line the output must hold
        holds_line() {
          if ! grep -qF "$2" "$1"; then
            echo "FAIL holds_line missing: $2 in=$1" >&2
            exit 1
          fi
        }

        # the fixture tree: one show with its posters, one show without,
        # three movie folders of which one holds no video and one holds a
        # video name with a bracket group, and one special
        mkdir -p "$s1/extras" "$one/Season 2" "$one/Specials" "$one/extrafanart" \
          "$two/Season 1" "$two/Season 08" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" "$run"
        for f in \
          "$one/banner.jpg" "$one/clearart.png" "$one/fanart.jpg" "$one/poster.jpg" \
          "$one/folder.jpg" "$one/tvshow.nfo" "$one/landscape.jpg" \
          "$one/season01-poster.jpg" "$one/season-specials-poster.png" \
          "$s1/Show One S01E01.mkv" "$s1/Show One S01E01.en.srt" "$s1/Show One S01E01.nfo" \
          "$s1/Show One S01E01-thumb.jpg" "$s1/season.nfo" "$s1/source456.torrent" \
          "$s1/stray.txt" "$s1/extras/inside.bin" "$one/Season 2/stray2.txt" \
          "$one/Specials/Show One S00E01.mkv" "$one/Specials/note.txt" \
          "$one/extrafanart/art.jpg" \
          "$two/tvshow.nfo" "$two/Season 1/Show Two S01E01.mkv" "$two/Season 1/junk.bin" \
          "$two/Season 08/Show Two S08E01.avi" "$two/Season 08/junk8.bin" \
          "$movies/Film One/poster.jpg" "$movies/Film One/clearart.png" \
          "$movies/Film One/disc.png" "$movies/Film One/extrafanart.jpg" \
          "$movies/Film One/folder.jpg" "$movies/Film One/movie.nfo" \
          "$movies/Film One/backdrop.jpg" "$movies/Film One/Film One.mkv" \
          "$movies/Film One/Film One.en.srt" "$movies/Film One/Film One-thumb.jpg" \
          "$movies/Film One/stray.dat" "$movies/Film Two/poster.jpg" "$movies/Film Two/junk.tmp" \
          "$movies/Film Three/Film Three [2004].mkv" "$movies/Film Three/Film Three [2004].nfo" \
          "$movies/Film Three/Film Three [2004]-thumb.jpg" \
          "$movies/Film Three/Film Three [2004].en.srt" "$movies/Film Three/Film Three 2.nfo" \
          "$movies/Film Three/junk.meta" \
          "$specials/Special Film/clearart.png" "$specials/Special Film/poster.jpg" \
          "$specials/Special Film/backdrop.jpg" "$specials/Special Film/movie.nfo" \
          "$specials/Special Film/source.torrent" "$specials/Special Film/Special Film.mp4" \
          "$specials/Special Film/Special Film.srt" "$specials/Special Film/stray.spec"; do
          printf 'x\n' >"$f"
        done

        gone_list=(
          "$one/banner.jpg" "$one/clearart.png" "$one/fanart.jpg"
          "$s1/stray.txt" "$one/Specials/note.txt"
          "$two/Season 1/junk.bin" "$two/Season 08/junk8.bin"
          "$movies/Film One/poster.jpg" "$movies/Film One/clearart.png"
          "$movies/Film One/disc.png" "$movies/Film One/extrafanart.jpg"
          "$movies/Film One/stray.dat" "$movies/Film Three/junk.meta"
          "$specials/Special Film/clearart.png" "$specials/Special Film/poster.jpg"
          "$specials/Special Film/stray.spec"
        )
        kept_list=(
          "$one/poster.jpg" "$one/folder.jpg" "$one/tvshow.nfo" "$one/landscape.jpg"
          "$one/season01-poster.jpg" "$one/season-specials-poster.png"
          "$one/Season 2/stray2.txt" "$one/extrafanart/art.jpg"
          "$s1/Show One S01E01.mkv" "$s1/Show One S01E01.en.srt" "$s1/Show One S01E01.nfo"
          "$s1/Show One S01E01-thumb.jpg" "$s1/season.nfo" "$s1/source456.torrent"
          "$s1/extras/inside.bin"
          "$one/Specials/Show One S00E01.mkv"
          "$two/Season 1/Show Two S01E01.mkv" "$two/Season 08/Show Two S08E01.avi"
          "$movies/Film One/Film One.mkv" "$movies/Film One/Film One.en.srt"
          "$movies/Film One/Film One-thumb.jpg" "$movies/Film One/movie.nfo"
          "$movies/Film One/backdrop.jpg" "$movies/Film One/folder.jpg"
          "$movies/Film Two/poster.jpg" "$movies/Film Two/junk.tmp"
          "$specials/Special Film/Special Film.mp4" "$specials/Special Film/Special Film.srt"
          "$specials/Special Film/backdrop.jpg" "$specials/Special Film/source.torrent"
          # the bracket group keeps its own video, sidecar, thumb, and
          # subtitle, and Film Three 2.nfo matches the [2004] entry as a
          # pattern, so the family reach of a bracket entry stays pinned
          "$movies/Film Three/Film Three [2004].mkv" "$movies/Film Three/Film Three [2004].nfo"
          "$movies/Film Three/Film Three [2004]-thumb.jpg" "$movies/Film Three/Film Three [2004].en.srt"
          "$movies/Film Three/Film Three 2.nfo"
        )

        # the dry run: each candidate is listed once and logged once. The
        # script takes one folder per argument, and the type comes from the
        # path: each show folder, movie folder, and special folder is its
        # own argument
        cd "$run"
        if ! bash "$script" "$one" "$two" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" >"$root/dry.out" 2>&1; then
          echo "FAIL the dry run exited nonzero" >&2
          cat "$root/dry.out" >&2
          exit 1
        fi

        # the season paths carry a doubled slash, because the season glob
        # ends on a slash; the assertions read the normalized copies
        sed "s|//\+|/|g" "$root/dry.out" >"$root/dry.norm"
        sed "s|//\+|/|g" "$run/cleanup.txt" >"$root/log.norm"
        for gone in "''${gone_list[@]}"; do
          listed_once "$root/dry.norm" "$gone"
          listed_once "$root/log.norm" "$gone"
        done
        for kept in "''${kept_list[@]}"; do
          listed_never "$root/dry.norm" "$kept"
        done

        # the season number pads in bash: a one-digit season and a
        # leading-zero season both name their two-digit poster
        holds_line "$root/dry.norm" "expected 'season01-poster.jpg/png'"
        holds_line "$root/dry.norm" "expected 'season08-poster.jpg/png'"

        # a directory is never a removal candidate
        listed_never "$root/dry.norm" "$s1/extras"
        listed_never "$root/dry.norm" "$one/extrafanart"

        # a folder without a video keeps its files
        holds_line "$root/dry.norm" "No video file found in $movies/Film Two"

        # the wet run: the gone files are gone, the kept files stay
        mkdir "$root/run2"
        cd "$root/run2"
        if ! bash "$script" --wet "$one" "$two" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" >"$root/wet.out" 2>&1; then
          echo "FAIL the wet run exited nonzero" >&2
          cat "$root/wet.out" >&2
          exit 1
        fi
        for gone in "''${gone_list[@]}"; do
          if test -e "$gone"; then
            echo "FAIL survived the wet run: $gone" >&2
            exit 1
          fi
        done
        for kept in "''${kept_list[@]}"; do
          if ! test -e "$kept"; then
            echo "FAIL lost in the wet run: $kept" >&2
            exit 1
          fi
        done
      '';

  # the backup script fixture of the two daily units: the sandbox cannot
  # write /mnt, so the fixture rewrites the deployed paths of a copy of
  # each unit script to a fixture tree. The copies come from the
  # evaluated tree, so a rewrite of a unit script cannot drift from the
  # fixture. One run of each unit goes through a stubbed age that fails
  # at once: the run must exit nonzero, leave no unencrypted tar under
  # the landing, sweep the stray tar and the stray .part of an earlier
  # failed run, and keep the old encrypted archives. The second run goes
  # through the real age with a generated key pair: it lands the archive
  # of the day under its final name, leaves no .part, and decrypts into
  # the member list. The check landed with the streaming shape of the
  # two units, so no gate run held the plaintext leak (issue 528)
  backup-scripts-fixture =
    let
      # the script text of one unit of the services host, as a file the
      # fixture rewrites: the read of the evaluated tree gives the exact
      # text that a rebuild deploys
      unitScript =
        name:
        let
          text = self.nixosConfigurations.services.config.systemd.services.${name}.script;
        in
        pkgs.writeText "unit-${name}.sh" text;
    in
    check "backup-scripts-fixture"
      [
        pkgs.age
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.gnutar
      ]
      ''
        set -eu
        root=$PWD/fixture
        today=$(date +%Y-%m-%d)
        landing=$root/landing
        members=$root/members
        data=$root/data
        mkdir "$root"

        # one key pair of the fixture: the public half replaces the
        # recipient of each unit copy, and the private half proves the
        # good runs decryptable
        age-keygen -o "$root/key"
        sed -n 's/^# public key: //p' "$root/key" >"$root/recipient"

        # the failing age: the stub writes its -o output partway and
        # exits nonzero, so a pipeline of a unit copy dies after a
        # partial stream landed, the way a failing age behaves
        stub=$root/stub
        mkdir "$stub"
        printf '#!/bin/sh\nout=\nprev=\nfor a in "$@"; do\n  if [ "$prev" = "-o" ]; then out=$a; fi\n  prev=$a\ndone\nif [ -n "$out" ]; then printf partial >"$out"; fi\nexit 1\n' >"$stub/age"
        chmod +x "$stub/age"

        # the fixture sources: one member tree per member of the backup
        # set, and one data tree for the vaultwarden volume
        mkdir -p "$members"/transcripts "$members/dispatcher-state" \
          "$members/memory" "$members/leg-state" "$members/forgejo-data" "$data" "$landing"
        for m in transcripts dispatcher-state memory leg-state forgejo-data; do
          printf '%s\n' "$m" >"$members/$m/file.txt"
        done
        printf 'sentinel\n' >"$data/db.sqlite3"

        # one run of a copy: each runner prints the output of the run
        # when the exit goes the wrong way, so a failing phase names its
        # cause in the log
        must_fail() {
          if PATH="$stub:$PATH" bash "$1" >"$2" 2>&1; then
            echo "FAIL the stubbed age did not fail the run of $1" >&2
            cat "$2" >&2
            exit 1
          fi
        }
        must_pass() {
          if ! bash "$1" >"$2" 2>&1; then
            echo "FAIL the run of $1 exited nonzero" >&2
            cat "$2" >&2
            exit 1
          fi
        }

        # the backups copy: each deployed path resolves to the fixture
        # tree. The guard fails the check when a deployed path stayed,
        # so a new path of the unit cannot miss the fixture silently
        sed -e "s|/mnt/backups|$landing|g" \
          -e "s|/home/dev/\.claude/projects|$members/transcripts|g" \
          -e "s|/home/dev/\.local/state/dispatcher|$members/dispatcher-state|g" \
          -e "s|/home/dev/projects/genixis/\.claude/memory|$members/memory|g" \
          -e "s|/home/dev/projects/genixis/\.claude-legs|$members/leg-state|g" \
          -e "s|/mnt/forgejo/data|$members/forgejo-data|g" \
          -e "s|-R [^ ]*|-R $root/recipient|" \
          ${unitScript "backups"} >"$root/backups.sh"
        if grep -n '/mnt/\|/home/dev' "$root/backups.sh"; then
          echo "FAIL the rewrite of the backups copy left a deployed path" >&2
          exit 1
        fi

        # the vaultwarden copy: the backups path rewrites before the
        # data path, because the data path is a prefix of it
        sed -e "s|/mnt/vaultwarden-backups|$landing|g" \
          -e "s|/mnt/vaultwarden|$data|g" \
          -e "s|~/\.ssh/vaultwarden_backups\.pub|$root/recipient|" \
          ${unitScript "vaultwarden-backup"} >"$root/vaultwarden.sh"
        if grep -n '/mnt/\|~/\.ssh' "$root/vaultwarden.sh"; then
          echo "FAIL the rewrite of the vaultwarden copy left a deployed path" >&2
          exit 1
        fi

        # no unencrypted tar under the landing: the find pattern matches
        # only names that end in .tar, so the encrypted archives and the
        # .part streams stay out
        no_plaintext() {
          if find "$1" -name '*.tar' | grep -q .; then
            echo "FAIL an unencrypted tar stayed under $1" >&2
            find "$1" -name '*.tar' >&2
            exit 1
          fi
        }

        # the stray names of earlier failed runs, and one old archive
        # that no sweep and no retention step may remove
        printf 'stray plaintext\n' >"$landing/backups-2020-01-01.tar"
        printf 'stray stream\n' >"$landing/backups-2019-12-31.tar.age.part"
        printf 'old archive\n' >"$landing/backups-2020-01-02.tar.age"

        # the failing run of the backups unit (issue 528, acceptance
        # criterion 1 and 2): it exits nonzero, it leaves no unencrypted
        # tar, no archive of today sits under the final name, the strays
        # are gone, and the old archive stays
        must_fail "$root/backups.sh" "$root/backups-fail.out"
        no_plaintext "$landing"
        test ! -e "$landing/backups-$today.tar.age"
        test -e "$landing/backups-$today.tar.age.part"
        test ! -e "$landing/backups-2020-01-01.tar"
        test ! -e "$landing/backups-2019-12-31.tar.age.part"
        test -e "$landing/backups-2020-01-02.tar.age"

        # the good run of the backups unit: the archive of the day lands
        # under its final name, no .part stays, and the archive decrypts
        # and lists the five members
        must_pass "$root/backups.sh" "$root/backups-good.out"
        test -f "$landing/backups-$today.tar.age"
        test ! -e "$landing/backups-$today.tar.age.part"
        no_plaintext "$landing"
        age -d -i "$root/key" -o "$root/backups.tar" "$landing/backups-$today.tar.age"
        tar -tf "$root/backups.tar" >"$root/backups.list"
        for m in transcripts dispatcher-state memory leg-state forgejo-data; do
          if ! grep -q "^$m/file.txt" "$root/backups.list"; then
            echo "FAIL the archive of the day lists no $m member" >&2
            cat "$root/backups.list" >&2
            exit 1
          fi
        done
        test -f "$landing/backups-2020-01-02.tar.age"

        # the failing run of the vaultwarden unit, against the same
        # landing: its sweep must leave the backups archives untouched
        printf 'stray plaintext\n' >"$landing/vaultwarden-2020-01-01.tar"
        printf 'stray stream\n' >"$landing/vaultwarden-2019-12-31.tar.age.part"
        printf 'old archive\n' >"$landing/vaultwarden-2020-01-02.tar.age"
        must_fail "$root/vaultwarden.sh" "$root/vaultwarden-fail.out"
        no_plaintext "$landing"
        test ! -e "$landing/vaultwarden-$today.tar.age"
        test -e "$landing/vaultwarden-$today.tar.age.part"
        test ! -e "$landing/vaultwarden-2020-01-01.tar"
        test ! -e "$landing/vaultwarden-2019-12-31.tar.age.part"
        test -e "$landing/vaultwarden-2020-01-02.tar.age"
        test -f "$landing/backups-$today.tar.age"

        # the good run of the vaultwarden unit
        must_pass "$root/vaultwarden.sh" "$root/vaultwarden-good.out"
        test -f "$landing/vaultwarden-$today.tar.age"
        test ! -e "$landing/vaultwarden-$today.tar.age.part"
        no_plaintext "$landing"
        age -d -i "$root/key" -o "$root/vaultwarden.tar" "$landing/vaultwarden-$today.tar.age"
        if ! tar -tf "$root/vaultwarden.tar" | grep -q './db.sqlite3'; then
          echo "FAIL the vaultwarden archive of the day lists no db.sqlite3" >&2
          tar -tf "$root/vaultwarden.tar" >&2
          exit 1
        fi
        test -f "$landing/vaultwarden-2020-01-02.tar.age"
        test -f "$landing/backups-2020-01-02.tar.age"
      '';

  # the fixture of the commit subject script: one fixture repository per
  # case holds the base commit on main and the case commits on a topic
  # branch, so the range main..HEAD carries exactly the case subjects.
  # The main in the range is a branch of the fixture repository, so a
  # merge of the forge cannot move it. One case
  # per rule proves the teeth of the walk: the length bar at both edges,
  # the pattern, and the period, and each failing case asserts the
  # message of its rule (issue 439, acceptance criterion 3). Three guard
  # cases prove the range check: a commit with no subject fails the
  # pattern at the head of the range and on the base side of a range with
  # several commits, and a range with no commit passes (issues 442 and
  # 445)
  commit-subjects-fixture =
    check "commit-subjects-fixture"
      [
        pkgs.git
        pkgs.gnugrep
      ]
      ''
        set -eu
        export HOME="$TMPDIR"
        export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@invalid
        export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@invalid
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
        script=${self}/.forgejo/scripts/check-commit-subjects.sh

        # one fixture repository: the base commit on main, then a topic
        # branch for the case commits, so main..HEAD holds exactly them
        fixture() {
          rm -rf "$TMPDIR/repo"
          git init -q -b main "$TMPDIR/repo"
          cd "$TMPDIR/repo"
          git commit -q --allow-empty -m "chore: base"
          git switch -q -c topic
        }

        # one failing case: the script exits nonzero and the output holds
        # the message of the rule
        fails_with() {
          if bash "$script" main..HEAD >"$TMPDIR/out" 2>&1; then
            echo "FAIL the subject passed: $1" >&2
            exit 1
          fi
          grep -qF "$2" "$TMPDIR/out"
        }

        # the length bar, pass edge: a subject of 72 characters
        fixture
        subject="fix: $(printf 'a%.0s' {1..67})"
        test "''${#subject}" -eq 72
        git commit -q --allow-empty -m "$subject"
        bash "$script" main..HEAD

        # the length bar, fail edge: a subject of 73 characters
        fixture
        subject="fix: $(printf 'a%.0s' {1..68})"
        test "''${#subject}" -eq 73
        git commit -q --allow-empty -m "$subject"
        fails_with "73 characters" "subject is longer than 72 characters: $subject"

        # the pattern: a subject outside the conventional form
        fixture
        subject="no type and no colon in this subject"
        git commit -q --allow-empty -m "$subject"
        fails_with "outside the pattern" "subject does not follow conventional commits (see AGENTS.md, section COMMITS): $subject"

        # the period: a subject that ends with one
        fixture
        subject="fix: this subject ends with a period."
        git commit -q --allow-empty -m "$subject"
        fails_with "trailing period" "subject ends with a period: $subject"

        # the empty subject at the head of the range: the walk reads the
        # one empty line and fails the pattern on it (issue 442,
        # acceptance criterion 1)
        fixture
        git commit -q --allow-empty --allow-empty-message -m ""
        fails_with "empty subject" "subject does not follow conventional commits (see AGENTS.md, section COMMITS): "

        # the empty subject on the base side of a range with several
        # commits: git log lists the head commit first and the commit
        # nearest the base last, so the empty subject of the base-side
        # commit is the trailing empty line, and command substitution
        # strips it. The read through process substitution keeps the
        # line, and the walk fails the pattern on it (issue 445,
        # acceptance criterion 1)
        fixture
        git commit -q --allow-empty --allow-empty-message -m ""
        git commit -q --allow-empty -m "fix: a valid subject at the head"
        fails_with "the base-side empty subject" "subject does not follow conventional commits (see AGENTS.md, section COMMITS): "

        # the empty range: the topic branch holds no commit, so the
        # range holds no subject, and the walk passes (issue 442,
        # acceptance criterion 2)
        fixture
        bash "$script" main..HEAD
      '';

  # the scan set of the CVE report: a pinned image carries a digest or a
  # version tag, and a version tag holds a digit; everything else floats,
  # and the pinning work itself rides item C3 of issue 350
  pinned-images =
    report "pinned-images"
      [
        pkgs.gnugrep
        pkgs.gnused
      ]
      ''
        grep -rhoE 'image = "[^"]+"' ${self}/modules/virtualisation \
          | sed -e 's/^image = "//' -e 's/"$//' \
          | grep -E '(@sha256|:[0-9])' \
          | sort -u > "$out"
      '';

  # the duplicate-sentence report of the audit: one fact lives in one home
  # (docs/design.md, Documentation Law item 9), so the report names each
  # sentence of twelve words or more that two files of the documentation
  # tree hold word for word, after case and punctuation fold away. It
  # reports and never fails, because a repetition needs a reader to judge
  # whether an exception applies (issue 366, pass A3)
  doc-duplicates =
    report "doc-duplicates"
      [
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
      ''
        cd "${self}"
        for f in docs/*.md AGENTS.md README.md; do
          case "$f" in docs/decisions.md) continue ;; esac
          tr '\n' ' ' < "$f" \
            | grep -oE '[^.]+\.' \
            | awk -v file="$f" 'NF >= 12 {
                s = tolower($0)
                gsub(/[^a-z0-9 ]/, " ", s)
                gsub(/ +/, " ", s)
                print s "\t" file
              }'
        done \
          | sort -u \
          | awk -F'\t' '
              { files[$1] = files[$1] " " $2 }
              END {
                for (s in files) {
                  n = split(files[s], a, " ")
                  if (n > 1) print s ":" files[s]
                }
              }' > "$out"
      '';

  # the shape report of the five code surfaces: the machine half of the size
  # notice that the standards record proposes (issue 676, candidate line 5).
  # For each surface the report names the largest files, the net line delta
  # against the committed state, and the one-caller candidates of the earn
  # test (docs/design.md, Necessity Test 2). The state file is the previous
  # report output, the pattern of .forgejo/perf-baseline.json: a refresh
  # builds the state output of the check and copies it over the file, and a
  # person commits the refresh. The counts are syntactic for python and
  # textual for the other surfaces, so a count can hide or mint a candidate,
  # and a reader judges each line. The report never fails its derivation
  # and reads no network (issue 713)
  code-shape =
    let
      stateFile = "${self}/.forgejo/code-shape-state.json";
    in
    pkgs.runCommand "code-shape"
      {
        outputs = [
          "out"
          "state"
        ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - ${self} ${stateFile} "$out" "$state" ${self.lastModifiedDate} <<'PY'
        import ast
        import json
        import re
        import sys
        from collections import defaultdict
        from pathlib import Path

        root = Path(sys.argv[1])
        state_path = Path(sys.argv[2])
        out_path = sys.argv[3]
        state_out_path = sys.argv[4]
        stamp = sys.argv[5]
        recorded = stamp[:4] + "-" + stamp[4:6] + "-" + stamp[6:8]

        EXT = {"go": ".go", "lua": ".lua", "nix": ".nix", "python": ".py", "shell": ".sh"}
        SURFACES = ("go", "lua", "nix", "python", "shell")
        TOP = 5
        GO_MODULE = "genixis/project/"
        SELF_MARK = "$" + "{self}"

        GO_FUNC = re.compile(r"(?m)^func ([A-Za-z_][A-Za-z0-9_]*)\(")
        GO_IMPORT_BLOCK = re.compile(r"(?m)^import \(\n(.*?)\)", re.S)
        GO_IMPORT_ONE = re.compile(r"(?m)^import \"([^\"]+)\"")
        NIX_LAMBDA = re.compile(r"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_'-]*)[ \t]*=[ \t]*([A-Za-z0-9_{}.,@ \t]+):")
        NIX_LAMBDA_NEXT = re.compile(r"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_'-]*)[ \t]*=[ \t]*\n[ \t]*[A-Za-z{][A-Za-z0-9_{}.,@ \t]*:")
        SH_FUNC = re.compile(r"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(\)[ \t]*\{")
        LUA_FUNC = re.compile(r"(?m)^[ \t]*(?:local[ \t]+)?function[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(")
        LUA_MFUNC = re.compile(r"(?m)^[ \t]*function[ \t]+M\.([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(")
        LUA_ASSIGN = re.compile(r"(?m)^[ \t]*M\.([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*function")
        LUA_REQUIRE = re.compile(r"require\(\s*[\"']([A-Za-z0-9_.]+)[\"']\s*\)")
        NIX_PATH_TOKEN = re.compile(r"\.{1,2}/[A-Za-z0-9_./-]+\.nix|[$][{]self[}][A-Za-z0-9_./-]*\.nix")

        def read_text(path):
            return path.read_text(encoding="utf-8", errors="replace")

        def strip_line_comments(body, marker):
            kept = []
            for line in body.splitlines():
                pos = line.find(marker)
                if pos >= 0:
                    line = line[:pos]
                kept.append(line)
            return "\n".join(kept)

        def go_strip(body):
            out = []
            i = 0
            n = len(body)
            mode = "code"
            while i < n:
                c = body[i]
                nxt = body[i + 1] if i + 1 < n else ""
                if mode == "code":
                    if c == "/" and nxt == "/":
                        mode = "line"
                        i += 2
                        continue
                    if c == "/" and nxt == "*":
                        mode = "block"
                        i += 2
                        continue
                    if c == "\"":
                        mode = "dq"
                        i += 1
                        continue
                    if c == "`":
                        mode = "raw"
                        i += 1
                        continue
                    out.append(c)
                    i += 1
                elif mode == "line":
                    if c == "\n":
                        mode = "code"
                        out.append(c)
                    i += 1
                elif mode == "block":
                    if c == "*" and nxt == "/":
                        mode = "code"
                        i += 2
                        continue
                    if c == "\n":
                        out.append(c)
                    i += 1
                elif mode == "dq":
                    if c == "\\":
                        i += 2
                        continue
                    if c == "\"":
                        mode = "code"
                    i += 1
                else:
                    if c == "`":
                        mode = "code"
                    i += 1
            return "".join(out)

        files = {}
        text = {}
        rel = {}
        counts = {}
        code = {}
        for surface in SURFACES:
            paths = [p for p in sorted(root.rglob("*" + EXT[surface])) if p.is_file()]
            files[surface] = paths
            for p in paths:
                rel[p] = str(p.relative_to(root))
                text[p] = read_text(p)
                counts[p] = len(text[p].splitlines())
        for p in files["go"]:
            code[p] = go_strip(text[p])
        for p in files["shell"]:
            code[p] = strip_line_comments(text[p], "#")
        for p in files["lua"]:
            code[p] = strip_line_comments(text[p], "--")
        for p in files["nix"]:
            code[p] = text[p]

        def function_defs(surface):
            defs = defaultdict(int)
            for p in files[surface]:
                body = code.get(p, text[p])
                found = []
                if surface == "go":
                    found = GO_FUNC.findall(body)
                elif surface == "nix":
                    found = [m.group(1) for m in NIX_LAMBDA.finditer(body)]
                    found += NIX_LAMBDA_NEXT.findall(body)
                elif surface == "shell":
                    found = SH_FUNC.findall(body)
                elif surface == "lua":
                    found = LUA_FUNC.findall(body) + LUA_MFUNC.findall(body) + LUA_ASSIGN.findall(body)
                for name in found:
                    defs[(name, p)] += 1
            return defs

        def textual_candidates(surface):
            defs = function_defs(surface)
            names = sorted({name for (name, p) in defs})
            occ = defaultdict(int)
            for p in files[surface]:
                body = code.get(p, text[p])
                for name in names:
                    hits = len(re.findall(r"\b" + re.escape(name) + r"\b", body))
                    if hits:
                        occ[(name, p)] = hits
            out = []
            for name in names:
                total = 0
                caller = None
                for p in files[surface]:
                    net = occ.get((name, p), 0) - defs.get((name, p), 0)
                    if net > 0:
                        total += net
                        caller = p
                if total == 1:
                    out.append((name, rel[caller]))
            return out

        def python_candidates():
            trees = {}
            for p in files["python"]:
                try:
                    trees[p] = ast.parse(text[p])
                except SyntaxError:
                    trees[p] = None
            defs = {}
            for p, tree in trees.items():
                if tree is None:
                    continue
                for node in tree.body:
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        defs.setdefault(node.name, []).append(p)
            refs = defaultdict(int)
            where = defaultdict(set)

            def walk(node, enclosing, p):
                for child in ast.iter_child_nodes(node):
                    name = None
                    if isinstance(child, ast.Name) and isinstance(child.ctx, ast.Load):
                        name = child.id
                    elif isinstance(child, ast.Attribute):
                        name = child.attr
                    if name in defs and name not in enclosing:
                        refs[name] += 1
                        where[name].add(rel[p])
                    inner = enclosing
                    if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        inner = enclosing | {child.name}
                    walk(child, inner, p)

            for p, tree in trees.items():
                if tree is not None:
                    walk(tree, set(), p)
            out = []
            for name in sorted(defs):
                if refs[name] == 1:
                    out.append((name, sorted(where[name])[0]))
            return out

        def python_module_candidates():
            stems = {p.stem for p in files["python"]}
            importers = defaultdict(set)
            for p in files["python"]:
                try:
                    tree = ast.parse(text[p])
                except SyntaxError:
                    continue
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            head = alias.name.split(".")[0]
                            if head in stems:
                                importers[head].add(rel[p])
                    elif isinstance(node, ast.ImportFrom):
                        if node.module and node.level == 0:
                            head = node.module.split(".")[0]
                            if head in stems:
                                importers[head].add(rel[p])
            out = []
            for stem in sorted(stems):
                users = importers.get(stem, set())
                if len(users) == 1:
                    out.append((stem, sorted(users)[0]))
            return out

        def go_package_candidates():
            importers = defaultdict(set)
            for p in files["go"]:
                raw = text[p]
                paths = list(GO_IMPORT_ONE.findall(raw))
                for block in GO_IMPORT_BLOCK.findall(raw):
                    for line in block.splitlines():
                        paths += re.findall(r"\"([^\"]+)\"", line)
                for imp in paths:
                    if imp.startswith(GO_MODULE):
                        importers[imp[len(GO_MODULE):]].add(rel[p])
            out = []
            for pkg in sorted(importers):
                users = importers[pkg]
                if len(users) == 1:
                    out.append((pkg, sorted(users)[0]))
            return out

        def nix_module_candidates():
            referrers = defaultdict(set)
            for p in files["nix"]:
                for tok in NIX_PATH_TOKEN.findall(code[p]):
                    if tok.startswith("."):
                        target = (p.parent / tok).resolve()
                    else:
                        target = (root / tok[len(SELF_MARK):]).resolve()
                    if target != p and target in text:
                        referrers[target].add(p)
            out = []
            for p in files["nix"]:
                users = referrers.get(p, set())
                if len(users) == 1:
                    out.append((rel[p], rel[next(iter(users))]))
            return out

        def lua_module_candidates():
            importers = defaultdict(set)
            for p in files["lua"]:
                for mod in LUA_REQUIRE.findall(text[p]):
                    if mod.startswith("genixis."):
                        importers[mod].add(rel[p])
            out = []
            for p in files["lua"]:
                mod = "genixis." + p.stem
                users = importers.get(mod, set())
                if len(users) == 1:
                    out.append((mod, next(iter(users))))
            return out

        state = {}
        if state_path.is_file():
            try:
                loaded = json.loads(read_text(state_path))
            except ValueError:
                loaded = {}
            if isinstance(loaded, dict):
                surfaces_state = loaded.get("surfaces", {})
                if isinstance(surfaces_state, dict):
                    state = surfaces_state

        def delta_text(delta):
            if delta >= 0:
                return "+" + str(delta)
            return str(delta)

        lines = []
        lines.append("code shape of the tree, against the state of " + recorded)
        lines.append("method: a one-caller candidate holds exactly one reference outside its own")
        lines.append("definition. Python counts references in its syntax tree; go, nix, shell, and")
        lines.append("lua count identifier occurrences with each definition subtracted (go over")
        lines.append("comment-free and string-free text, shell and lua without line comments, nix")
        lines.append("over raw text, and the shell surface holds no module system). The counts are")
        lines.append("approximations: a reader judges each candidate (docs/design.md, Necessity")
        lines.append("Test 2, issue 713).")
        lines.append("")
        for surface in SURFACES:
            total = sum(counts[p] for p in files[surface])
            prev = state.get(surface)
            head = "no previous state"
            if isinstance(prev, dict) and isinstance(prev.get("lines"), int):
                head = "delta " + delta_text(total - prev["lines"])
            lines.append("== " + surface + ": " + str(len(files[surface])) + " files, " + str(total) + " lines, " + head)
            largest = sorted(
                ((counts[p], rel[p]) for p in files[surface]),
                key=lambda pair: (-pair[0], pair[1]),
            )[:TOP]
            lines.append("  largest files:")
            for size, name in largest:
                lines.append("  " + str(size).rjust(6) + "  " + name)
            if surface == "python":
                functions = python_candidates()
                modules = python_module_candidates()
            elif surface == "go":
                functions = textual_candidates(surface)
                modules = go_package_candidates()
            elif surface == "nix":
                functions = textual_candidates(surface)
                modules = nix_module_candidates()
            elif surface == "lua":
                functions = textual_candidates(surface)
                modules = lua_module_candidates()
            else:
                functions = textual_candidates(surface)
                modules = []
            lines.append("  one-caller functions: " + str(len(functions)))
            for name, user in functions:
                lines.append("    " + name + "  <-  " + user)
            if surface != "shell":
                lines.append("  one-caller modules: " + str(len(modules)))
                for name, user in modules:
                    lines.append("    " + name + "  <-  " + user)
            lines.append("")
        Path(out_path).write_text("\n".join(lines), encoding="utf-8")
        fresh = {
            "recorded": recorded,
            "surfaces": {
                surface: {
                    "files": len(files[surface]),
                    "lines": sum(counts[p] for p in files[surface]),
                }
                for surface in SURFACES
            },
        }
        Path(state_out_path).write_text(json.dumps(fresh, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        PY
      '';

  # the drift report of the permission rules against the command inventory
  # (issue 715): the naming law states each allowed command in the AGENTS.md
  # of the repository and updates the command inventory in the same commit
  # (docs/agent-context.md, Run and Change the Rules), and no machine signal
  # held the two sides together, so a dead rule or a stale row surfaced only
  # at audit time: the stale tea comment rules lived until the audit of issue
  # 509 removed them, and the store Read grant lived until the probes of
  # issue 598 showed the gap. The report reads the Bash rules of the two
  # settings layers, the project layer of .claude/settings.json and the user
  # layer of modules/programs/cli/claude.nix, and the rows of the command
  # inventory of docs/agent-context.md, and it names each rule that no row
  # cites for the layer of the rule and each row that names no live rule of
  # the layer that it cites. A row names a rule when the head of the rule,
  # the text before its first wildcard, and the head of one backticked form
  # of the row, the text before its first placeholder, are equal, or one
  # holds the other as a prefix: the table writes a varying argument as a
  # placeholder, the rule writes it as a wildcard, and the prefix reach
  # covers the class rows, which name a bare tool or a verb family. The
  # layer citation reads the Allowed-by cell of the row: a cell that names
  # no rule covers a form that no settings layer allows, and the hook layer
  # stays outside, because this report covers the Bash rules of the settings
  # files. The Read and Edit rule forms stay outside, because their naming
  # lives in the prose and in the Read Rule Matrix (issue 715, scope). The
  # report never fails its derivation and reads no network, because a
  # finding needs a reader to judge which side must move, the posture of
  # decision D8 of issue 350. The two drift fixtures prove the teeth, the
  # fixture pattern of the format rows: a settings copy that holds an allow
  # rule that no row names must yield its finding, and an inventory copy
  # that holds a row that cites the project layer for a form that no rule
  # matches must yield its finding
  permission-drift = report "permission-drift" [ pkgs.python3 ] ''
    python3 - "$out" ${self}/.claude/settings.json ${self}/modules/programs/cli/claude.nix ${self}/docs/agent-context.md <<'PY'
    import json
    import re
    import sys

    out_path, settings_path, nix_path, doc_path = sys.argv[1:5]

    RULE_STRING = re.compile(r'"(Bash\([^"]*\))"')
    PLACEHOLDER = re.compile(r"<[^>]*>|…")
    FORM = re.compile(r"`([^`]+)`")

    # the list openers of the permissions value of the user layer, in their
    # literal shape: a rule string belongs to the list whose opener precedes
    # it, and the opener of another list ends the rule scan of the list
    # before it
    NIX_OPENERS = [
        ("allow = [", ("user", "allow")),
        ("deny = [", ("user", "deny")),
        ("additionalDirectories = [", None),
        ("hooks.PreToolUse = [", None),
    ]

    def read(path):
        with open(path, encoding="utf-8") as handle:
            return handle.read()

    # the Bash rules of the project layer: the settings file is json, and
    # each rule string carries the Bash(...) shape
    def rules_of_settings(text):
        doc = json.loads(text)
        rules = []
        for kind in ("allow", "deny"):
            for entry in doc.get("permissions", {}).get(kind, []):
                if entry.startswith("Bash(") and entry.endswith(")"):
                    rules.append((("project", kind), entry[5:-1]))
        return rules

    # the Bash rules of the user layer: the module is nix, and a text scan
    # reads each rule string with the list it sits in
    def rules_of_user_layer(text):
        marks = [(text.find(marker), side) for marker, side in NIX_OPENERS if text.find(marker) >= 0]
        marks.sort(key=lambda mark: mark[0])
        rules = []
        for hit in RULE_STRING.finditer(text):
            side = None
            for at, mark_side in marks:
                if at < hit.start():
                    side = mark_side
            if side is not None:
                rules.append((side, hit.group(1)[5:-1]))
        return rules

    # the rows of the command inventory: the table under the heading of the
    # inventory, one record per row line, with the backticked forms of the
    # command cell and the Allowed-by cell
    def rows_of_inventory(text):
        section = text.split("## The Command Inventory", 1)[1]
        rows = []
        in_table = False
        for line in section.splitlines():
            if line.startswith("|"):
                in_table = True
                cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
                if len(cells) < 2 or cells[0] in ("Command form", "---"):
                    continue
                rows.append((FORM.findall(cells[0]), cells[1]))
            elif in_table:
                break
        return rows

    # the sides that a row cites: a cell that names no rule covers a form
    # that no settings layer allows, and the deny citation of a cell names
    # the deny rules that close flags of an allowed tool
    def cites(cell):
        if "no rule" in cell:
            return []
        sides = []
        if "project rule" in cell:
            sides.append(("project", "allow"))
        if "user rule" in cell:
            sides.append(("user", "allow"))
        if "deny rule" in cell:
            sides.append(("user", "deny"))
        return sides

    def rule_head(pattern):
        return pattern.split("*", 1)[0].rstrip()

    def form_head(form):
        hit = PLACEHOLDER.search(form)
        return form[: hit.start()].rstrip() if hit else form

    # one head names the other when they are equal or one holds the other as
    # a prefix: the table writes a varying argument as a placeholder, the
    # rule writes it as a wildcard, and a class row names a bare tool or a
    # verb family that the rule head extends
    def names(head_a, head_b):
        return head_a == head_b or head_a.startswith(head_b) or head_b.startswith(head_a)

    def analyze(settings_text, nix_text, doc_text):
        rules = rules_of_settings(settings_text) + rules_of_user_layer(nix_text)
        rows = [(forms, cell, cites(cell)) for forms, cell in rows_of_inventory(doc_text)]
        unnamed = []
        for side, pattern in rules:
            head = rule_head(pattern)
            if not any(
                side in cited and any(names(head, form_head(form)) for form in forms)
                for forms, cell, cited in rows
            ):
                unnamed.append((side, pattern))
        dead = []
        for forms, cell, cited in rows:
            for side in cited:
                if not any(
                    rule_side == side
                    and any(names(rule_head(pattern), form_head(form)) for form in forms)
                    for rule_side, pattern in rules
                ):
                    dead.append((forms, side))
        return unnamed, dead

    def render(unnamed, dead):
        lines = [
            "drift between the permission rules and the command inventory",
            "method: a row names a rule when the row cites the layer of the rule, and the head of",
            "the rule (the text before its first wildcard) and the head of one form of the row (the",
            "text before its first placeholder) are equal, or one holds the other as a prefix. A",
            "finding needs a reader: the row, the rule, or the match can be the side that must",
            "move (issue 715, docs/agent-context.md).",
            "",
            "== rules that no row of the command inventory names",
        ]
        for layer in ("project", "user"):
            for kind in ("allow", "deny"):
                group = sorted(p for (l, k), p in unnamed if (l, k) == (layer, kind))
                lines.append(layer + " " + kind + " (" + str(len(group)) + "):")
                lines.extend("  Bash(" + pattern + ")" for pattern in group)
        lines.append("")
        lines.append("== rows that name no live Bash rule of the layer that they cite")
        if dead:
            for forms, (layer, kind) in dead:
                listed = ", ".join("`" + form + "`" for form in forms)
                lines.append("  " + listed + ": cites " + layer + " " + kind + ", and no rule of that layer matches")
        else:
            lines.append("  (none)")
        return "\n".join(lines) + "\n"

    settings_text = read(settings_path)
    nix_text = read(nix_path)
    doc_text = read(doc_path)
    unnamed, dead = analyze(settings_text, nix_text, doc_text)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(render(unnamed, dead))

    # the teeth: a settings copy that holds an allow rule that no row names
    # must yield the rule, and an inventory copy that holds a row that cites
    # the project layer for a form that no rule matches must yield the row.
    # The live findings never fail the derivation; a fixture that yields no
    # finding breaks the matcher and fails it
    settings = json.loads(settings_text)
    settings["permissions"]["allow"].append("Bash(zz-drift-fixture no-row *)")
    fixture_unnamed, _ = analyze(json.dumps(settings), nix_text, doc_text)
    if (("project", "allow"), "zz-drift-fixture no-row *") not in fixture_unnamed:
        sys.exit("FAIL self-test: the fixture rule with no row yields no finding")
    table_head = "| Command form | Allowed by | Named by |\n| --- | --- | --- |\n"
    _, fixture_dead = analyze(
        settings_text,
        nix_text,
        doc_text.replace(
            table_head,
            table_head + "| `zz-drift-fixture <arg>` | project rule | fixture |\n",
            1,
        ),
    )
    if not any(side == ("project", "allow") for _, side in fixture_dead):
        sys.exit("FAIL self-test: the fixture row with no rule yields no finding")
    PY
  '';
}
