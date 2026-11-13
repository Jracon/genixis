---
name: search
description: Use when a task must find text, code, or indexed Markdown, or must build or refresh a qmd index. Gives the routing rule between `rg`, `semble`, and `qmd`, the qmd query grammar and commands, and the semble commands and cache.
---

# search

This skill gives the routing rule between the search tools of this machine and one section per tool.

## Routing

1. Use `rg` when you know the exact tokens. It reads the files of the working tree.
2. Use `semble` when you search code by meaning and do not know the words.
3. Use `qmd` when the answer may sit in indexed Markdown.
4. Use `semble --content docs` for Markdown that no qmd collection holds.

`rg` and `fd` respect `.gitignore`. Use `rg --no-ignore` and `fd -I` when the answer can sit in an ignored file.

Change an index only when the task asks for setup or maintenance.

## qmd: search indexed Markdown

`qmd` searches Markdown that an index covers: notes, transcripts, documentation trees, and wikis. It runs three
local models. One model expands the query, one model embeds the text, one model reranks the results.

Source: the `qmd` skill and `docs/SYNTAX.md` of the `tobi/qmd` repository at tag `v2.8.3`, the installed version,
by Tobias Lütke, MIT license. This text keeps the query grammar and the commands of the source. It removes the
MCP server, the HTTP API, the npm install, and the skill-install commands, because this machine uses the
command line only.

### The index of a checkout

1. A repository can commit `.qmd/index.yml`. Each checkout of that repository stores its database under `.qmd/`.
   Git ignores the databases and caches under `.qmd/`.
2. Every command inside the tree uses that config. qmd needs no flag and no variable for this.
3. Build the database of a fresh checkout with `qmd update`, then `qmd embed`.
4. qmd asks for approval only when the config defines an update command, a path outside the project, or a model
   that is not a default. Run `qmd trust` to approve the config. Run `qmd trust list` to list the approvals.
5. Check the freshness of the index before a long search. Compare the file count that `qmd status` reports for the
   collection with the count of the Markdown files on disk. The command `fd -e md . docs` lists the files of the
   `docs` tree. When the counts differ, run `qmd update`, then `qmd embed`.

### Permissions on this machine

1. The read verbs of `qmd` sit in the global allow list of `claude.nix`. The rules for `qmd update` and `qmd embed`
   sit in that list too, not in the project allowlist of a repository, because this skill sends the sessions of
   every project to these two commands.
2. Each rule covers the bare command only, because `qmd update --pull` also runs `git pull`.
3. A change to these rules goes into `claude.nix`: a session cannot edit the project allowlist of a repository
   unattended. The changed rules reach the sessions of a machine only after the next switch of the home.

### Cost

1. `qmd search` runs BM25 only, with no model. It answers in less than a second.
2. `qmd query` runs the models. The expansion takes about 10 seconds. On a host without a GPU, the reranker adds
   minutes. Pass `--no-rerank` to skip the reranker.
3. When `qmd query` fails on a model or on a device, run `qmd search` with better keywords.

### Score

The score is a blend of retrieval ranks and reranker ratings. It is not a measure of relevance. Read the top
chunks of a result list, not only the first chunk. A chunk with a lower score can hold the answer.

### Query grammar

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

### Lex syntax

| Syntax | Meaning | Example |
| --- | --- | --- |
| `word` | Prefix match | `perf` matches "performance" |
| `"phrase"` | Exact phrase | `"rate limiter"` |
| `-term` | Exclude a term | `performance -sports` |
| `-"phrase"` | Exclude a phrase | `performance -"test data"` |

The `-term` syntax works in `lex:` lines only.

### Commands

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

### Search procedure

1. Run `qmd search '<keywords>' -n 10` first when you know keywords.
2. Run `qmd query` with typed lines when you do not know the words of the source or the topic is wide.
3. Read the top chunks of the results. The snippets are leads, not answers. Fetch the full text with `qmd get`
   before you quote or decide. Cite the file and the line numbers of the text that you use.

### macOS

A `libggml-metal` backtrace at the end of an output does not mean a failure. Read the result above it. The
command still succeeded.

## semble: search code by meaning

`semble` ranks the chunks of a path by their meaning. It chunks the files with tree-sitter and ranks the chunks
with BM25 and one local embedding model. The default content type is code.

Never run `semble install` or `semble uninstall`. They write the configuration of coding agents. This machine
uses the command line only.

### Commands

| Command | Action |
| --- | --- |
| `semble search '<query>' [path ...]` | Ranks the chunks of the paths by the meaning of the query. Without a path, it searches the current directory. |
| `semble find-related <file> <line>` | Ranks the chunks that relate to the chunk at the line of the file. |

1. Give `<file>` exactly as the results of `semble search` print it. The results print paths relative to the
   searched path. A path from the working directory fails.
2. The line number is 1-indexed, as the results show it.

Flags: `-k <num>` sets the result count. The default is 5. `--content` sets the content types: `code`, `docs`,
`config`, or `all`. The default is `code`, and the flag accepts several types in one space-separated list.
`--format json|text` sets the output format. The default is `json`. `--max-snippet-lines <num>` sets the lines of
source per result. The value 10 gives the signature and the body, the value 0 gives no code, and the default
gives the full chunk.

The JSON output holds a `query` field and a `results` array. Each result holds `file_path`, `start_line`,
`end_line`, and `score`. Read the file at the line range of a result before you quote it.

### The cache

1. A first search of a path builds an index. The index lives under `~/.cache/semble/`, in one directory per
   searched path set. The grammars of tree-sitter live under `~/.cache/semble/grammars/`.
2. The cache is state of the host, not state of a checkout. No flag of the two commands moves it into the
   project folder.
3. A search reuses the cached index of the path. The index does not see a file change after its build. When a
   result disagrees with the file on disk, read the file.

### Models

`semble` and `qmd` share no model. `qmd` keeps three ggml models under `~/.cache/qmd/models/`. `semble` downloads
one embedding model, `minishlab/potion-code-16M-v2`, into the Hugging Face cache. The `libggml-metal` note in the
qmd section covers `qmd` only.
