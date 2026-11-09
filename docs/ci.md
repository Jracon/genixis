# CI and templates

The Forgejo workflows of `.forgejo/workflows/` and the templates of `.forgejo/`.

## CI (`.forgejo/workflows/`)

The three workflows run on the self-hosted Forgejo runner (`runs-on: native`, see forgejo.nix in docs/containers.md).

### `update-flake.yaml`

The workflow runs daily and on dispatch. The steps are:

1. `nix fmt -- --ci`.
2. `nix flake update`.
3. `nix flake check --impure`.
4. Evaluate `darwinConfigurations.m2pro-mbp` and every `homeConfigurations` user. Flake check skips both.
5. Build the `media` and `services` toplevels. `desktop` is skipped, because it would compile the CachyOS kernel.
6. Commit `flake.lock` if it changed.

When you add a host, a user, or a Darwin config, add it to these steps.

### `check-commit-subjects.yaml`

The workflow runs on every event of a pull request. It checks the subject of every commit of the pull request against the rules of the COMMITS section of AGENTS.md: the type, the optional scope, the optional `!`, a lowercase subject that does not end with a period, and at most 72 characters. Merge commits are skipped: git writes their subject, not the author. The workflow cannot check that the subject is imperative. A pull request that fails the check needs new commits with correct subjects. A wrong subject in a pushed commit stays wrong, because the rules of this repository forbid a force-push.

### `ci.yaml`

The workflow runs on every event of a pull request. It is the machine gate of a pull request. The steps are:

1. `nix fmt -- --ci`.
2. `nix flake check --impure`. On the runner this builds `checks.x86_64-linux.project`, which runs `gofmt -l` and `go test` of the project tool.
3. Run `python3 modules/programs/cli/claude/forge-hook-test.py`, the test of the forge hook.
4. Run `python3 modules/services/dispatcher/dispatcher-test.py`, the stub harness of the dispatcher.

The workflow builds no host configuration. When you add a check that every pull request must pass, add it to these steps.

## Templates (`.forgejo/`)

Forgejo reads templates from the default branch, so a new template starts to work after its pull request merges.

- `.forgejo/ISSUE_TEMPLATE/issue.md` is the one issue template. Each issue has the sections Problem, Goal, and Acceptance criteria. An issue is ready to work on when each section is complete.
- `.forgejo/PULL_REQUEST_TEMPLATE.md` is the pull request template. The pull request title follows Conventional Commits. The body holds the seven parts of the owner brief of the factory skill: What changed, Why, Alternatives rejected, Where the risk sits, Machine decisions, Spine files, and Test evidence. The Issues section holds one `Closes` line for each issue that the pull request solves. It holds `Refs` when the pull request must not close the issue. The template carries the attribution line for pull requests that an agent wrote.
