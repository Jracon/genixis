---
name: diataxis
description: Use when you write, review, or structure documentation: a topic file, a tutorial, a how-to guide, reference, or explanation. Gives the four documentation forms of Diataxis, the compass that decides between them, and the craft rules of each form.
---

# Diataxis

Diataxis names four forms of documentation and puts them into one map. Each form serves one need of a reader. Where the repository carries its own documentation law, that law wins. This skill gives the general craft.

## The Compass

Decide the form of a piece of text with two questions:

1. Does the text serve action or cognition? Action is doing. Cognition is knowing and understanding.
2. Does the reader acquire a skill or apply one? Acquisition is study. Application is work.

The answers select the form:

| Action or cognition | Acquisition or application | Form |
| ------------------- | -------------------------- | ----------------- |
| action | acquisition | tutorial |
| action | application | how-to guide |
| cognition | application | reference |
| cognition | acquisition | explanation |

The question of the reader names the form in the same way. "Can you teach me to do this?" asks for a tutorial. "How do I do this?" asks for a how-to guide. "What is this?" asks for reference. "Why is it this way?" asks for explanation.

Apply the compass at any grain: a word, a sentence, a section, a whole document. When the form of a text feels obvious at once, apply the compass anyway, because the immediate answer is often the wrong one.

Study versus work decides the split between a tutorial and a how-to guide. Basic versus advanced does not. A how-to guide can be basic. A tutorial can be advanced.

## Procedure

1. Classify each piece of text with the compass.
2. Check the text for mixed forms. A piece that serves two needs serves each one badly.
3. Separate what is mixed. Move each part to the home of its form, or link to that home.
4. Apply the craft rules of the form.
5. Link between forms. Do not mix them.

## Tutorials

A tutorial is a lesson. Its purpose is that the learner learns, not that a result ships.

1. A tutorial is a contract. The tutor carries the responsibility for success. Write so that an attentive learner cannot fail.
2. Open with the destination: "In this tutorial we will build and deploy a small service." Do not write "In this tutorial you will learn", because it presumes the outcome and names no result.
3. Deliver a visible result at every step. Show the expected output before the learner runs the step.
4. Flag the signs of a wrong turn. Say what surprising output means.
5. Point at what the learner should notice. Close each loop of learning.
6. Keep the explanation to the minimum. Give one sentence of reason where a step needs one, and link to explanation for the depth.
7. Stay concrete. Learning moves from the concrete to the general. Ignore options and alternatives.
8. Write for reliability. A learner has no rescue, so the steps must not fail.
9. Speak as "we". Use plain imperatives: "Run the command." Write "Notice that..." at each point of attention.
10. Invite repetition. A learner who repeats the steps owns the skill.

## How-To Guides

A how-to guide leads a competent reader through one real task.

1. Name a guide after a real goal of the reader: "How to back up the database". Do not use a gerund. Do not use a bare noun. Both hide the goal.
2. Assume the ground. The reader knows the tool and the field, so start at the task.
3. Keep the guide on one goal. Do not explain inside it, and do not collect reference material in it for completeness. Link to both.
4. Prefer usability over completeness. A guide starts and ends at a reasonable place, and the reader joins it to their own work.
5. Write conditional steps: "If you want X, do Y."
6. Count a judgement or a check as a step. A step is not only a command.

## Reference

Reference describes the machinery of the product, and it describes nothing else.

1. Describe, and only describe. Instruct nowhere. Argue nowhere.
2. Write reference to be consulted, not read. Keep it austere.
3. State facts with no doubt and no ambiguity. The reader needs truth and certainty.
4. Structure reference like the product it describes. Put material where the reader expects it.
5. Hold one pattern across all reference pages. Reference is no place for variety of style.
6. Give an example where it illustrates. An example shows, and it does not explain.
7. Write plain statements, lists of options, and warnings: "You must...", "Never...".

## Explanation

Explanation is discussion. It is the one form that can carry opinion and perspective.

1. Connect the topic to its neighbors. Give the context: the history, the constraints, and the design decisions.
2. Take the bigger picture. A title fits the shape "About X".
3. Weigh the alternatives. Say what else was possible, and why it lost.
4. Keep the explanation bounded. It carries no instruction and no technical description.
5. Scope an explanation with a real question of the form "Why...?".

## Failure Modes

| Mode | Cause | Fix |
| --- | --- | --- |
| Tutorial and guide collapse | one document serves study and work | split it, and link between the two |
| Explanation inside reference | an example grows into a discussion | keep reference to description, and link out |
| Explanation inside a tutorial | the wish to teach more | one sentence of reason per step, and link out |
| Machinery-defined guide | steps named after the tool | name the guide after the goal of the reader |
| Empty four-form scaffolding | structure before content | let structure grow from content |
| "You will learn" opening | presumption of the outcome | state what "we will do" |
| Vague title | gerund or bare noun | "How to X", with the real goal of the reader |

## Growth of the Set

1. A documentation set needs no complete four forms. There is no exam. Serve the needs that exist.
2. Improve one piece at a time, and publish each step at once. Every step in the right direction is worth an immediate release.
3. Let structure grow from inside. Do not impose a plan on the set.

## Example

A request arrives: "Write a getting-started page for the tool." The reader is new, so they acquire skill, and the page walks actions. The compass answers: tutorial. The rules that bind: show the destination, one visible result per step, no explanation beyond one sentence, the "we" voice. Reference material that the draft collects moves to the reference page. The reasons for the design move to explanation. Links replace all three in the tutorial.

## Sources

This skill paraphrases the Diataxis framework of Daniele Procida (https://diataxis.fr), read in full on 2026-11-13. The site text is licensed CC BY-SA 4.0. This file copies no passage from it.
