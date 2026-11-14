{
  self,
  pkgs,
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
  # the gate on its own
  ruff = check "ruff" [ pkgs.ruff ] ''
    ruff check --select E4,E7,E9,F ${self}/modules/programs/cli/claude ${self}/modules/services/dispatcher
  '';

  # the lua tree reads the api of neovim through the global `vim`
  luacheck = check "luacheck" [ pkgs.luajitPackages.luacheck ] ''
    luacheck --globals vim --max-line-length 120 ${self}/modules/programs/cli/neovim/lua
  '';

  # the documentation sweep of the gate: cited paths must resolve, the
  # files must be listed in AGENTS.md, and the two writing rules hold
  # (docs/decisions.md, records 21 and 22)
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
        # docs/decisions.md is exempt as a citation source, because its
        # register is append-only and names historical paths
        for p in $(grep -rhoE 'docs/[a-z0-9-]+\.md' . \
            --include='*.nix' --include='*.go' --include='*.py' --include='*.md' \
            --exclude='decisions.md' | sort -u); do
          test -f "$p" || { echo "missing: $p"; missing=1; }
        done
        for f in docs/*.md; do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        for f in $(find modules -name README.md); do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        # a citation carries no line number, and each sub-list item is lettered
        for f in docs/*.md AGENTS.md; do
          case "$f" in docs/decisions.md) continue ;; esac
          grep -nE '\.(md|nix|go|py|lua|sh|awk|json|ya?ml|toml|age|pub):[0-9]+' "$f" && missing=1 || true
          grep -nE '^ +([-*+]|[0-9]+\.) ' "$f" && missing=1 || true
        done
        test "$missing" -eq 0
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
}
