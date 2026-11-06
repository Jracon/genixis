---
name: asd-ste100
description: Use when you write or rewrite text that agents read, such as AGENTS.md, CLAUDE.md, a skill, a prompt, or acceptance criteria. Gives the rules of Simplified Technical English (ASD-STE100), adapted for instructions to agents, so that the text has one reading only.
---

# Simplified Technical English (ASD-STE100)

Text that agents read must have one reading only. These rules paraphrase ASD-STE100 Issue 9,
adapted for instructions to agents. Apply all of them. The text must also read fluently: do not
use sentence fragments or long chains of clauses.

Each rule ends with its trace: an Issue 9 rule number, or "agent-specific" with a reason. The
approved-word dictionary of Issue 9 is not part of this skill.

## Words

1. Use one word for one meaning in the full text. Do not use synonyms for variety. (1.11, 9.4)
2. Give each word one meaning only. Do not use one word for two different things. (1.3, 9.2)
3. Use the simple, common word: "use", not "utilize". Write "start", not "initiate".
   (agent-specific: no dictionary is present, so the simple word is the test)
4. Technical names are permitted: commands, options, file names, product names, and terms of
   the field. (1.5, 1.12)
5. Write a literal name in backticks, as the agent types it. (agent-specific: it marks text to copy)
6. Select a short technical name that is easy to understand. Do not use slang or jargon.
   (1.9, 1.10)
7. Do not use a technical name as a verb, and do not use a technical verb as a noun. (1.7, 1.13)
8. Do not use clusters of more than three nouns. Write "the config of the remote host". (2.1)
9. Write a long technical name in full the first time. Then use a shorter form. (2.2)
10. Do not use vague words: "appropriate", "as needed", "etc.". State the exact condition or
    give the full list. (agent-specific: a vague word makes the agent guess)
11. Do not use hedge words: "should", "might", "probably", "usually". Write "do" or "do not",
    and state each exception. (agent-specific: a hedge hides whether an action is mandatory)
12. Use American English spelling. (1.14)

## Verbs

1. Use the simple present for facts and descriptions: "The command removes the worktree." (3.2)
2. Use the imperative for instructions: "Run the tests." Do not write "must" before an
   imperative, unless the instruction stops injury or damage. (3.2, 5.3)
3. Use the simple past and the simple future only when the time is important. (agent-specific
   tightening of 3.2: fewer tenses give fewer readings)
4. You can use the past participle as an adjective: "the removed file". Do not make complex
   constructions with auxiliary verbs: no "has removed", no "is to be removed". (3.3, 3.4)
5. Use the active voice. In descriptive text, you can write the passive voice only when you do
   not know the actor. (3.6)
6. Use a verb for an action, not a noun: "shows", not "gives an indication of". (3.7)
7. Do not use the "-ing" form of a verb, except in a technical name or a fixed term. (3.5)
8. Do not use a phrasal verb when a single verb exists: "remove", not "get rid of". (9.3)

## Sentences

1. Write one instruction in each sentence. You can join two actions that happen at one time. (5.2)
2. Write a sentence for an instruction in 20 words or fewer. Write a sentence for a description
   in 25 words or fewer. (5.1, 6.3)
3. Put a condition before its instruction, with a comma between the two. (5.4)
4. Write one condition in each sentence. For more conditions, use a list. (agent-specific: a
   second condition hides which condition the instruction depends on)
5. Use the articles "the", "a", and "an". Do not drop them to save words. (4.5)
6. Do not omit words, and do not use contractions. Write "do not", not "don't". (4.2)
7. Write each negation as "not" or "never". Do not use double negatives. (agent-specific: a
   double negation hides the meaning)
8. Do not write fragments in running text. List items, table cells, and headings can be
   fragments. (4.2, 4.3)
9. Use connecting words, for example "and", "but", and "thus", to connect related sentences. (4.4)

## Structure

1. Write a procedure as a numbered list, in the order that the agent does the steps. (4.3)
2. Write each step as one action. Put the check of a result in the next sentence. (5.2)
3. Put a prohibition or a risk before its step. State the damage after the command. (7.2, 7.3)
4. Give each paragraph one topic. Put the topic in the first sentence. (6.4, 6.5)
5. Write a paragraph in six sentences or fewer. (6.6)
6. State the reason for a rule in one short sentence after the rule, when the reason is not
   clear. (agent-specific: the reason helps the agent to decide an edge case)

## Punctuation and word count

1. Use the standard punctuation marks, but not the semicolon. Write two sentences instead. (8.1)
2. Use hyphens to connect words that operate as one unit before a noun: "a read-only file". (8.2)
3. Use parentheses for a reference, an identifier, an abbreviation, or an explanation. (8.3)
4. Count words for the limits above in this way (8.4 to 8.7):
   1. In a list, the colon ends the lead sentence. Count each item as a new sentence.
   2. Count text in parentheses as one word.
   3. Count a number with its unit, an abbreviation, an identifier, a quoted name, a title,
      and a proper noun as one word each.
   4. A hyphenated word counts as one word.

## Check

Before you finish, read the text again:

1. Each term has one meaning, and each meaning has one term.
2. Each sentence has one reading. When you find a second meaning, rewrite the sentence.
3. No sentence is over the limits, and no vague or hedge word remains.
4. The text reads fluently aloud.

When a word replacement is not sufficient, change the construction of the sentence, and keep
the meaning (9.1). After a rewrite, compare the new text with the original through the
`rewrite-fidelity` skill.
