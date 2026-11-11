# decisions

The decision register of the repository: each record states a decision that stands, each alternative that lost, and the event that reopens it.

Domain: why. Reader: a session that needs the reason for a past decision, or the owner who reopens one.
Code: none. Each record names the issue or the commit that made it.

## The law of the register

1. A record is appended, never rewritten. A supersession is a new record that names the record that it replaces.
2. When a review question settles the reason for a decision, the pull request that relies on the reason adds the record in the same commit (issue 199).
3. The stopgap register and the rejected list are sections of this file. The discipline of a stopgap stays in docs/design-philosophy.md.

## Records

1. The documentation split by domain. Made: 2026-11-07, issue 199. Decision: the docs tree names one domain per file: what, why, end, or how-to. The docs list of AGENTS.md groups each file under its domain, and each file appears under one group only. Alternatives that lost: the reorganization of the tree into one directory per domain, because the paths of the files stay; the split by reader alone, because a reader question can cross domains. Reopens: a file that holds two domains in one body.

2. The naming chain of the forge. Made: 2026-11-06, issue 166, transport record second revision. Decision: the repository owns no address for the forge name. The router DNS override resolves the name on the LAN, and the tailnet delegates local.jracon.xyz to the router through split DNS, so the name resolves wherever Tailscale runs. This record supersedes the stage 0 verdicts on the ssh route over MagicDNS and on the /etc/hosts pin (issue 166, stage 0 record, 2026-11-05), which kept a committed pin and a tailnet-primary transport. Alternatives that lost: the committed hosts pins on every host, because they added no reachability in any state; the hand-written pin on m2pro-mbp, for the same reason. Reopens: a state in which the router cannot hold the override, or the split DNS delegation stops.

3. The rebuild campaign of the docs tree. Made: 2026-11-07 and 2026-11-09, issue 204. Decision: the tree was rebuilt from the repository alone. The law file survived the wipe. The cold-read report ran before the wipe. No rebuild leg read the project memory or an old docs file. The why content names a forge thread or this register. The design philosophy returned under review, and the Documentation law was encoded in the body of issue 204, so the wipe could not lose it. Alternatives that lost: a full wipe that also removed the law file and AGENTS.md, because the standard and the index must exist before the rebuild starts. Reopens: the close of issue 204, where the law in the issue body and the law in the file must hold one wording.

4. A description file of the forge commands stays under the scratch directory. Made: 2026-11-09, issue 218, decision record item 1. Decision: the forms of tea issues create, tea pulls create, and the edit of an owned entity accept a description file only under the scratch directory of the worktree. Alternatives that lost: the upload path as it was, accepted with a reason, because the forge and its mirror would carry any file that a session can read. Reopens: a probe that shows a gap in the guard. The change ran as issue 237.

5. Merge before review stays a rare deviation. Made: 2026-11-09, issue 218, decision record item 2. Decision: the merge-before-review order of pull requests 103 and 106, and the missing reviewer verdict of entity 194, are accepted as rare deviations. The loop gains no rule. Alternatives that lost: a rule that orders the review before the merge; a verdict trigger in the dispatcher. Reopens: a repeat of the deviation.

6. The writing skill was verified against the licensed specification. Made: 2026-11-09, issue 239. Decision: the rules of the technical-english skill carry verdicts against ASD-STE100 Issue 9. The verdict table sits on issue 239. The license bars quotations, so the record holds verdicts only. Alternatives that lost: the acceptance of the paraphrases without verification. Reopens: a new rule of the skill that carries no trace.

7. The attribution lines stay. Made: 2026-11-09, issue 218, questionnaire item 4. Decision: the commit trailer and the supplied attribution lines stay. The no-emoji rule covers agent-written text only. Alternatives that lost: to forbid the supplied attribution lines; to drop the commit trailer. Reopens: a change of the attribution on the forge. Stage 5 of issue 166 encodes the emoji exception into the instruction text.

8. An agent session never enters a worktree. Made: the owner, early November 2026; the origin record sits on issue 218, questionnaire item 5, and the change is pull request 36. Decision: the project tool starts a session inside the worktree of a branch. No session of an agent changes the working tree by itself. Reason: the rule prevents an agent session from making its own worktrees outside the project tool. Alternatives that lost: sessions that enter a worktree by hand. Reopens: a harness that cannot start a session inside a directory.

9. Entity edits, closes, and reopens stay on the ask list. Made: pull request 37, rule 6; reviewed 2026-11-09 on issue 218, questionnaire item 6. Decision: the hook asks about every edit, close, and reopen of a forge entity, with the owned-entity exception. Alternatives that lost: to move the edits to the allow list. Reopens: stage 5 of issue 166, which reviews the rule.

10. The plan decisions of the project tool. Made: early November 2026, in the plans design thread of issue 38; the origin record sits on issue 218. Decision: only the commands that start a session take a plan. The token of a plan is an agenix secret. No token sits on a command line. Reasons: Security law item 3 of docs/design-philosophy.md, because a token reaches a process only through a file that the process reads; only the commands that start a session route an endpoint. Alternatives that lost: a token in an environment variable or a command argument; a plan flag on every command. Reopens: a second harness, or a new form of endpoint.

11. Issue 152 closed as cut. Made: the owner, 2026-11-09; the record sits on issue 218, decision record item 6. Decision: the issue closed as cut, and the dispatcher holds no verdict trigger by this decision. Alternatives that lost: a verdict trigger limit in the dispatcher. Reopens: stage 6 of issue 166, which reads the dispatcher entries with it.

12. Issue 123 closed as dropped. Made: the owner; the record sits on issue 218, decision record item 7. Decision: the issue closed as dropped, and the owner recalls no reason. The truth about branch deletion lives in docs/project.md: the forge deletes the remote branch of a merged pull request. Reopens: none named.

13. The stale allow rules decision lives in stage 5. Made: 2026-11-09, issue 218, questionnaire item 11. Decision: the removal decision on the stale tea comment allow rules lives in stage 5 of issue 166. Alternatives that lost: a removal inside this register. Reopens: stage 5 of issue 166.

14. The probe rule came from the machine. Made: 2026-11-09, issue 218, second decision record. Decision: the allow rule for the nested print-mode probe took its form from the machine, as the example under option a in the body of issue 220. The owner confirmed the choice during the leg session of 2026-11-08. No forge record holds the confirmation. The claim of the body of pull request 224, that the owner named the exact form, is corrected by this record. The body stays as merged, because records are appended, never rewritten. Alternatives that lost: none on record. Reopens: a change of the rule.

## Stopgap register

A stopgap is a mechanism whose cause is not yet gone (docs/design-philosophy.md, Stopgap discipline). Each entry names its cause, its guard, and its verdict. Seed: the stage 0 record of issue 166, 2026-11-05, with its later supersessions.

1. The ssh route of the forge over MagicDNS, in the ssh config secret. Cause: macOS Local Network privacy once blocked the LAN for a tmux server that WezTerm had started. The launchd tmux server agent removed the cause (modules/programs/cli/tmux.nix:71-100). Verdict: keep as a stated design. Record 2 supersedes the transport half of this entry.
2. The /etc/hosts pin of the forge name. Cause: a background session ran in a process chain that held no macOS Local Network grant, and the grant follows the code signature, which changes at each Nix build. Verdict: keep as a stated design, then superseded by record 2: the pins are gone, and the naming chain carries the name.
3. The GitHub mirror fallback of the rebuild and rehome functions, with the themes mirror override (modules/programs/cli/fish.nix:47-57). Cause: the VPN or the LAN can block the forge. Verdict: keep as a stated design. The mirror is the fallback for a tailnet outage and for machines that run no Tailscale.
4. rclone-webdav runs with no authentication, on port 8080 of the host services (modules/services/rclone-webdav.nix:24-32). Cause: its only consumer is the sync of retroarch saves. Verdict: conditional solve. Add authentication only if the retroarch webdav client supports credentials. Otherwise keep the service as a stated design, with the retroarch reason.
5. The rclone TODO of vaultwarden (modules/virtualisation/oci-containers/vaultwarden/vaultwarden.nix:48). Cause: no offsite backup location exists. Verdict: solve. An offsite backup location is the trigger. A daily local age-encrypted backup already runs (vaultwarden.nix:27-65).
6. The local permission rules of claude.nix. Cause: the sandbox probes of phase 5 of issue 74 have not passed. Verdict: stopgap. The rules stay temporary until the probes pass.
7. The structural placeholders: common/dummy-configuration.nix, the default hostId of the media pool (modules/virtualisation/oci-containers/media-servers/pool.nix), the path form of local-rebuild (modules/programs/cli/fish.nix:119-123), and the elevation strategy none of a root rebuild (modules/programs/cli/fish.nix:25-35). Verdict: open. Stage 7 of issue 166 takes each verdict, and some are standing patterns, not stopgaps.

## Rejected and deferred

A record of the nos, so a later session does not raise them again. Moved from docs/design-philosophy.md, which keeps a pointer. Sources: issue 74 and issue 166.

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
