---
name: asd-ste100
description: Use when you write or rewrite text that agents read, such as AGENTS.md, CLAUDE.md, a skill, a prompt, or acceptance criteria. Gives the rules of Simplified Technical English (ASD-STE100), adapted for instructions to agents, so that the text has one reading only.
---

# Simplified Technical English (ASD-STE100)

Text that agents read must have one reading only. These rules come from ASD-STE100, adapted for instructions to
agents. Apply all of them. The text must also read fluently: do not use sentence fragments or long chains of clauses.

## Words

1. Use one word for one meaning. When you select a word for a thing or an action, use only that word in the full
   text. Do not use synonyms for variety.
2. Give each word one meaning only. Do not use one word for two different things.
3. Use the simple, common word: "use", not "utilize" or "leverage"; "start", not "initiate"; "help", not
   "facilitate".
4. Technical names are permitted: commands, options, file names, product names, and terms of the field. Write a
   literal name (a command, a path, a key, a flag) in backticks, exactly as the agent types it.
5. Do not use a technical name as a verb. Write "run `nix fmt`", not "nixfmt the file".
6. Do not use clusters of more than three nouns. Write "the config of the remote host", not "the remote host config
   file path".
7. Do not use vague words: "appropriate", "relevant", "properly", "as needed", "etc.", "and so on". State the exact
   condition or give the full list.
8. Do not use hedge words: "should", "might", "probably", "usually", "ideally". Write "do" or "do not". If a rule has
   an exception, state the exception.

## Verbs

1. Use the simple present for facts and descriptions: "The command removes the worktree."
2. Use the imperative for instructions: "Run the tests."
3. Use the simple past and the simple future only when the time is important.
4. Use the active voice. Write "The hook rejects the commit", not "The commit is rejected". Name the agent of the
   action.
5. Do not use the "-ing" form of a verb, except in a technical name or a fixed term.
6. Do not use phrasal verbs when a single verb exists: "remove", not "get rid of"; "find", not "look up".

## Sentences

1. Put one instruction in each sentence.
2. Write a sentence for an instruction in 20 words or fewer. Write a sentence for a description in 25 words or fewer.
3. Put a condition before its instruction: "If the build fails, stop.", not "Stop if the build fails, unless ...".
4. Write one condition in each sentence. For more conditions, use a list.
5. Use the articles "the", "a", and "an". Do not drop them to save words.
6. Do not use contractions. Write "do not", not "don't".
7. Write each negation as "not" or "never". Do not use double negatives.
8. Do not write sentence fragments in running text. List items, table cells, and headings can be fragments.

## Structure

1. Give each paragraph one topic. Put the topic in the first sentence.
2. Write a paragraph in six sentences or fewer.
3. Write a procedure as a numbered list, in the order that the agent does the steps.
4. Write each step as one action. If a step has a result to check, write the check in the next sentence.
5. Put a prohibition or a risk before the step that it is about, not after it.
6. State the reason for a rule in one short sentence after the rule, when the reason is not clear. The reason helps
   the agent to decide an edge case.

## Check

Before you finish, read the text again and do these checks:

1. Each term has one meaning, and each meaning has one term.
2. Each instruction has one reading. Read each sentence and find a second meaning. If you find one, rewrite it.
3. No sentence is longer than the limits above.
4. No vague word or hedge word remains.
5. The text reads fluently aloud.

After a rewrite of existing text, compare the new text with the original through the `rewrite-fidelity` skill.
