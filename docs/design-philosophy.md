# Design philosophy of genixis

The criteria that decide what belongs in this repository. They are the standing guide of the project: each change and each review applies them to each line. A change that cannot cite a criterion here does not belong in the repository.

## The stance

1. Declarative first. Nix owns every machine this repository builds. A state that Nix cannot express needs a register entry, or it goes.
2. Local-first on owned hardware. Infrastructure and data stay on machines the owner controls. Models are remote endpoints until a local one is good enough.
3. The harness is a replaceable part. Enforcement lives where an agent cannot influence it: the OS, the network, the identity, and the forge.
4. Ticket-driven and loop-based. The forge is the single tracker. Work starts from an issue that states a problem, a goal, and acceptance criteria.
5. Total portability. A machine that this flake does not build can still work in the repository. A developer-facing output needs only Nix with flakes and a checkout.
6. Resilience by avenue count. The forge is reachable through several independent paths. The tailnet is primary. The router override and the mirror are fallbacks. One path is a single point of failure.
7. Natural language is an interface, not a dependency. The owner instructs the loop over text, also away from a terminal. Everything that the interface can do, the owner can do without it. The interface never reaches a launch or resume path of a daemon. The loop is self-improving, and it runs on the self-hosted services of this repository.
8. The comprehension budget. The owner keeps the skill to do the work and to understand what the loop produces. A fixed weekly budget of attention and practice covers this. Once a month, the owner writes one task in the same worktree flow, and the loop reviews it as it reviews the work of an agent.
9. Free software. The repository is GPL-3.0, and the public mirror carries the same grant as the origin.

## The declarative law

1. One place per decision. All nixpkgs configuration and all overlays live in common/nixpkgs.nix. A Home Manager module never sets an option below nixpkgs.
2. Nothing downloads at runtime. Plugins, language servers, and formatters come from nixpkgs. No tool runs its own package manager, and no tool fetches code from the network at its start.
3. Every source is pinned. A dependency is a flake input with a lock entry. An unpinned fetch has no place here. Sources are fetched over git+https, never through a rate-limited public API.
4. Nix shadows the system package manager. The Nix profiles come first on the path. Homebrew serves only what Nix does not.
5. Machine-private settings stay out of the tree. Per-machine facts and device identities live in an uncommitted local.nix, and secrets live in agenix files. The repository commits no machine facts and no key material.
6. One owner per home. Home Manager runs as a module of the system build. A standalone home exists only for a machine that no system of this flake builds, so two managers never fight over one home.
7. Platform purity. A module that Darwin loads holds no NixOS-only option.
8. Each project pins its own tools. The devShell of a project holds the tools that edit it. Global installs serve only files outside a project.
9. The end state reaches Nix without flakes. A developer-facing output today needs Nix with flakes and a checkout. The aim extends past that state, and the mechanism stays open.

## Security law

1. No secret in the clear. Every secret is an agenix file. No plaintext secret is committed, and no key is inlined in a module.
2. Two key channels, and no key crosses them. A host key decrypts the system secrets of one host. A user key decrypts the two user secrets. A host that declares no system secret holds no host key.
3. A token reaches a process only through a file that the process reads. No token sits in a command argument, where a process list shows it. No token sits in a plan file, because the store is readable by every user of the machine.
4. Least privilege per identity. Each machine holds one scoped token and one push key. A missing scope is added alone, and a wider role is never the answer. The agent login holds no admin role.
5. The .env read denies stay at every tier. The forge and the public mirror form an exfiltration channel, so no sandbox replaces them.
6. A forwarded socket is a trust grant. The grant reaches every process of the login that holds it, so each forward serves one connection and ends with it.
7. The audit layer reads and labels only. It launches no session, and the loop keeps working when it is gone.
8. A destructive command answers to a person at a terminal only. It lists the work that it will remove, and it asks for a fresh confirmation code that it reads from the terminal.

## Service law

1. Every service earns its port. An exposed port has a firewall rule. A sidecar database opens no port outside its isolated network.
2. Persistent data is a bind mount under /mnt/<service>/. Never a named volume. Shared media lives under /mnt/media/.
3. One directory per service group. A flat file never orchestrates several services.
4. Private traffic stays private. A torrent downloader routes through the VPN gateway, or it does not run. A service with no public consumer binds to the tailnet or the loopback only.
5. A container pulls an image only when a newer one exists. No service pulls at every start.

## Terminal law

1. The terminal is the interface. No desktop app or voice surface is added while the terminal layer answers.
2. One modifier per layer. Meta operates the OS and the terminal application, Option operates tmux, Ctrl operates the tool in the pane. A key with no modifier, or with Shift only, goes to the tool in the pane.
3. No Meta key reaches a pane. Every Meta key stays in the application.
4. Each layer keeps one universal chord that works on every host and through every remote hop, so no layer can strand the user.
5. The keymap table in docs/keymap.md is the one list of the bindings. A change that adds a binding adds its row and its conflict check.
6. The shell is fish. The repository configures no second login shell.
7. Colour lives in the themes flake. Real hex appears there only. Every tool in this repository names ANSI colours and follows the active scheme.

## Workflow law

1. The project binary owns the git workflow. No second workflow tool is added while it answers.
2. A project holds main/ and one worktree per branch beside it. Nothing lives inside a repository, and no path is hardcoded.
3. The branch namespace names the worker: ai/ for a dispatcher leg, review/ for an interactive agent session, research/ for an investigation, and a plain name for the owner.
4. One topic per commit. Each commit evaluates alone.
5. No force push, and no bypassed hook. A rejection at a gate or at the forge is a stop: the failure is reported, and it is not retried with other flags.
6. A rebuild runs only when the owner asks for it.
7. An area under review justifies its present lines before it gains new ones.
8. A change to a gate carries its tests and its documents in the same commit.
9. The owner merges every pull request. An agent merges only into a branch that ends in /composition, and only under the conditions that the AGENTS.md of that project gives.

## The necessity tests

One question applies to each line: what keeps it here?

1. Use: each service runs because a person or a pipeline consumes it.
2. Earn: each mechanism earns its abstraction. An abstraction with one caller and no second planned consumer folds into its caller.
3. Consumer: each behavior of a tool has a caller, in the repository or on a machine this repository builds.
4. Match: each line of a document states what the code does. When a document and the code disagree, fix whichever is wrong.

A line that passes no test is removed. A line that passes holds its reason in the document nearest to it.

## Stopgap discipline

A stopgap is a mechanism whose cause is not yet gone. The stopgap register holds every one. Each entry names its cause, its guard, and its verdict:

1. Remove: the cause is gone, or the mechanism serves nothing.
2. Solve: a permanent fix is known and scheduled.
3. Keep as a stated design: the trade-off is accepted, with a reason and a review trigger.

A stopgap without a register entry is a defect. A stated design without a reason is a stopgap.

## Rejected and deferred

A record of the nos, so a later session does not raise them again.

1. Rejected permanently: the copy-on-write clone per agent, and the path remote. Tangled returns only when it has private repositories, branch protection, scoped agent auth, issue events, and a CLI. Buzz returns as a component when its approval gates and its outbound hooks are finished.
2. Deferred with a trigger:
   - The microVM tier, only if Seatbelt or the proxy fail.
   - Per-agent forge users, while the single scoped login with branch protection stands.
   - jj as a backend, behind the backend interface, when its churn settles.
   - beads as a runtime dependency, when the shared queue earns it.
3. Rejected tool classes:
   - Orchestrators and governance layers, because the loop is continue-build and the spine stays human-authored.
   - Trackers and spec frameworks, because the forge is the tracker.
   - Routers and account managers, because plans and identities are declarative and a proxy is a new trust surface.
   - Git workflow tools, because the project binary owns the workflow.
   - Desktop apps and voice, because the terminal is the interface.
4. A tool enters the repository only when the phase that needs it starts, and after its probe passes.

## Layering and trust

1. The security spine stays human-authored with agent assist: the forge hook, the sandbox profiles, the secrets topology, the branch protection, the destructive paths of the project binary, the dispatcher, and the tea wrapper.
2. The owner reviews and merges every pull request. The gate orders attention. It never replaces the review.
3. The owner can do every part of the workflow by hand, through the same tools. No agent-only pathway becomes load-bearing.
4. A replacement lands and passes its probe before the rule it replaces is deleted.
5. The record carries the executor: the login, the commit trailers, and the branch namespace. A brief discloses which decisions the machine made.
6. Evidence and decision stay apart. A session supplies the evidence, never the decision. The owner takes each decision of direction.
7. Everything that reaches the owner passed an agent review first. The queue of the owner holds only reviewed pull requests.
8. A headless session never waits for a person. What enforcement would ask about, it denies. The session reports on its entity and stops.
9. Enforcement stands in two layers. The local gate answers first, and the forge answers last. Both hold the same trunk rules.
10. Agent-generated state joins the backup set as it appears: transcripts, memory, dispatcher state, and the audit archive.
11. Rules, skills, and memory stay harness-neutral in their source. Each harness materializes its own format from one declarative source, so a second harness changes no policy.
12. Every pull request of the loop carries a brief: what changed, why, which alternatives were rejected, and where the risk sits. The reviewer challenges the brief, and the risk score ranks the attention of the owner.

## Documentation law

1. Text that agents read allows one reading only. Simplified Technical English is the dialect, applied with the writing skills.
2. A session loads the index first. Reference text loads when a task needs it.
3. A change and the documents it touches land in one commit.
4. Knowledge lives in the tree, not in a session: the owner finds the reason for a past decision with no agent present.
5. Plain reads stay first-class. The tree answers with no index and with no agent present: plain search and a file reader reach every record.
6. The tree and the hive memory hold different knowledge. The tree holds the knowledge of the project. The hive memory holds the learning of the owner. The two share one format and never trade roles.
7. AGENTS.md holds instructions and pointers only. Reference text moves to the tree when a section grows. Each file of the tree opens with a title, a one-line purpose, and the code that it documents.
8. The tree holds one file per topic. A topic is what a reader arrives with questions about, for example the keymap or the secrets. A topic file exists only when the questions of a reader need one home.
9. A topic file holds one section per kind of knowledge about the topic. Each cause of Aristotle (Physics II.3) is one kind of knowledge about the topic, at any grain of the topic, and use is a fifth kind downstream of the causes. Each section answers one question:
   1. What is the topic? (the formal cause)
   2. How is the topic realized? (the material cause)
   3. Why is the topic that way? (the efficient cause)
   4. What does the topic enable? (the final cause)
   5. How does a reader use and change the topic? (use)

   A section exists only where content exists.
10. One source holds each fact. When two topics need one fact, the file of one topic holds the fact, and the file of the other topic points to it.
11. A decision record states the decision, each alternative that lost, and the event that reopens it. A record is appended, never rewritten. A supersession is a new record that names the record that it replaces.
12. The end of the repository stays in this document. A topic file states the end of its own topic. It copies no criterion.
13. A procedure of one topic is a section of the topic file. A procedure that crosses topics gets its own file.
14. One test binds each kind:
    1. What: the Match test. Each sentence matches the code, and a code change drags its sentence along.
    2. Realization: the section names each source that holds the topic. A change that moves a source updates the section.
    3. Why: the record shape of item 11.
    4. End: a change can cite the statement.
    5. Use: the owner walks the steps with no code open.

## Sources

The document stands on its own. The entries below are the record of its origin, not its authority.

- #74: the standing principles and the phase record.
- #166: the repository review that gathered and tested the criteria.
- #209: the Documentation law on one file per topic and the four causes.
- AGENTS.md: the working rules of the repository.
- README.md: the install paths and the onboarding of a machine.
