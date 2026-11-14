# Agents merge no pull request

Record 17 of the register. The index of the register sits in docs/decisions.md.

17. Agents merge no pull request. Made: 2026-11-11, issue 331. Decision: the exception clause of the global agent rules ended, so no agent merges a pull request into a branch that ends in /composition. A produced project self-authorizes through its own AGENTS.md, which takes priority over the global rules. Reason: the review of issue 331 settled that the owner merges every pull request, and no composition branch existed in this repository. Alternatives that lost: the exception clause, because it carried no use in this repository. Reopens: a produced project that asks an agent to merge into its composition branch.
