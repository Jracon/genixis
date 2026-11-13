# code-style

Nix layout rules of the repository: what the formatter owns, and what the hand keeps.

## Formatter and Hand

`nix fmt` formats every .nix file with nixfmt-tree, CI checks the result, and the hand writes the structure that the formatter cannot decide: the order of the pieces, the comments, and the platform variance.

## Rules of the Hand

Indentation, line breaks, and the trailing commas belong to the formatter. Run `nix fmt` before each commit, and never fix a formatting dispute by hand (AGENTS.md, COMMANDS).

Rules that the hand keeps, each visible in the standing files:

1. One file holds one topic. A module file of one program names the program; a common/ file names the layer.
2. A module starts with the argument header on its own line, for example `{ config, lib, pkgs, ... }:`.
3. A `let` block holds the helpers of the file, and a one-sentence comment above each helper states its reason.
4. Flake inputs sit in name order (flake.nix).
5. A comment above an attribute states why the attribute holds its value, not what the value says.
6. Platform variance runs through the library, never through a copy of a block: `lib.mkIf`, `lib.mkDefault`, `lib.optional`, `lib.optionalString`.
7. A multi-line script sits in a `''` string.
8. A machine fact never enters the file: local.nix keys and agenix files carry it (docs/flake.md; docs/secrets.md).

## One Authority for Layout

1. A single authority, the formatter, owns the layout, so no review argues about whitespace (AGENTS.md, COMMITS).
2. Declarative Law binds the structure: one place per decision, no machine facts in the tree, platform purity (docs/flake.md).

## Purpose of the Shape

Purpose of the topic: a reader of any file finds the same shape, and a review argues about the state, not the layout. Declarative Law of docs/flake.md states the criteria.

## Write and Review Nix

Write a Nix change: follow the rules above, run `nix fmt`, then `nix flake check --impure`.

Review a Nix change: read the `let` block and the comments first. A helper with no reason stated is a finding.
