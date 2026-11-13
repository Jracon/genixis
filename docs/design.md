# design

Repository-wide design criteria: the Stance, the Necessity Tests, the Workaround discipline, the trust posture, the Documentation Law, and the map to the topic files that hold the topic criteria. A change that contradicts a criterion here does not belong in the repository.

A criterion of this repository binds this repository only, unless the criterion says otherwise. This document stands on its own.

## Stance

1. Declarative first. Nix owns every machine this repository builds. A state that Nix cannot express needs documentation, or it goes.
2. Local-first on owned hardware. Infrastructure and data stay on machines the owner controls. Models are remote endpoints until a local one is good enough.
3. A replaceable harness. Enforcement lives where an agent cannot influence it: the OS, the network, the identity, and the forge.
4. Ticket-driven and loop-based. One forge is the single tracker. Work starts from an issue that states a problem, a goal, and acceptance criteria.
5. Total portability. A reader needs none of the infrastructure of this repository to understand it or to work in it. No forge, no produced tool configuration, and no self-hosted service stands between a reader and the repository. Any editor can change it, and a developer-facing output needs only Nix with flakes and a checkout.
6. Resilience by avenue count. Several independent paths reach the forge. Tailnet is primary, and the router override and the mirror are fallbacks. One path is a single point of failure.
7. Equivalence with the agent interface. Everything that the agent interface can do, the owner can do without it, with the same results.
8. Natural language is an interface, not a dependency. Instruction reaches the loop over text, also away from a terminal. Natural language never reaches a launch or resume path of a daemon.
9. A self-improving loop. It improves the work of the repository, and it runs on the self-hosted services of this repository.
10. Comprehension budget. A fixed weekly budget of attention and practice keeps the owner skilled in the work and in what the loop produces. Once a month, the owner writes one task in the same worktree flow, and the loop reviews it as it reviews the work of an agent.
11. Free software. GPL-3.0 licenses this repository, and the public mirror carries the same grant as the origin.

## Necessity Tests

One question applies to each line: what keeps it here?

1. Use: each service runs because a person or a pipeline consumes it.
2. Earn: each mechanism earns its abstraction. An abstraction with one caller and no second planned consumer folds into its caller.
3. Consumer: each behavior of a tool has a caller, in the repository or on a machine this repository builds.
4. Match: each line of a document states what the code does. When a document and the code disagree, fix whichever is wrong.

A line that passes no test is removed. A line that passes holds its reason in the document nearest to it.

## Workaround Discipline

A workaround is a mechanism that fills a gap, with or without a permanent solution. Each record lives with the concept it serves, in the topic file of that concept, and it moves with its topic. Each entry names its cause, its guard, and its verdict:

1. Remove: the cause is gone, or the mechanism serves nothing.
2. Solve: a permanent fix is known and scheduled.
3. Keep as a stated design: the trade-off is accepted, with a reason and a review trigger.
4. Pending: no verdict is taken, and the record names its review trigger.

A workaround without a record is a defect. A stated design without a reason is a workaround.

## Layering and Trust

1. Review stays with the owner. Every pull request passes the owner, and the gate orders the attention of the owner. No gate replaces the review.
2. Capability equivalence. By hand, the owner does every part of the workflow, with the same capabilities. No agent-only pathway becomes load-bearing.
3. Evidence and decision stay apart. A session supplies the evidence, never the decision, and the owner takes each decision of direction.

## Documentation Law

1. Text that agents read allows one reading only. Simplified Technical English is the dialect, applied with the writing skills.
2. A change and the documents it touches land in one commit, because a document that lands apart from its change drifts from the code.
3. Knowledge lives in the tree. A session and a chat hold none of it, and the owner finds the reason for a past decision with no agent present.
4. Plain reads stay first-class. With no index and no agent present, plain search and a file reader reach every record.
5. Tree and hive memory hold different knowledge. Project knowledge lives in the tree, and the learning of the owner lives in the hive memory. Both share one format and never trade roles.
6. AGENTS.md holds instructions and pointers only. Reference text moves to the tree when a section grows. Each file of the tree opens with a title and a one-line purpose.
7. One file per topic. A topic is what a reader arrives with questions about, for example the keymap or the secrets. A topic file exists only when the questions of a reader need one home.
8. One section per kind of knowledge. A topic file holds one section per kind of knowledge about the topic, at any grain of the topic. Each section answers one question:
   a. What is the topic?
   b. How is the topic realized?
   c. Why is the topic that way?
   d. What does the topic enable?
   e. How does a reader use and change the topic?

   A section exists only where content exists.
   These five kinds are the quadrants of Diátaxis, the named convention of the tree (https://diataxis.fr): what a topic is, how it is realized, and what it enables are reference; why it is that way is explanation; how a reader uses and changes it is how-to. A tutorial is the fourth quadrant, one file with one section per walkthrough.
9. One source holds each fact. When two topics need one fact, the file of one topic holds the fact, and the file of the other topic points to it, because two copies of one fact drift apart at the next change.
10. A decision record states the decision, each alternative that lost, and the event that reopens it. A supersession takes the place of the record that it replaces and names what it replaced. A superseded record is no longer needed, because the forge keeps the history.
11. Purpose of the repository stays in this document. A topic file states the purpose of its own topic. It copies no criterion, because a restated criterion is a second copy of one fact, and one source holds each fact.
12. A procedure of one topic is a section of the topic file, so a reader of the topic finds every step in one place. A procedure that crosses topics gets its own file, because a copy in each topic file would drift apart, and one copy in a single topic file hides from the readers of the other topics.
13. One test binds each kind:
    a. What: the Match test. Each sentence matches the code, and a code change drags its sentence along.
    b. Realization: the section names each source that holds the topic. A change that moves a source updates the section.
    c. Why: the record shape of item 10.
    d. Enable: a change can cite the statement.
    e. Use: the owner walks the steps with no code open.

## Criteria Map

Each topic file holds the criteria of its topic:

- `docs/flake.md`: the Declarative Law. One place per decision, no runtime downloads, pinned sources over git+https, Nix before the system package manager, machine privacy, one manager per home, platform purity, self-scoped devShells.
- `docs/containers.md`: the Service Law. Ports earn a firewall rule, bind mounts under /mnt, one directory per service group, private traffic, image pulls only on a newer image.
- `docs/cli.md`: text as the interface, and one login shell.
- `docs/keymap.md`: one modifier per layer, one universal chord per layer, one row list of the bindings.
- `docs/terminal-aesthetic.md`: ANSI colours, with no literal hex outside the themes flake.
- `docs/project.md`: the Workflow Law, and the destructive-command threshold of the Security Law.
- `docs/secrets.md`: the Security Law of key channels, tokens, and secret files.
- `docs/forge-hook.md`: least privilege, no admin role for the agent login, the env-tier denies, headless denial, two enforcement layers, harness-neutral rules.
- `docs/ci.md`: the gate rules, and the brief law of the loop.
