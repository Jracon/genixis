---
name: qmd
description: Use when a task must find text in an indexed Markdown collection, or must build or refresh a qmd index. Gives the routing rule against `rg` and `semble`, the query grammar, the commands, and the meaning of the score.
---

# qmd: search indexed Markdown

`qmd` searches Markdown that an index covers: notes, transcripts, documentation trees, and wikis. It runs three
local models. One model expands the query, one model embeds the text, one model reranks the results.

Source: the `qmd` skill and `docs/SYNTAX.md` of the `tobi/qmd` repository at tag `v2.8.3`, the installed version,
by Tobias Lütke, MIT license. This text keeps the query grammar and the commands of the source. It removes the
MCP server, the HTTP API, the npm install, and the skill-install commands, because this machine uses the
command line only.

## Routing

1. Use `rg` when you know the exact tokens. It reads the files of the working tree.
2. Use `semble` when you search code by meaning and do not know the words.
3. Use `qmd` when the answer may sit in indexed Markdown.

Change an index only when the task asks for setup or maintenance.

## The index of a checkout

1. A repository can commit `.qmd/index.yml`. Each checkout of that repository stores its database under `.qmd/`.
2. Every command inside the tree uses that config. qmd needs no flag and no variable for this.
3. Build the database of a fresh checkout with `qmd update`, then `qmd embed`.
4. qmd asks for approval only when the config defines an update command, a path outside the project, or a model
   that is not a default. Run `qmd trust` to approve the config. Run `qmd trust list` to list the approvals.
5. Check the freshness of the index before a long search. Compare the file count that `qmd status` reports for the
   collection with the count of the Markdown files on disk. The command `fd -e md . docs` lists the files of the
   `docs` tree. When the counts differ, run `qmd update`, then `qmd embed`.

## Cost

1. `qmd search` runs BM25 only, with no model. It answers in less than a second.
2. `qmd query` runs the models. The expansion takes about 10 seconds. On a host without a GPU, the reranker adds
   minutes. Pass `--no-rerank` to skip the reranker.
3. When `qmd query` fails on a model or on a device, run `qmd search` with better keywords.

## Score

The score is a blend of retrieval ranks and reranker ratings. It is not a measure of relevance. Read the top
chunks of a result list, not only the first chunk. A chunk with a lower score can hold the answer.

## Query grammar

A query is one expand query or one query document of typed lines:

```
query          = expand_query | query_document ;
expand_query   = text | "expand:" text ;
query_document = [ intent_line ] { typed_line } ;
intent_line    = "intent:" text ;
typed_line     = ("lex" | "vec" | "hyde") ":" text ;
```

1. `lex:` keywords for BM25. Use exact terms, titles, names, and code symbols.
2. `vec:` a question in natural words, for the vector search.
3. `hyde:` 50 to 100 words of the answer that you expect.
4. `intent:` context that removes an ambiguity of the query. It names what you search for and what you avoid.
   The `intent:` line does not search. It steers the expansion, the rerank, and the snippet choice. Write at most
   one `intent:` line, never alone.
5. A single line with no type goes to the expansion model. The model writes the `lex`, `vec`, and `hyde` lines.
   Do not mix `expand:` with typed lines.

Write the typed lines yourself when you know the words of the field. You know the context of the task; the
expansion model does not. When you write a query document, write `intent:` and one `lex:` or `vec:` line at
minimum.

The first query line carries two times the weight in the fusion. Put your best line first.

## Lex syntax

| Syntax | Meaning | Example |
| --- | --- | --- |
| `word` | Prefix match | `perf` matches "performance" |
| `"phrase"` | Exact phrase | `"rate limiter"` |
| `-term` | Exclude a term | `performance -sports` |
| `-"phrase"` | Exclude a phrase | `performance -"test data"` |

The `-term` syntax works in `lex:` lines only.

## Commands

| Command | Action |
| --- | --- |
| `qmd query '<question>'` | Hybrid search: expansion, BM25, vectors, rerank. |
| `qmd search '<keywords>'` | BM25 only. Fast. No model. |
| `qmd vsearch '<question>'` | Vector search only. |
| `qmd get <file>` | Prints one document with line numbers. |
| `qmd multi-get <pattern>` | Prints several documents: one glob or a comma-separated list. |
| `qmd status` | Reports the index, the collections, and the file counts. |
| `qmd doctor` | Diagnoses the install: the runtime, the models, the device. |

Flags: `-n <num>` sets the result count. `-c <name>` limits the search to one collection; repeat the flag for
more collections. Without `-c`, the search covers every collection. `--format json` prints output that a program
can read. `--explain` prints the score trace of each result. `--full-path` prints on-disk paths instead of
`qmd://` URIs. `--no-rerank` skips the reranker.

`qmd get` reads a line range with a suffix: `qmd get 'docs/flake.md:40:20'` prints 20 lines from line 40. Use the
suffix, not `head` or `sed`, because the suffix keeps the line numbers and the document header.

## Search procedure

1. Run `qmd search '<keywords>' -n 10` first when you know keywords.
2. Run `qmd query` with typed lines when you do not know the words of the source or the topic is wide.
3. Read the top chunks of the results. The snippets are leads, not answers. Fetch the full text with `qmd get`
   before you quote or decide. Cite the file and the line numbers of the text that you use.

## macOS

A `libggml-metal` backtrace at the end of an output does not mean a failure. Read the result above it. The
command still succeeded.
