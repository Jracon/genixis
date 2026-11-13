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
}
