# ci

The CI of the forge: the workflows, the runner, and the templates.

Domain: what. Reader: a session that changes a workflow or a template, or reads a red gate.
Code: .forgejo/workflows/, .forgejo/ISSUE_TEMPLATE/, .forgejo/PULL_REQUEST_TEMPLATE.md, modules/virtualisation/oci-containers/forgejo/forgejo.nix.

## What is the topic?

1. The pull request gate runs the format check, the flake check, and the two Python harnesses on every pull request (.forgejo/workflows/ci.yaml).
2. The commit subject check holds the Conventional Commits rule on every pull request (.forgejo/workflows/check-commit-subjects.yaml).
3. The nightly input update bumps the flake inputs, gates the result, builds the servers, and commits the lock (.forgejo/workflows/update-flake.yaml).
4. The issue template and the pull request template carry the structure of each entity (.forgejo/).
5. One runner answers all three: the instance `genixis_flake_update_runner` on the host `services`, label `native:host` (forgejo.nix:8-42).

## How is the topic realized?

The pull request gate (ci.yaml):

1. The job runs on the native runner and checks out with the token of the forge (ci.yaml:10-15).
2. `nix fmt -- --ci` checks the formatting (ci.yaml:17-18).
3. `nix flake check --impure` builds the checks of the local system. The project check runs `gofmt` and the go tests of the project tool in its check phase (ci.yaml:20-24; lib/project-package.nix:36-43).
4. The forge hook harness and the dispatcher harness run with the python3 of the runner (ci.yaml:26-30).
5. A pull request of the same repository runs the workflow from the pull request content, so a workflow change gates itself (ci.yaml:3-4).

The commit subject check (check-commit-subjects.yaml): the job walks each new subject from the base to the head commit, and fails on a subject over seventy-two characters, on a subject outside the Conventional Commits pattern, and on a trailing period (check-commit-subjects.yaml:19-41).

The input update (update-flake.yaml):

1. The schedule runs daily at midnight, and a manual dispatch starts it too (update-flake.yaml:3-6).
2. After `nix flake update`, the gate runs again, then the Darwin derivation and the three home derivations are evaluated, because the flake check skips them (update-flake.yaml:23-32).
3. The toplevels of `media` and `services` are built, so a broken update never commits. The desktop is skipped, because it would compile a kernel without the CachyOS binary cache (update-flake.yaml:34-40).
4. With a diff, the bot commits `chore: update flake inputs` as forgejo-actions and pushes with the token through a credential helper (update-flake.yaml:42-59). The workflows reach only the origin; none names the mirror.

The templates:

1. The issue template asks for the problem, the goal, the scope, the test steps, the size, the alternatives, the acceptance criteria, and the relations (.forgejo/ISSUE_TEMPLATE/issue.md).
2. The pull request template asks for the owner brief: what changed, why, the alternatives rejected, where the risk sits, the machine decisions, the spine files, the test evidence, and the issues (.forgejo/PULL_REQUEST_TEMPLATE.md). The template keeps the attribution line on a pull request that an agent wrote, by the decision record 7 of docs/decisions.md.

## Why is the topic that way?

1. The local gate and the forge gate hold the same trunk rules, and the forge answers last (Layering item 9, docs/design-philosophy.md).
2. The flake check carries the go tests, so a pull request that cannot run the tests locally still gets the authoritative run from the runner (flake.nix:376-379; docs/runbook.md holds the environment note).
3. The harnesses of the hook and the dispatcher run in CI on every pull request, so a leg without a python3 of its own still covers them (ci.yaml:26-30).

## What does the topic enable?

The end of the topic: every pull request passes one gate before the owner sees it, and the locked inputs of main never break a build. The Workflow law of docs/design-philosophy.md states the criteria.

## How does a reader use and change the topic?

Read a red gate: the dispatcher turns it into a nudge leg on the branch (docs/services.md).

Change the gate: edit the workflow, and the pull request that carries it runs the changed workflow itself.

Write an entity: start from the template of the forge. The pull request body follows the template sections; the owner brief of the factory skill fills them.
