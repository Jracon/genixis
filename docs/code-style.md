# code-style

The Nix layout rules of the repository: what the formatter owns, and what the hand keeps.

Domain: what. Reader: a session that writes or reviews a Nix change.
Code: the .nix files of the repository, flake.nix, the treefmt config behind `nix fmt`.

## What is the topic?

`nix fmt` formats every .nix file with nixfmt-tree, CI checks the result, and the hand writes the structure that the formatter cannot decide: the order of the pieces, the comments, and the platform variance.

## How is the topic realized?

The formatter owns the layout: indentation, line breaks, and the trailing commas. Run `nix fmt` before each commit, and never fix a formatting dispute by hand (AGENTS.md, COMMANDS).

The hand keeps these rules, each visible in the standing files:

1. One file holds one topic. A module file of one program names the program; a common/ file names the layer (flake.nix:107-143; common/).
2. A module starts with the argument header on its own line, for example `{ config, lib, pkgs, ... }:` (common/base.nix:1-5).
3. A `let` block holds the helpers of the file, and a one-sentence comment above each helper states its reason (modules/programs/cli/fish.nix:9-57; agenix-rules.nix:1-9).
4. The flake inputs sit in name order (flake.nix:4-62).
5. A comment above an attribute states why the attribute holds its value, not what the value says (common/homebrew.nix:11-15).
6. Platform variance runs through the library, never through a copy of a block: `lib.mkIf`, `lib.mkDefault`, `lib.optional`, `lib.optionalString` (flake.nix:114-143; modules/programs/cli/fish.nix:387-394; common/wsl.nix:8).
7. A multi-line script sits in a `''` string (modules/programs/cli/fish.nix:63-405; common/ssh.nix:18-20).
8. A machine fact never enters the file: local.nix keys and agenix files carry it (docs/flake.md; docs/secrets.md).

## Why is the topic that way?

1. The formatter is the one authority on layout, so no review argues about whitespace (AGENTS.md, COMMITS).
2. The declarative law binds the structure: one place per decision, no machine facts in the tree, platform purity (docs/design-philosophy.md, Declarative law items 1, 5, and 7).

## What does the topic enable?

The end of the topic: a reader of any file finds the same shape, and a review argues about the state, not the layout. The Declarative law of docs/design-philosophy.md states the criteria.

## How does a reader use and change the topic?

Write a Nix change: follow the rules above, run `nix fmt`, then `nix flake check --impure`.

Review a Nix change: read the `let` block and the comments first. A helper with no reason stated is a finding.
