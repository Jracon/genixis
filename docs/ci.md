# ci

CI of the forge: the workflows, the runner, and the templates.

## Workflows and Runner

1. A pull request gate runs the format check, the flake check, the evaluation of the Darwin and home configurations, the documentation path check, and the two Python harnesses on every pull request (.forgejo/workflows/ci.yaml).
2. Commit subject check holds the Conventional Commits rule on every pull request (.forgejo/workflows/check-commit-subjects.yaml).
3. Nightly input update bumps the flake inputs, gates the result, builds the servers, and commits the lock (.forgejo/workflows/update-flake.yaml).
4. Issue template and pull request template carry the structure of each entity (.forgejo/).
5. One runner answers all three: instance `genixis_flake_update_runner` on the host `services`, label `native:host`.

## Pull Request Gate

1. A job runs on the native runner and checks out with the token of the forge.
2. `nix fmt -- --ci` checks the formatting.
3. `nix flake check --impure` builds the checks of the local system. Its project check runs `gofmt` and the go tests of the project tool in its check phase (lib/project-package.nix).
4. Step `Evaluate Darwin and Home Manager configurations` evaluates the Darwin derivation and the three home derivations, because the flake check skips them. The step runs the same evaluation lines as the input update, and it builds nothing.
5. A forge hook harness and a dispatcher harness run with the python3 of the runner.
6. A documentation path check sweeps the tracked text: a cited docs path must resolve, every file of docs must be listed in AGENTS.md, every record file of docs/adr/ must be named in the register index of docs/decisions.md, and every README under modules must be listed in AGENTS.md too, so the deep homes of subsumed products stay named (docs/adr/deep-homes-of-subsumed-products.md). The record files of docs/adr/ are exempt as sources of citations, because each record is append-only and names historical paths.
7. A pull request of the same repository runs the workflow from the pull request content, so a workflow change gates itself.

## Commit Subject Check

A job walks each new subject from the base to the head commit, and fails on a subject over seventy-two characters, on a subject outside the Conventional Commits pattern, and on a trailing period (check-commit-subjects.yaml). Merge commits stay out, because git writes their subject, not the author. A wrong subject in a pushed commit stays wrong, because the rules of this repository forbid a force push.

## Input Update

1. A schedule runs daily at midnight, and a manual dispatch starts it too.
2. After `nix flake update`, the gate runs again, then the Darwin derivation and the three home derivations are evaluated, because the flake check skips them.
3. Toplevels of `media` and `services` are built, so a broken update never commits. Its desktop build is skipped, because it would compile a kernel without the CachyOS binary cache.
4. With a diff, the bot commits `chore: update flake inputs` as forgejo-actions and pushes with the token through a credential helper. Each workflow reaches only the origin; none names the mirror.

The gate and the update workflow name each user and the Darwin configuration in their evaluation steps. The update workflow names each host that it builds in its build step. When you add a user or a Darwin configuration, add it to both evaluation steps. When you add a host, add it to the build step of the update workflow.

## Templates

1. Issue template asks for the problem, the goal, the scope, the test steps, the size, the alternatives, the acceptance criteria, and the relations (.forgejo/ISSUE_TEMPLATE/issue.md).
2. Pull request template asks for the owner brief: what changed, why, the alternatives rejected, where the risk sits, the machine decisions, the spine files, the test evidence, and the issues (.forgejo/PULL_REQUEST_TEMPLATE.md). Its template keeps the attribution line on a pull request that an agent wrote (docs/adr/attribution-lines.md).
3. Templates are read from the default branch, so a new template starts to work only after its pull request merges.

## Gate Rules

1. Local gate and forge gate hold the same trunk rules, and the forge answers last (two enforcement layers, docs/forge-hook.md).
2. One flake check carries the go tests, so a pull request that cannot run the tests locally still gets the authoritative run from the runner (docs/runbook.md holds the environment note).
3. Harnesses of the hook and the dispatcher run in CI on every pull request, so a leg without a python3 of its own still covers them. A leg can lack python3, and the lack is intermittent (issue 225). Probe `python3 --version` before you leave a harness run to CI.
4. A change to a gate carries its tests and its documents in the same commit.
5. Every pull request of the loop carries a brief: what changed, why, which alternatives were rejected, and where the risk sits. A reviewer challenges the brief, and the risk score ranks the attention of the owner.

## Purpose of the Gate

Purpose of the topic: every pull request passes one gate before the owner sees it, and the locked inputs of main never break a build. Gate rules above state the criteria.

## Use the Gate and the Templates

Read a red gate: the dispatcher turns it into a nudge leg on the branch (docs/services.md).

Change the gate: edit the workflow, and the pull request that carries it runs the changed workflow itself.

Write an entity: start from the template of the forge. Pull request body follows the template sections; the owner brief of the factory skill fills them.
