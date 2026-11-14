# audit

The records of the nine audit passes of campaign A (issue #366, campaign A of #350): the machine input of each pass, its method, its findings, and the disposition of each finding. The pass order follows the issue. Code findings cite file and symbol.

## A1: Duplicate Code

Machine input: the gate of campaign M runs green, and it holds no duplication detector. deadnix, statix, go vet, staticcheck, ruff, and luacheck find nothing, so no machine result names a duplicate. The detector of M6 stays deferred (issue #350, C8): jscpd is absent from nixpkgs.

Method: three structured surveys of the surfaces, one for the Go module, one for the Nix tree, one for the lua tree and the shell configs, each citing file and symbol, checked by search.

Findings and dispositions:

1. Eighteen duplicate families in the Go module, from the envelope emitter of `reportSession` and `emitList` down to the worktree-of-branch loop in four copies. The consolidation is novel work: issue #367.
2. Repeated blocks across the Nix tree: the linuxserver environment block in fourteen containers, the timezone fact against `time.timeZone` of common/base.nix, the uid 1000 fact, the healthcheck quadruple, the network-create line, and smaller pairs. The fixes are glue, but they touch about thirty files: issue #368.
3. Seven families in the lua tree, from the shell-out helper of `run` and `gitOut` to the neo-tree window filter in three copies. The tree holds no tests, so the owner verifies the editor live: issue #369.
4. The popup key letter sat in two hand-synced places, the rows of lib/keymap.nix and the popups of tmux.nix. Fixed in the diff: `popupKeys` of lib/keymap.nix derives the letter from the row, and tmux.nix reads it.

Detector: none exists, and no tool can enter from a leg, because the dependency policy of the campaign gates each new tool behind an owner decision. The detector question goes to the owner with the closing record of the campaign: wait for the jscpd reopen trigger, or pick another tool. The found classes are tracked in the issues above.

## A2: Competing Code

Machine input: the flake check of the gate evaluates the media host with both instances, and nothing flags the overlap.

Evidence: the native service modules/services/syncthing.nix (`dataDir`, `openDefaultPorts`) and the container media-servers/syncthing.nix (published ports, `/mnt/syncthing` as `/config`) both load on media. The committed topology of lib/syncthing.nix is empty, so the native instance syncs nothing. Both instances claim the same ports and the same directory.

Naming: the container holds the data. The verdict stays with the owner: issue #370 carries the evidence and the removal plan. The standing detector of the class, a port-overlap check, rides the verdict, because a gate that flags the overlap would redden main before the fix.

## A3: Competing Sources of Truth

Machine input: the new doc-duplicates report of lib/checks.nix, whose first output names four repetitions.

Findings and dispositions:

1. The Stance items 6, 8, and 9 were restated in docs/services.md, item 3 in docs/agent-context.md, and item 2 in docs/containers.md. Fixed in the diff: each file states its local application and cites the Stance.
2. The token rule lived in docs/secrets.md and again in the trust items of docs/agent-context.md. Fixed: the trust item points to the rule.
3. The runner fact lived in docs/ci.md and again in the forgejo row and the quirk list of docs/containers.md. Fixed: docs/ci.md holds the fact, and the containers file points to it.
4. AGENTS.md restated the Documentation Law. Fixed: the sentence is gone.

Recorded exceptions: the naming-chain fact appears in README.md and AGENTS.md, because the README is the public face and AGENTS.md the agent face; the owner rules whether an exception holds. The law-header formula that opens each law section repeats by design, like the purpose sentences. Detector: the doc-duplicates report stands, in the reports job.

## A4: Waste

Machine input: the gate lints of campaign M, which cover dead code in each language, run green. The pass looked past them, at behaviors without consumers.

Findings and dispositions:

1. The wsl and bare outputs, the nixos-wsl input, common/wsl.nix, the stranded standalone home of the nixos user, and the dead `users.root` attribute: removed in the diff (carry-over C1).
2. Config lines at their defaults or without effect: the jellyfin port mappings under host networking, the shelfmark UDP firewall port, the stale TODO and the commented agenix lines of rclone-webdav.nix, the `maplocalleader` and `wrap` lines of options.lua, and two starship values at their documented defaults. Removed in the diff.
3. Kept with reasons: `spec.RateLimited` of internal/spec/spec.go, which the dispatcher contract of exit code 11 names; the lua lines that anchor a documented rule at its default (the textobjects `lookahead`, the neotest signs, the fastfetch localip trio of docs/cli.md); the empty `pyright` entry, which enables the server; the `fzf.setup` call, which loads the plugin; the option interfaces `genixis.tmux.popups` and `genixis.claude.plans`, which document the extension point; the package set of aarch64-darwin, which keeps the output symmetric; and the tool overlap between the devShell and the editor, which serves different machines.
4. The jj Backend interface of internal/backend: the deferred record stands (docs/project.md), which closes entry 18 of issue #218. The seam bypass in `Resolve` of internal/identity/identity.go rides issue #367.
5. The gate vocabulary of internal/coord, exported and unused: a design reversal for the owner, issue #371.
6. Found beside the pass: the daily root timer of jellyfin. Issue #375.

Detector: the dead-code classes gate through campaign M. No mechanical detector exists for a config line at its default; the pass leaves that gap on this record.

## A5: Performance

Protocol: the host is the native runner on services; each command of the baseline file runs three times; the median counts. The commands are `nix flake check --impure`, which measures the evaluation cost of the whole tree at a warm store, and `nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath`, which measures the heaviest single evaluation.

Baseline, recorded on 2026-11-13 by the audit session on the same host, with an epoch clock around each run that adds about three seconds per measurement: flake check 59.6, 59.2, and 57.7 seconds, median 59.2; darwin eval 24.7, 22.4, and 23.3 seconds, median 23.3. The numbers and the method live in .forgejo/perf-baseline.json, the one home of the data.

Standing report: the reports job measures and prints each median beside the baseline (docs/ci.md holds the step). The Go test command cannot run inside a leg, because the sandbox holds no C compiler; the check phase of the gate is the authoritative run and it is green.

## A6: Out of Date

Machine input: the input-age report, reproduced from the lock of the branch base: flake-compat 319 days, brew-src and nixos-wsl 18, themes 23, nixpkgs 14, the newest entries 11 days. The bot commit series of the lock ends on 2026-11-02 after a daily run.

Findings and dispositions:

1. The nightly update stopped landing: infrastructure fault, issue #372. The leg cannot read the run history of the forge.
2. flake-compat: transitive under nix-cachyos-kernel, and under nixos-wsl until C1 removed that parent. The upstream moves rarely, so the age is upstream stasis. Recorded reason, no action.
3. themes and the nvim plugin set: the themes input is the repository of the owner, and the nvim plugins come from nixpkgs (docs/cli.md), so both ride the lock and the nightly update. Recorded reason, no action.
4. The audit bumps no lock by hand: the nightly update owns the lock, and a manual bump would mask the fault of item 1.

Detector: the input-age report stands.

## A7: Vulnerable

Machine input: the secrets check of the gate runs green, gitleaks and the empty-plaintext calibration included. The scheduled govulncheck and trivy runs had not run at the time of the pass: the reports job first runs on the schedule after the merge of #364, and its findings follow this record.

Verdicts:

1. Rotation cadence: no rule of docs/secrets.md names one, and the git history shows single-commit secrets. The rule is Security Law: issue #373.
2. The native runner executes pull-request workflows with a token whose scope no repository text states. Issue #374.

Seated entries of issue #218: entry 30 is closed, because docs/secrets.md states the fail-closed consequence and the one-line rotation of the pinned host key. Entry 12 is closed: the pass verified with a probe file that an ignored directory of the worktree enters no store copy of the path source. Entry 13 rides issue #376.

Found beside the pass: the daily root timer of jellyfin, issue #375, and its row in docs/containers.md landed in the diff.

## A8: Backup-Set Verification

Machine input: a search of the tree for backup mechanisms, which finds the vaultwarden timer alone.

Finding: the repository claims a backup set and holds no mechanism for it. The dispatcher state of services, the transcripts, and the memory sit in no backup, and no offsite location exists. The design is a new decision: issue #377. No detector can exist before the design names the set.

## A9: Layer Audit

Each item of the global agent layer, judged under the layer rule of #350:

1. The global instructions of modules/programs/cli/claude/CLAUDE.md hold machine context and work rules that serve every project. Correct layer.
2. The writing-skill mandate sits in the global instructions, and genixis binds its own tree through its Documentation Law. Two layers, two bindings, no conflict. Correct.
3. The adr and diataxis skills carry general craft and defer to the law of each repository. Global is correct.
4. The factory, forgejo, project, and search skills serve every leg that any dispatcher instance spawns, genixis and produced projects alike (dispatcher machine decision 25). Their issue numbers cite the genixis forge, which is the one home of the loop record. Correct.
5. The technical-english and semantic-diff skills carry general craft. Correct.
6. The one repository-specific allow rule of the global layer, `tea issues create` for jracon/genixis, serves the home of the global instructions, and the hook states the same exception. Deliberate pair. Correct.
7. Knowledge homes: the documentation tree is project knowledge, the skills are craft, the qmd index is per checkout, and AGENTS.md holds pointers. No agent definition exists outside the dispatcher prompts, which are project state. Correct.
8. The not-applicable read of the readiness gate: the only issue that carries Readiness lines is #366, and its not-applicable names its answerer. No abuse exists in a sample of one.

No finding survives, so no detector is due.
