# threads

The thread store: the coordination records of the loop as plain markdown in this repository.

## The Thread Store

1. The store is the `threads/` tree at the root of the repository. One directory holds one thread. A thread is the record of one coordination conversation: an issue thread of the loop, or the review verdict of a pull request.
2. The forge stays the working surface of the loop. The store holds records only, and it runs no step of the loop: no gate, no label, and no rule reads a thread. The forge carries the review and the merge (docs/design.md, Stance).
3. A decision of record stays in the register (docs/decisions.md). When a thread settles a decision, the thread holds the conversation and the register holds the decision. One fact keeps one home (docs/design.md, Documentation Law item 9).
4. A human reads a full thread with an editor alone. Plain search reaches every record, because each thread is plain markdown (docs/design.md, Documentation Law item 4).

## Format of a Thread

1. The directory name of a thread is its slug. A slug holds lowercase letters, digits, and hyphens, for example `review-702`.
2. `thread.md` holds the body of the thread. A frontmatter block between two `---` lines opens the file, and the markdown of the body follows it. The keys of the block:
   a. `title:` the subject of the thread, on one line.
   b. `author:` the login of the writer of the body.
   c. `date:` the time of the write, in UTC, in the shape `2026-11-27T20:00:00Z`.
   d. `status:` `open` or `closed`.
   e. `origin:` the address of the entity that a migration copied. Omit this key for a thread that was born in the store.
3. One file holds one event of the thread. The file name joins the four-digit sequence, the type, and the author, for example `0001-verdict-claude-bot.md`. The sequence starts at `0001` and grows by one. The reading order is the name order of the files: the body first, then each event by sequence.
4. A frontmatter block opens an event file, and the text of the event follows it. The keys of the block:
   a. `type:` the type of the event, from the list below.
   b. `author:` the login of the writer of the event.
   c. `date:` the time of the write, in UTC, in the shape of the body key.
5. Two types exist. `comment` is one reply of the conversation. `verdict` is one review verdict of a pull request. A new type enters with the change that needs it, and this file and the tool learn it in one commit.

## Commands of the Store

`project threads` reads and writes the store (modules/programs/cli/project). A write verb writes files only. The caller commits the write as a normal git commit of its branch, so a write lands through a pull request.

1. `project threads list` prints one line per thread: the slug, the status, the count of events, and the title.
2. `project threads show <slug>` prints one thread in reading order.
3. `project threads new <slug> --title <title> --body-file <file>` writes `thread.md` of a new thread. `--author` names the writer, and the git identity of the checkout answers when the flag is absent. `--origin` records a migration. `--status` sets the status, and `open` is the default.
4. `project threads add <slug> --type <type> --body-file <file>` writes the next event file of a thread.
5. The text of a write comes from the file that `--body-file` names. With no flag, the command reads piped text, and a call at a terminal names the flag, because a terminal answers no text.
6. The commands share the exit-code table of the tool: an unknown slug answers 5, and an argument error answers 2 (docs/project.md).

## Store Law

Store Law of this topic, at its application (docs/design.md holds the map):

1. A thread is plain markdown. A human reads a full thread with an editor alone, and no tool of the store stands between a reader and a record.
2. No secret and no session transcript enters a thread. A thread holds only coordination text that the forge already shows in the clear (docs/secrets.md, Security Law item 8).
3. The store holds records, and it runs no step of the loop. The forge reviews and merges (docs/design.md, Stance).
4. An agent writes a thread through `project threads`, and the write lands as a git commit of a pull request. A person writes the same files with an editor, and the format, not the tool, is the contract.

## Purpose of the Store

Purpose of the topic: the repository carries the coordination state of the loop, so a reader with no forge and no agent answers a question about past coordination from a checkout alone. Store Law above states the criteria.

## Use and Change the Store

Read a thread: open `threads/<slug>/thread.md`, then each event file in name order. `project threads show <slug>` prints the same order.

Write a thread: run the write verbs inside a checkout, then commit the files that they wrote.

Migrate a thread of the forge: read the entity with tea, write the body and one event per comment through the tool, and set `origin` to the address of the entity.

Change the store: edit this file, the commands, and the go tests in one commit (docs/design.md, Documentation Law item 2).
