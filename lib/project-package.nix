# The Go rewrite of the project tooling (issue #74, phase 3): one binary
# with the former fish function's subcommands behind the same command name.
# Built in-tree per the decisions of #68; keep extraction cheap: the Go
# module under modules/programs/cli/project has its own go.mod and imports
# nothing of the surrounding Nix.
#
# go test runs in checkPhase (git in nativeCheckInputs, because the tests
# drive real repositories), so `nix flake check --impure` runs the tests
# without new hostPackages on the runner.
{
  buildGoModule,
  git,
}:

buildGoModule {
  pname = "project";
  version = "0.1.0";

  src = ../modules/programs/cli/project;
  vendorHash = null;
  nativeCheckInputs = [ git ];

  # gofmt must be clean: the repository has no Go toolchain outside this
  # build, so the check phase is what enforces it
  preCheck = ''
    unformatted=$(gofmt -l .)
    if test -n "$unformatted"; then
      gofmt -d $unformatted
      echo "gofmt is not clean: $unformatted" >&2
      exit 1
    fi
  '';
}
