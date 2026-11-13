# Whole-codebase audit and authorship scheme (tracking draft)

Status: draft, branch `research/tracking-issue`, integrated on 2026-11-13.
This file is the source of the next tracking issue, the successor of #166.
The documentation overhaul closed on 2026-11-13 through pull requests #347 and
#349, so the gate that held this draft is gone: the issue can now be written
and posted. Each change to this file lands as its own commit, so the git
history of the branch shows every shape change. A decided item graduates to
the decision register when it is taken; the posted issue keeps only open
state.

## Purpose

Three campaigns under two standing principles. The audit makes each line of
the codebase justify itself against seven defect classes. The authorship
scheme replaces the comprehension budget, Stance item 10 of `docs/design.md`.
The lean loop drives human interventions toward the decisions that need a
human. The principles power the campaigns and outlive them.

## Principle 1: Mechanical Checks First

1. A check that a machine can run is run by a machine, in CI, before an agent
   or the owner reads the result. Agent attention goes only to judgment.
2. Posture default, owner undecided, changeable by comment before campaign M
   lands: deterministic cheap checks gate at once; noisy or expensive checks
   report on a schedule and become gates when they prove stable.
3. The oracle rule: for any identity or correctness claim, the comparison
   harness lands before the code it compares.

## Principle 2: Decisions Stay With the Owner

1. An ambiguity is resolved before a line of code exists. A leg that meets a
   decision its brief does not cover parks the issue with one precise
   question and never chooses.
2. Machines execute and record. They do not decide.

## Campaign Graph

```mermaid
flowchart LR
    F["Close issue 166 with the reconstructed record"] --> P["Campaigns M, L, B in parallel"]
    P --> A["Campaign A, seven audit passes"]
    A --> X["Exit: verdicts, checks, lean loop, scheme, carry-overs"]
```

## Campaign M: The Checks

Runs first. All items are agent-authored glue. The docs campaign already
landed one new gate sweep: cited docs paths must resolve, every docs file and
module readme must be listed in AGENTS.md (PR #349, ci.yaml).

| Item | Work | State |
| --- | --- | --- |
| M1 | Inventory the gate steps of ci.yaml, the path sweep included | planned |
| M2 | deadnix and statix for Nix | planned |
| M3 | go vet, staticcheck, govulncheck for Go | planned |
| M4 | ruff for the two Python suites | planned |
| M5 | luacheck for lua | planned |
| M6 | jscpd for duplication | planned |
| M7 | Extend the landed path sweep into the enforceable standing rules: the line-cite ban and the lettered sub-lists | planned |
| M8 | Lock-age report | planned |
| M9 | Secret scan | planned |

## Campaign L: The Lean Loop

Runs beside campaign M.

| Item | Work | State |
| --- | --- | --- |
| L1 | Readiness protocol, the eight ambiguity classes, extends the template of issues #248 and #250 | planned |
| L2 | Readiness gate, default mechanical, explicit not-applicable allowed | planned |
| L3 | Decision catalog in the factory skill: take-alone classes versus park classes | planned |
| L4 | Park shape: one precise question, blocked step named | planned |
| L5 | Intervention log: content over count | planned |
| L6 | Merge policy: owner merges into protected branches, delegation below is wide open | planned |
| L7 | Authorship regime declaration for produced projects | planned |

## Campaign B: The Authorship Scheme

Lands early. A rule change. The decision record lands in the append-only
register of `docs/decisions.md`, written with the adr skill; the register
holds records 19 to 21 today.

| Item | Work | State |
| --- | --- | --- |
| B1 | Amend Stance item 10 of docs/design.md; the register record names the weekly budget as the lost alternative | planned |
| B2 | The boundary: glue is patterned wiring, and Nix modules are glue; novel has no reference path: new algorithms, the spine, new design | planned |
| B3 | The Socratic contract: ask, probe, review; never draft | planned |
| B4 | The scheme governs audit output: glue fixes by agents, novel fixes by Socratic sessions | planned |

## Campaign A: The Audit

Starts after campaigns M and L land. Method: mechanical results first,
evidence packs second, owner verdicts third, one issue per surviving finding.
The docs campaign closed its own findings, so this audit reads the final
fourteen-file tree.

| Pass | Seed |
| --- | --- |
| A1 duplicate code | none |
| A2 competing code | the syncthing pair: native module beside the container of media-servers |
| A3 competing sources of truth | the restatement-plus-citation pattern: Stance items restated, the runner fact and the token rule in two files each (parked finding 4 of the docs campaign) |
| A4 waste | none |
| A5 performance | fresh measurement |
| A6 out of date | flake-compat of 2025-12-29, themes of 2026-10-21, the nvim plugin set |
| A7 vulnerable | none |

Surfaces: Nix 5,816 lines plus the new row list of `lib/keymap.nix`, Go 11,505
lines with no external dependencies, nvim lua 1,462 lines, fish, tmux, wezterm,
`forge-hook.py` 799 lines, `dispatcher.py` 1,449 lines plus tests, the docs
tree of fourteen files, CI, about 40 containers, the secrets spine.

## Carry-Overs

| Item | Work | Home |
| --- | --- | --- |
| C1 | Remove the wsl and bare outputs, flake.nix, and the nixos-wsl input | campaign A |
| C2 | The syncthing verdict of the source pair | campaign A |
| C3 | Pin about 30 images, version or digest; caddy third-party build decision; Service Law amendment | campaign A |
| C4 | The stage 4 to 7 dispositions folded into the closing record of #166 | opening sequence |
| C5 | The seven parked findings of the docs campaign, listed below; the closing state of #332 leaves them for owner rulings on the new shape | campaign A, docs surface |
| C6 | Issue #345: evaluate the darwin configuration and the standalone homes in the gate | campaign M, with G8 |

Parked findings of the docs campaign, from the structure window of
2026-11-13:

| ID | Finding |
| --- | --- |
| P1 | Deferred records carry no cause, guard, or verdict; standing rule 7 of #332 demands all three, and the Workaround Discipline defines no verdict for deferred. Rule and taxonomy disagree. |
| P2 | The ssh-route workaround record of services.md names a removed cause with verdict keep as a stated design, and states no reason and no trigger. |
| P3 | The why sections of project.md, cli.md, and terminal-aesthetic.md state decisions without lost options and without reopen events. |
| P4 | The restatement-plus-citation pattern against the one-source law: Stance items restated with citations, the runner fact in two topic files, the token rule in two files, the criteria map restating law keywords. |
| P5 | The register minimum shape against the adr skill: context and consequences are due fields, and the records carry a Reason line inconsistently. |
| P6 | Note, no action: register record 3 names the close of issue 204 as its reopen event; the issue is closed. |
| P7 | Warts: the name forge-hook covers a third of its file, hive memory appears once with no definition, and sentences beyond the STE limits remain in several files. |

## Decision Log

All decisions of 2026-11-11, taken by the owner in interactive sessions. The
decisions of the docs campaign live in the register (records 19 to 21), not
here: one source holds each fact.

| ID | Decision | Source |
| --- | --- | --- |
| D1 | Boundary: Nix module authorship is glue | question round 1 |
| D2 | Socratic contract: ask and review only | question round 1 |
| D3 | Practice arm subsumed by the scheme, no monthly cadence | question round 2 |
| D4 | Pin every image | question round 2 |
| D5 | Campaign A sequences after #332; the condition fired on 2026-11-13, campaign A now waits on campaigns M and L | question round 2 |
| D6 | Performance pass: no known pain points, measures fresh | question round 2 |
| D7 | Update and close #166 | question round 1 |
| D8 | Check posture undecided, split default recorded | question round 1 |
| D9 | The scheme binds genixis only | lean-loop round |
| D10 | Readiness enforcement undecided, mechanical default recorded | lean-loop round |
| D11 | Intervention recording: content over count | lean-loop round |
| D12 | Owner merges into main and protected branches; below that, wide open | lean-loop round |

## Pending

Undecided defaults: the check posture of principle 1 item 2, and the readiness
enforcement of L2.

The gap review of 2026-11-11 found 18 items. The fold decision is open: each
row enters a campaign table, or is rejected with a reason, when the owner
rules. Three rows moved through the docs campaign:

| ID | Area | State |
| --- | --- | --- |
| G1 | Audit-to-check conversion rule: each pass ends with a standing detector | open |
| G2 | Unmanaged forge state: drift surface and runbook diff | open |
| G3 | New agent state joins the backup set: intervention log, readiness records, corpora | open |
| G4 | Brief hierarchy: product charter above issues; feasibility probe class | open |
| G5 | Lean dogfood acceptance: campaigns M, L, B as the validation run | open |
| G6 | Enforcement files are spine for review, glue for authorship | open; partly in force: the docs PRs carry a spine-files section, and the gate sweeps grew by PR #349 |
| G7 | Container CVE scan beside pinning; digest pins for exposed services | open |
| G8 | Host eval matrix in CI, the Darwin eval included | carried by open issue #345 |
| G9 | Docs lint of the standing rules; URL check beside the citation check | trigger fired: the deferred gate-enforced style sweeps name a second documentation campaign, and this issue carries one. The rule set shrank on 2026-11-13 when the sentence-start and heading rules were dropped; the enforceable remainder is M7 |
| G10 | Token cost telemetry per leg per phase | open |
| G11 | Crash-resume hardening; park stops versus crash stops in the log | open |
| G12 | Loop observability surface: queue, stuck legs, log | open |
| G13 | nvim plugin freshness in the out-of-date pass | open; seeded into A6 |
| G14 | Performance measurement protocol: fixed host, repeated runs, standing regression report | open |
| G15 | Verdicts on rotation cadence and the native runner boundary | open |
| G16 | Lever: early start of code passes if #332 stalls | moot: #332 closed on 2026-11-13 |
| G17 | Readiness amendment flow for disproven answers | open |
| G18 | Not-applicable audit of the gate; empty-plaintext agenix check | open |

Owner actions that the docs campaign left open, recorded here so the posted
issue carries them:

1. The home switch: the diataxis and adr skills and the changed search skill
   reach sessions only after the owner switches the home.
2. The first tutorial walk: a rebuild fills the walk date of
   docs/tutorial.md.

## Method and Records

The #332 campaign cancelled its per-file issue method mid-run: one branch,
one rule set, one pull request per series, rulings in window comments, worked.
This issue adopts that method per campaign. Evidence cites files and symbols,
never line numbers in doc text. The owner decides; sessions record. Each
campaign posts its closing record as a comment on the posted issue. The
diataxis and adr skills bind the new texts; technical-english and
semantic-diff verify each rewrite.

## Appendix: The Readiness Question Set

The canonical demonstration of the readiness protocol. The owner test brief:
a Minecraft clone in Rust with byte-identical outputs against Java.

A. Reference and product: which exact release and builds are the reference.
What the first milestone delivers. Which subsystems are in scope, in what
sequence, and what is explicitly out.

B. Oracle: which outputs the correctness claim binds to. Which runtime build
is the oracle, with which flags. On which platform the claim must hold. What
corpus defines success, who generates it, and whether the bar is 100 percent.

C. Basis: clean-room or readable decompilation, an owner decision. The asset
policy for copyrighted material.

D. Materials: which jars, seeds, and saves the owner supplies, hash-pinned so
the oracle never moves. Which hardware the runners have.

E. Build rules: the dependency policy. The determinism strategy. The
performance floor per milestone.

F. Loop contract: the authorship regime. The merge delegation below protected
branches. The budgets and stop rules. The decision catalog. The reporting
cadence.
