---
name: adr
description: Use when a review or a task settles a decision that outlives the session, and a decision record is due: an ADR, a register entry, a decision log line. Tells when a decision needs a record and how to write each field: context, decision, options that lost, consequences, status, and the trigger that reopens it.
---

# Decision Records

A decision record states one decision, the forces that shaped it, and its outcome, for a reader who was not present. Where the repository carries its own register law, that law wins. This skill gives the general craft.

## When To Write A Record

1. Write a record when a future reader could only accept a decision or change it with no knowledge of its reason. A project that piles up such decisions grows afraid of change.
2. Write one record for one decision.
3. Do not write a record for a trivial decision, for a self-contained decision, or for a decision that other documents already carry.
4. Record the outcome of a decision, not a plan. A record is a journal, and it is not a proposal.
5. Do not defer the record of a decision that is costly to undo.
6. Treat the draft as part of the decision. The draft surfaces disagreement before the change lands.

## Fields Of A Record

1. Title: a noun phrase that names the decision.
2. Context: the forces at play, stated as facts. Keep the language free of value. Name each tension as a tension. Two or three sentences hold it. A consequence of an earlier record often becomes the context here.
3. Decision: the response to the forces. Write it in the present tense, in full sentences, in the active voice. State it with no hedge. Name the deciders where the practice asks for accountability.
4. Options that lost: each serious alternative, with the reason that it lost. The original form of Nygard omits this field. MADR and Fowler both make it central. This skill takes their side: a record with no lost options does not say why the winner won.
5. Consequences: the new context after the decision. List the negative and the neutral outcomes, not only the positive ones. Flag the follow-up records that the decision needs.
6. Reopen trigger: the event that puts the decision back on the table. Write an event, never a sentiment. "The router cannot hold the override" reopens a record. "We feel unsure" does not.
7. Status and supersession: proposed, accepted, deprecated, or superseded. A supersession names the record that it replaces. The replaced record points at its replacement. Numbers run in one monotonic sequence, and no number is reused. Never rewrite an accepted record. Supersede it.

## Shape Rules

1. Keep a record to one or two pages.
2. Write prose in full sentences. Use a list only for a real list. A bullet is no permit for a fragment.
3. Put the material of the decision first, and the detail after it.
4. Link the supporting material. Do not inline it.

## Failure Modes

| Mode | Cause | Fix |
| --- | --- | --- |
| Fairy tale | only the pros, or a truism | state the negative outcomes |
| Sales pitch | marketing language | plain facts, and no adjective with no backing |
| Dummy alternative | a straw man that flatters the winner | name the serious alternatives |
| Free lunch | no consequences named | write the costs |
| Sprint | one option, and a short-term view only | name the second option, and the long-term cost |
| Tunnel vision | local context only | include operations and maintenance |
| Mega record | a design document in disguise | link the design, and keep the decision |
| Blueprint in disguise | law voice instead of journal voice | record what was decided, not what to do |
| Stale status | the status line lags the world | update the status with each supersession |
| Record that nobody read | no reader saw it after the write | name the readers, and point them at the record |

## Sources

This skill paraphrases its sources and copies no passage from them. Nygard, Documenting Architecture Decisions (https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions). Fowler, ArchitectureDecisionRecord (https://martinfowler.com/bliki/ArchitectureDecisionRecord.html). The templates and practices of adr.github.io (https://adr.github.io). MADR, with its own record set (https://github.com/adr/madr). The creation and review anti-patterns of Zimmermann (https://www.ozimmer.ch/practices/2023/04/03/ADRCreation.html). A community template collection ships a skill of this kind already (https://github.com/joelparkerhenderson/architecture-decision-record).
