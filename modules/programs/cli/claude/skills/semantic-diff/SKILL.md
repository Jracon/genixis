---
name: semantic-diff
description: Use after you rewrite text that agents read, such as AGENTS.md, CLAUDE.md, a skill, or acceptance criteria. Compares the rewrite with the original and finds each statement that the rewrite dropped, added, or changed. The skill applies to each rewrite, not only to a rewrite into Simplified Technical English.
---

# Semantic diff

A rewrite must change the words and keep the meaning. This skill lists each difference in
meaning between the original and the rewrite. A difference is permitted only when the task
asked for it.

## Procedure

1. Read the original from its source. Do not compare against your memory of the text. For a
   file in git, `git show HEAD:<path>` gives the original when the rewrite is not committed,
   and `git diff <path>` shows both texts. When the task gives the original as text, use that
   text.
2. Split the original into statements. One statement holds one fact, one instruction, or one
   prohibition, together with the condition that limits it. Treat each list item as one
   statement. Split a sentence that holds two facts or two instructions into two statements.
   Number the statements in the order in which they occur.
3. Split the rewrite into statements in the same way. Number them in the same way.
4. Pair the statements. Two statements pair when they give the same action or the same fact.
   One statement can pair with more than one statement on the other side, when the rewrite
   divided or joined statements. A group is one original statement with the rewrite
   statements that pair with it.
5. For each group, compare these parts between the original statement and the rewrite
   statements:
   1. Modality: "must", "never", "do", "can", and "only" keep their strength.
   2. Negation: a "not" or a "never" is present in both, or in neither.
   3. Actor and scope: the same actor, files, commands, hosts, users, or cases.
   4. Conditions: each "if", "when", "unless", and "except" is present, with the same trigger.
   5. Quantifiers: "each", "all", "one", "any", and "at most" are the same.
   6. Order: steps and priorities keep their order, when the order has a meaning.
   7. Literals: commands, paths, flags, keys, URLs, and numbers are identical, character for
      character.
   8. Reasons: each stated reason is present. A reason helps an agent to decide an edge case.
6. When a part differs, record one change for the group.
7. Record a loss for each original statement with no group partner. Record an addition for
   each rewrite statement that pairs with nothing.
8. When the task asks you to fix the text, fix each difference that the task did not ask for.
   Then do steps 2 to 7 again on the changed parts.

## Report

Give the result as one numbered list. Put the items in this order: losses in original order,
then changes in original order, then additions in rewrite order. Each item gives:

1. The type: loss, addition, or change.
2. The original statement, quoted, or "none".
3. The rewrite statements, quoted, or "none".
4. The part from step 5 that differs.
5. The action: fixed, kept because the task asked for it, or open because the task asked for
   no fix.

When no difference remains, write "No difference in meaning." Also give the number of original
statements and the number of rewrite statements that you compared.
