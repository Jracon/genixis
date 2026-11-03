# Golden ide fixtures

These files freeze the pure parts of the ide window builder that used to live
in fish functions and store scripts (`ide`, `__ide_claude`, `ide-layout` in
modules/programs/cli/{fish,tmux,yazi}.nix, before the Go rewrite of issue
#74, phase 3). A window keeps its socket, its start script, and its `@ide_*`
options for its whole life, and the tmux hooks and yazi openers read them, so
these values are a consumer contract: an accidental change fails the tests.

## How to regenerate

Run the generator with fish 4.x and jq on PATH:

    fish modules/programs/cli/project/internal/ide/testdata/generate.fish

It rewrites `escape-cases.json`, `escape-golden.txt`, and `claude-start.txt`
in place. The case list lives in the generator itself; adding a case changes
the first two files together, and the Go test walks them in order. Record the
reason for a deliberate change in the commit message.

## What each file holds

- `escape-cases.json`: the words that reach `FishEscape`, as a JSON array:
  socket paths (with the double slash a macOS TMPDIR leaves), settings JSON
  of both spawn forms, prompt words, the `-c` argument of a reloaded nvim,
  and one adversarial word per fish escaping class.
- `escape-golden.txt`: fish's `string escape --` output for those words, one
  per line, in the same order. The bytes below 0x20 that fish passes through
  raw (0x1a, 0x1c-0x1f) sit in the file as invisible bytes; a diff tool that
  shows control characters is the way to inspect them.
- `claude-start.txt`: the two-line fish script that started claude in the
  agent pane, from the `__ide_claude` body of the fish implementation, for
  one fixed socket and one fixed claude command line (a replan: `--continue`,
  settings with the zai plan, a permission mode, and a prompt after `--`).
  The first line removes the script itself; the second is the claude command
  with each argument fish-escaped.
