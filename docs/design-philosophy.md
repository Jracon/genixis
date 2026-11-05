# Design philosophy of genixis

The criteria that decide what belongs in this repository. The review of #166
applies them to each line. A change that cannot cite a criterion here does not
belong in the repository.

## The stance

1. Declarative first. Nix owns every machine this repository builds. A state
   that Nix cannot express needs a register entry, or it goes.
2. Local-first on owned hardware. Infrastructure and data stay on machines the
   owner controls. Models are remote endpoints until a local one is good
   enough.
3. The harness is a replaceable part. Enforcement lives where an agent cannot
   influence it: the OS, the network, the identity, and the forge.
4. Ticket-driven and loop-based. The forge is the single tracker. Work starts
   from an issue that states a problem, a goal, and acceptance criteria.
5. Total portability. A machine that this flake does not build can still work
   in the repository. A developer-facing output needs only Nix with flakes and
   a checkout.
6. Resilience by avenue count. The forge is reachable through several
   independent paths. The tailnet is primary; the router override and the
   mirror are fallbacks. One path is a single point of failure.

## The tests of the review

Each stage of #166 asks one question of each line: what keeps it here?

1. Use: each service runs because a person or a pipeline consumes it.
2. Earn: each mechanism earns its abstraction. An abstraction with one caller
   and no second planned consumer folds into its caller.
3. Consumer: each behavior of a tool has a caller, in the repository or on a
   machine this repository builds.
4. Match: each line of a document states what the code does. When a document
   and the code disagree, fix whichever is wrong.

A line that passes no test is removed. A line that passes holds its reason in
the document nearest to it.

## Stopgap discipline

A stopgap is a mechanism whose cause is not yet gone. The stopgap register on
#166 holds every one. Each entry names its cause, its guard, and its verdict:

1. Remove: the cause is gone, or the mechanism serves nothing.
2. Solve: a permanent fix is known and scheduled.
3. Keep as a stated design: the trade-off is accepted, with a reason and a
   review trigger.

A stopgap without a register entry is a defect. A stated design without a
reason is a stopgap.

## Layering and trust

1. The security spine stays human-authored with agent assist: the forge hook,
   the sandbox profiles, the secrets topology, the branch protection, the
   destructive paths of the project binary, the dispatcher, and the tea
   wrapper.
2. The owner reviews and merges every pull request. The gate orders attention;
   it never replaces the review.
3. The owner can do every part of the workflow by hand, through the same
   tools. No agent-only pathway becomes load-bearing.
4. A replacement lands and passes its probe before the rule it replaces is
   deleted.
5. The record carries the executor: the login, the commit trailers, and the
   branch namespace. A brief discloses which decisions the machine made.

## Documentation law

1. Text that agents read allows one reading only. Simplified Technical English
   is the dialect, applied with the writing skills.
2. A session loads the index first. Reference text loads when a task needs it.
3. A change and the documents it touches land in one commit.
4. Knowledge lives in the tree, not in a session: the owner finds the reason
   for a past decision with no agent present.

## Sources

- #74: the standing principles and the phase record.
- #166: the stages, the necessity tests, and the stage 0 record.
- AGENTS.md: the working rules of the repository.
