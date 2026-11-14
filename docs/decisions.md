# decisions

Register index of the repository: the law of the register, one index line for each record under docs/adr/, and the rejected list. Each record states a decision that stands, each alternative that lost, and the event that reopens it.

## Law of the Register

1. A record is one file under docs/adr/, named by a slug with no number. The record is appended, never rewritten. A supersession takes the place of the record that it replaces and names what it replaced, because the forge keeps the history.
2. A new record adds its file and one line of this index in the same commit.
3. When a review question settles the reason for a decision, the pull request that relies on the reason adds the record in the same commit (issue 199).
4. Workaround records live in the topic file of the concept that they serve, and docs/design.md holds the discipline. This file holds the index and the rejected list.

## Records

The records before the split of 2026-11-13 carry their historical number in this index and in their text (docs/adr/adr-directory-for-the-register.md). The numbers ended at record 25, and no new number is assigned. A citation of a record names the record file.

- 2. The naming chain of the forge — docs/adr/forge-naming-chain.md
- 3. The rebuild campaign of the docs tree — docs/adr/docs-tree-rebuild-campaign.md
- 4. A description file of the forge commands stays under the scratch directory — docs/adr/scratch-description-files.md
- 5. Merge before review stays a rare deviation — docs/adr/merge-before-review-deviation.md
- 6. The writing skill was verified against the licensed specification — docs/adr/writing-skill-verification.md
- 7. The attribution lines stay — docs/adr/attribution-lines.md
- 8. An agent session never enters a worktree — docs/adr/no-session-worktree-entry.md
- 9. Entity edits, closes, and reopens stay on the ask list — docs/adr/entity-edits-on-ask-list.md
- 10. The plan decisions of the project tool — docs/adr/project-tool-plan-tokens.md
- 11. Issue 152 closed as cut — docs/adr/issue-152-closed-as-cut.md
- 12. Issue 123 closed as dropped — docs/adr/issue-123-closed-as-dropped.md
- 13. The stale allow rules decision lives in stage 5 — docs/adr/stale-allow-rules-in-stage-5.md
- 14. The probe rule came from the machine — docs/adr/probe-rule-from-the-machine.md
- 15. Agent knowledge lives in the repository and on the forge — docs/adr/agent-knowledge-repo-and-forge.md
- 16. Design criteria live at their concepts — docs/adr/criteria-live-at-concepts.md
- 17. Agents merge no pull request — docs/adr/agents-merge-no-pull-request.md
- 18. A workaround record can carry a pending verdict — docs/adr/pending-verdict-workaround-records.md
- 19. Named documentation conventions — docs/adr/named-documentation-conventions.md
- 20. No documentation file is load-bearing for an interface — docs/adr/no-load-bearing-docs-interface.md
- 21. Deep homes of subsumed products — docs/adr/deep-homes-of-subsumed-products.md
- 22. The boundary of glue and novel work — docs/adr/glue-novel-boundary.md
- 23. The Socratic contract for novel work — docs/adr/socratic-contract.md
- 24. One record shape for workaround and register records — docs/adr/one-record-shape.md
- 25. The scope of the earlier-records clause of record 24 — docs/adr/earlier-records-clause-scope.md
- An adr directory for the register — docs/adr/adr-directory-for-the-register.md

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
4. Rejected permanently: a changelog, because the forge history and the decision register serve every consumer of one. Source: the structure window of issue 332, 2026-11-12.
5. Rejected permanently: architecture diagrams, C4 and mermaid among them, because diagram source is text but not plain prose, and plain reads stay first-class. Source: the structure window of issue 332, 2026-11-12.
