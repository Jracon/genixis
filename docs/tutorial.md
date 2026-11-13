# tutorial

Walkthroughs of the repository: one lesson per section, and each section carries the date of its last walk. A walkthrough restates the steps that it teaches (docs/design.md, Documentation Law).

## Rebuild a Machine

In this walkthrough we rebuild one host of this flake from a checkout, and we read the package diff before the switch. We use the host `media` as the example, and we put our own host name in the place of `media`.

The ground: a machine of this flake past its first successful switch (README owns the steps before that switch), and a checkout of this repository.

Last walk: not walked yet.

1. We run `direnv allow` in the root of the checkout. Each checkout allows its environment once. We see `direnv: loading` and then `direnv: export`, and the tools of the devShell are on the path.
2. We run `local-rebuild media`. The command runs nh, and nh builds the new configuration before it touches the machine. We see the build output end, and then a table of the packages that change.
3. We read the table. We notice the count of upgrades, of new packages, and of removals. Nothing has changed on the machine yet, so this is the place to stop when a row surprises us.
4. We confirm at the prompt of nh. nh asks for the sudo password itself, activates the new generation, and prints the activation summary. We see the summary end with the number of the new generation.
5. We see the result at the next start of the machine: the boot menu lists the new generation first, and the menu keeps five generations in total.
6. We close the loop: when the boot menu has held five generations for a while, we run `cln`. The command keeps five generations and the current one, and it prints each one that it removes.

We repeat this walk after each change that we want on the host: the table then shows only what that change did.

The path without a checkout, the standalone homes, and the mirror fallback live in docs/runbook.md, and the plain-word commands of the shell live in docs/cli.md.
