# ci

CI of the forge: the workflows, the runner, and the templates.

## Workflows and Runner

1. A pull request gate runs on every pull request, and the step inventory below names what it runs (.forgejo/workflows/ci.yaml).
2. Commit subject check holds the Conventional Commits rule on every pull request (.forgejo/workflows/check-commit-subjects.yaml).
3. Nightly input update bumps the flake inputs, gates the result, builds the servers, and commits the lock (.forgejo/workflows/update-flake.yaml).
4. Issue template and pull request template carry the structure of each entity (.forgejo/).
5. One runner answers all three: instance `genixis_flake_update_runner` on the host `services`, label `native:host`. The label runs each job directly on the host through the sandboxed nix-daemon, and the runner needs no Podman access. A bare tool of a job goes into its hostPackages. A check tool comes from the flake of the checkout, so a red check reproduces on the exact pull request revision.
6. The pull request gate also runs a reports job, on the daily schedule and on a manual dispatch of the workflow, never on a pull request (.forgejo/workflows/ci.yaml).

## Pull Request Gate

The gate job runs on the native runner and checks out with the token of the forge. Each numbered item below names one step of the job, in the order of the workflow. A pull request of the same repository runs the workflow from the pull request content, so a workflow change gates itself.

Each check derivation lives in lib/checks.nix, so the `Check flake` step builds it too. Each check names its posture: it gates pull requests when it is deterministic and cheap, and it reports on the reports job when it is noisy or expensive (issue #350, decision D8). A report check writes its report to its output, and it never fails its derivation.

1. `Checkout repository`: the actions/checkout step.
2. `Check formatting`: `nix fmt -- --ci` checks the formatting of the .nix files.
3. `Check flake`: `nix flake check --impure` builds the checks of the local system. Its project check runs `gofmt` and the go tests of the project tool in its check phase (lib/project-package.nix).
4. `Evaluate Darwin and Home Manager configurations`: evaluates the Darwin derivation and the two home derivations, because the flake check skips them. The step runs the same evaluation lines as the input update, and it builds nothing.
5. `Check documentation rules`: sweeps the flake source. A cited docs path must resolve. Every file of docs must be listed in AGENTS.md. Every record file of docs/adr/ must be named in the register index of docs/decisions.md, and every README under modules must be listed there too. The listing keeps the deep homes of subsumed products named (docs/adr/deep-homes-of-subsumed-products.md). The step also holds the two writing rules of the gate (docs/adr/gate-writing-rules.md): a citation carries no line number, and each sub-list item is lettered. The writing rules exempt the register surfaces: the index of docs/decisions.md and the record files of docs/adr/. Register text is append-only. The record files are exempt as sources of citations, because each record names historical paths.
6. `Test the forge hook`: runs the harness of the forge hook with the python3 of the runner (modules/programs/cli/claude/forge-hook-test.py).
7. `Test the dispatcher`: runs the harness of the dispatcher with the python3 of the runner (modules/services/dispatcher/dispatcher-test.py).
8. `Lint the Nix files`: deadnix and statix gate the flake source. An unused let binding fails the run. Module argument names stay out of the check, because a module declares its interface through them.
9. `Vet the Go module`: go vet gates the project tool. Its derivation needs no network, because the module imports nothing outside the Go standard library.
10. `Staticcheck the Go module`: staticcheck gates the project tool, with the same properties as go vet.
11. `Lint the Python harnesses`: ruff gates the two Python suites, the forge hook harness and the dispatcher harness, with the rule set pinned to E4, E7, E9, and F. A new ruff release carries new opinion rules, and a rule upgrade must not redden the gate on its own.
12. `Lint the nvim lua files`: luacheck gates the lua tree of neovim, with `vim` declared as a global, because the tree reads the api of neovim through it, and with the line limit of 120 characters.
13. `Scan the tree for secrets`: gitleaks gates the flake source, and the empty-plaintext check flags an agenix file that decrypts to nothing, because agenix verifies the recipients, not the content (docs/secrets.md, Security Law item 1; docs/runbook.md). The check calibrates its reference sizes itself, by encrypting an empty plaintext inside the derivation.

## Scheduled Reports

The reports job runs on the daily schedule and on a manual dispatch of the workflow, and never on a pull request. Each report check is noisy or expensive, so it never fails the gate; it becomes a gate when it proves stable (issue #350, decision D8). A report names a finding, and a finding that a pass confirms becomes a tracker issue.

1. `Report Go vulnerabilities`: govulncheck reads the vulnerability database over the network, so it runs outside a derivation, through the govulncheck package of the flake. New vulnerabilities arrive out of band, and that noise keeps it off the gate.
2. `Report the age of the flake inputs`: names each input of the lock with its lock date and its age in days, oldest first, so an input whose update stopped stays visible. The report never fails the run, because an age is a signal, not a failure.
3. `Scan the pinned container images for CVEs`: trivy scans each image that carries a digest or a version tag, and the scan never fails the run, because the findings arrive out of band and the database comes over the network. The pinned-images check derives the scan set from the image lines of the container tree, so one definition of pinned serves the scan, and the pinning work itself rides item C3 of issue #350.
4. `Report duplicate sentences of the documentation tree`: the doc-duplicates check names each sentence of twelve words or more that two files of the tree hold word for word, because one fact lives in one home (docs/design.md, Documentation Law item 9). The report never fails the run: a repetition needs a reader to judge whether an exception applies, and docs/decisions.md stays exempt, because its index is append-only.
5. `Report the performance baseline`: the standing regression report of the audit. The protocol fixes the host, the commands, and the repetition: the runner of this repository on the host `services` runs each command of the baseline file three times and prints the median beside the recorded baseline. The baseline file `.forgejo/perf-baseline.json` is the one home of the numbers; it names its host, its date, and its method. A fresh baseline is taken by hand, on the same host, and committed. The report never fails the run: a reader judges the drift against the method error that the baseline names.

## Commit Subject Check

A job walks each new subject from the base to the head commit, and fails on a subject over seventy-two characters, on a subject outside the Conventional Commits pattern, and on a trailing period (check-commit-subjects.yaml). Merge commits stay out, because git writes their subject, not the author. A wrong subject in a pushed commit stays wrong, because the rules of this repository forbid a force push.

## Input Update

1. A schedule runs daily at midnight, and a manual dispatch starts it too.
2. After `nix flake update`, the gate runs again, then the Darwin derivation and the two home derivations are evaluated, because the flake check skips them.
3. Toplevels of `media` and `services` are built, so a broken update never commits. Its desktop build is skipped, because it would compile a kernel without the CachyOS binary cache.
4. With a diff, the bot commits `chore: update flake inputs` as forgejo-actions and pushes with the token through a credential helper. Each workflow reaches only the origin; none names the mirror.

The gate and the update workflow name each user and the Darwin configuration in their evaluation steps. The update workflow names each host that it builds in its build step. When you add a user or a Darwin configuration, add it to both evaluation steps. When you add a host, add it to the build step of the update workflow.

## Templates

1. Issue template asks for the problem, the goal, the scope, the test steps, the size, the alternatives, the acceptance criteria, and the relations (.forgejo/ISSUE_TEMPLATE/issue.md).
2. Pull request template asks for the owner brief: what changed, why, the alternatives rejected, where the risk sits, the machine decisions, the spine files, the test evidence, and the issues (.forgejo/PULL_REQUEST_TEMPLATE.md). Its template keeps the attribution line on a pull request that an agent wrote (docs/adr/attribution-lines.md).
3. Templates are read from the default branch, so a new template starts to work only after its pull request merges.

## Gate Rules

1. Local gate and forge gate hold the same trunk rules, and the forge answers last (two enforcement layers, docs/agent-context.md).
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
