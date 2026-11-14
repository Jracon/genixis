# An agent session never enters a worktree

Record 8 of the register. The index of the register sits in docs/decisions.md.

8. An agent session never enters a worktree. Made: the owner, early November 2026; the origin record sits on issue 218, questionnaire item 5, and the change is pull request 36. Decision: the project tool starts a session inside the worktree of a branch. No session of an agent changes the working tree by itself. Reason: the rule prevents an agent session from making its own worktrees outside the project tool. Alternatives that lost: sessions that enter a worktree by hand. Reopens: a harness that cannot start a session inside a directory.
