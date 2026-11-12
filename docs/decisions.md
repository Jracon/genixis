# decisions

The decision register of the repository: each record states a decision that stands, each alternative that lost, and the event that reopens it.

## Law of the Register

1. A record is appended, never rewritten. A supersession takes the place of the record that it replaces and names what it replaced, because the forge keeps the history.
2. When a review question settles the reason for a decision, the pull request that relies on the reason adds the record in the same commit (issue 199).
3. Workaround records live in the topic file of the concept that they serve, and docs/design.md holds the discipline. This file holds the decision register and the rejected list.

## Records

2. The naming chain of the forge. Made: 2026-11-06, issue 166, transport record second revision. Decision: the repository owns no address for the forge name. The router DNS override resolves the name on the LAN, and the tailnet delegates local.jracon.xyz to the router through split DNS, so the name resolves wherever Tailscale runs. This record supersedes the stage 0 verdicts on the ssh route over MagicDNS and on the /etc/hosts pin (issue 166, stage 0 record, 2026-11-05), which kept a committed pin and a tailnet-primary transport. Alternatives that lost: the committed hosts pins on every host, because they added no reachability in any state; the hand-written pin on m2pro-mbp, for the same reason. Reopens: a state in which the router cannot hold the override, or the split DNS delegation stops.

3. The rebuild campaign of the docs tree. Made: 2026-11-07 and 2026-11-09, issue 204. Decision: the tree was rebuilt from the repository alone. The law file survived the wipe. The cold-read report ran before the wipe. No rebuild leg read the project memory or an old docs file. The why content names a forge thread or this register. The design philosophy returned under review, and the Documentation law was encoded in the body of issue 204, so the wipe could not lose it. Alternatives that lost: a full wipe that also removed the law file and AGENTS.md, because the standard and the index must exist before the rebuild starts. Reopens: the close of issue 204, where the law in the issue body and the law in the file must hold one wording.

4. A description file of the forge commands stays under the scratch directory. Made: 2026-11-09, issue 218, decision record item 1. Decision: the forms of tea issues create, tea pulls create, and the edit of an owned entity accept a description file only under the scratch directory of the worktree. Alternatives that lost: the upload path as it was, accepted with a reason, because the forge and its mirror would carry any file that a session can read. Reopens: a probe that shows a gap in the guard. The change ran as issue 237.

5. Merge before review stays a rare deviation. Made: 2026-11-09, issue 218, decision record item 2. Decision: the merge-before-review order of pull requests 103 and 106, and the missing reviewer verdict of entity 194, are accepted as rare deviations. The loop gains no rule. Alternatives that lost: a rule that orders the review before the merge; a verdict trigger in the dispatcher. Reopens: a repeat of the deviation.

6. The writing skill was verified against the licensed specification. Made: 2026-11-09, issue 239. Decision: the rules of the technical-english skill carry verdicts against ASD-STE100 Issue 9. The verdict table sits on issue 239. The license bars quotations, so the record holds verdicts only. Alternatives that lost: the acceptance of the paraphrases without verification. Reopens: a new rule of the skill that carries no trace.

7. The attribution lines stay. Made: 2026-11-09, issue 218, questionnaire item 4. Decision: the commit trailer and the supplied attribution lines stay. The no-emoji rule covers agent-written text only. Alternatives that lost: to forbid the supplied attribution lines; to drop the commit trailer. Reopens: a change of the attribution on the forge. Stage 5 of issue 166 encodes the emoji exception into the instruction text.

8. An agent session never enters a worktree. Made: the owner, early November 2026; the origin record sits on issue 218, questionnaire item 5, and the change is pull request 36. Decision: the project tool starts a session inside the worktree of a branch. No session of an agent changes the working tree by itself. Reason: the rule prevents an agent session from making its own worktrees outside the project tool. Alternatives that lost: sessions that enter a worktree by hand. Reopens: a harness that cannot start a session inside a directory.

9. Entity edits, closes, and reopens stay on the ask list. Made: pull request 37, rule 6; reviewed 2026-11-09 on issue 218, questionnaire item 6. Decision: the hook asks about every edit, close, and reopen of a forge entity, with the owned-entity exception. Alternatives that lost: to move the edits to the allow list. Reopens: stage 5 of issue 166, which reviews the rule.

10. The plan decisions of the project tool. Made: early November 2026, in the plans design thread of issue 38; the origin record sits on issue 218. Decision: only the commands that start a session take a plan. The token of a plan is an agenix secret. No token sits on a command line. Reasons: the token rule of docs/secrets.md, because a token reaches a process only through a file that the process reads; only the commands that start a session route an endpoint. Alternatives that lost: a token in an environment variable or a command argument; a plan flag on every command. Reopens: a second harness, or a new form of endpoint.

11. Issue 152 closed as cut. Made: the owner, 2026-11-09; the record sits on issue 218, decision record item 6. Decision: the issue closed as cut, and the dispatcher holds no verdict trigger by this decision. Alternatives that lost: a verdict trigger limit in the dispatcher. Reopens: stage 6 of issue 166, which reads the dispatcher entries with it.

12. Issue 123 closed as dropped. Made: the owner; the record sits on issue 218, decision record item 7. Decision: the issue closed as dropped, and the owner recalls no reason. The truth about branch deletion lives in docs/project.md: the forge deletes the remote branch of a merged pull request. Reopens: none named.

13. The stale allow rules decision lives in stage 5. Made: 2026-11-09, issue 218, questionnaire item 11. Decision: the removal decision on the stale tea comment allow rules lives in stage 5 of issue 166. Alternatives that lost: a removal inside this register. Reopens: stage 5 of issue 166.

14. The probe rule came from the machine. Made: 2026-11-09, issue 218, second decision record. Decision: the allow rule for the nested print-mode probe took its form from the machine, as the example under option a in the body of issue 220. The owner confirmed the choice during the leg session of 2026-11-08. No forge record holds the confirmation. The claim of the body of pull request 224, that the owner named the exact form, is corrected by this record. The body stays as merged, because records are appended, never rewritten. Alternatives that lost: none on record. Reopens: a change of the rule.

15. Agent knowledge lives in the repository and on the forge. Made: 2026-11-11, issue 320. Decision: an agent session writes no fact into the local memory of a project, the `.claude/memory` directory beside the checkouts. A standing rule goes into the `AGENTS.md` of the project or a file that it names, the reason for a past decision goes into this register, a fact of one topic goes into the docs file of that topic, and work state goes onto the forge entity that carries the work. The rule itself stands in the global instructions that the flake builds (modules/programs/cli/claude/CLAUDE.md). Reason: the local memory reaches only the sessions of one machine and one project directory, and a session on another host, a leg on the forge runner, and a fresh checkout never read it. Alternatives that lost: the local memory as the store of the machine, because no other machine and no fresh checkout reads it. Reopens: a harness whose memory syncs through the repository.

16. Design criteria live at their concepts. Made: 2026-11-11, issue 331. Decision: docs/design-philosophy.md folded into the core file docs/design.md and into the topic files of the tree. Each topic file holds the criteria of its topic, each workaround record lives with the concept that it serves, and the domain grouping of the docs tree ended. This record takes the place of record 1, the documentation split by domain, which held the grouping that ended here. Supersession in the replace shape applies from this record forward; earlier records keep their appended history. Alternatives that lost: a design folder beside the topic files, because a criterion lives with the concept it governs; the central stopgap register, because one file per topic contradicts the Documentation Law. Reopens: a criterion with no home at its concept.

## Rejected

A record of the nos, so a later session does not raise them again. Deferred items live in the topic file of their concept. Sources: issue 74 and issue 166.

1. Rejected permanently: the copy-on-write clone per agent, and the path remote. Tangled returns only when it has private repositories, branch protection, scoped agent auth, issue events, and a CLI. Buzz returns as a component when its approval gates and its outbound hooks are finished.
2. Rejected tool classes:
   - Orchestrators and governance layers, because the loop is continue-build and the spine stays human-authored.
   - Trackers and spec frameworks, because the forge is the tracker.
   - Routers and account managers, because plans and identities are declarative and a proxy is a new trust surface.
   - Git workflow tools, because the project binary owns the workflow.
   - Desktop apps and voice, because the terminal is the interface.
3. A tool enters the repository only when the phase that needs it starts, and after its probe passes.
