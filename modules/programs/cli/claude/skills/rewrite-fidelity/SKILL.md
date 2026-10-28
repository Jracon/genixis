---
name: rewrite-fidelity
description: Use after you rewrite text that agents read, such as AGENTS.md, CLAUDE.md, a skill, or acceptance criteria, for example into Simplified Technical English. Compares the rewrite with the original and finds each statement that the rewrite dropped, added, or changed.
---

# Rewrite fidelity

A rewrite must change the words and keep the meaning. This skill finds each difference in meaning between the
original and the rewrite. A difference is permitted only when the task asked for it.

## Procedure

1. Get the original text. For a file in git, use `git show HEAD:<path>` or `git diff <path>`. Do not compare against
   your memory of the text.
2. Split the original into atomic statements. An atomic statement is one fact, one instruction, or one prohibition.
   Number each statement.
3. Split the rewrite into atomic statements in the same way.
4. Match each statement of the original to the statement or statements of the rewrite that carry it.
5. For each pair, compare these parts:
   1. Modality: "must", "never", "do", "can", and "only" keep their strength.
   2. Negation: a "not" or a "never" is present in both, or in neither.
   3. Scope: the same files, commands, hosts, users, or cases.
   4. Conditions: each "if", "when", "unless", and "except" is present, with the same trigger.
   5. Quantifiers: "each", "all", "one", "any", and "at most" are the same.
   6. Order: steps and priorities have the same order, when the order has a meaning.
   7. Literals: commands, paths, flags, keys, and numbers are identical, character for character.
   8. Reasons: each stated reason is present. A reason helps an agent to decide an edge case.
6. List each original statement that has no match. This is a loss.
7. List each rewrite statement that has no match. This is an addition.
8. Fix each loss, addition, and change that the task did not ask for. Then do the procedure again on the changed
   parts.

## Report

Give the result as a numbered list. Each item names one difference:

1. The type: loss, addition, or change.
2. The original statement, quoted, or "none".
3. The rewrite statement, quoted, or "none".
4. The part that differs, from step 5.
5. The action: fixed, or kept because the task asked for it.

If no difference remains, write "No difference in meaning." and give the number of statements that you compared.
