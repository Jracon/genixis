# Progress

The per-area count of planned and done work of the review. The board of the
project binary reads this file and shows the counts beside the frontier
(issue #102). One line is one item. An unchecked box is planned work, and a
checked box is done work. Name the issue of an item at its end. Mark the
line in the same commit that lands the item. The stages of #166 own the
order of the work.

## Flake mechanics and hosts

- [x] Stage 0: every phase of #74 holds a verdict, and the register holds one per entry (#166).
- [x] Stage 0: the transport decision is on record. The LAN is primary, and the tailnet is the roaming fallback (#167).
- [ ] Stage 3: the dormant hosts meet their verdict: wsl and bare (#166).
- [ ] Stage 7: audit the flake mechanics, the host wrappers, and the outputs (#166).

## Self-hosted services

- [x] Stage 0: the usage inventory lists every container group by host (#166).
- [ ] Stage 3: each container group names what it still serves, and the owner confirms the list (#166).
- [ ] Stage 3: the register verdicts land: the authentication of rclone-webdav, and the rclone TODO of vaultwarden (#166).
- [ ] Stage 3: the media host keeps one syncthing instance (#166).

## The project binary

- [x] The pull-request flow: project review opens a pull request as the worktree review/pr-n (#181).
- [x] The board joins the frontier, the open issues, and the open pull requests (#102, #181).
- [ ] Stage 4: audit each subcommand, flag, and code path (#165 follows in #166).

## The terminal layer

- [x] The editor phases of #105: languages and pinning, small additions, structure, debug and replace (#105).
- [x] The reviewer rig: the diff flow against the base branch, with lazygit, hunk, and tuicr as surfaces (#181).
- [ ] Stage 4: re-derive the keymap from the layers (#165).
- [ ] Stage 4: remove the copy-paste of the popup bindings (#154).

## The agent harness

- [x] The two writing skills carry their new names, technical-english and semantic-diff (#178).
- [x] The explicit-instruction rule leads the work rules (#180).
- [ ] Stage 5: audit the forge hook, the plans, the identities, and the skills, and tier each hook rule (#166).

## The dispatcher and agentsview

- [x] Stage 0: the loop verdict is continue-build (#166).
- [ ] Stage 6: audit the receiver and the dispatcher, and move the README into this tree (#166).
- [ ] Stage 6: land #152 under its own issue, with the repository filter of the receiver (#166).

## The secrets and identity spine

- [x] Stage 0: the register verdicts for the ssh route, the hosts pin, and the mirror fallbacks (#166).
- [ ] Stage 7: audit the secrets spine and the ssh key rules (#166).

## Documentation, CI, and templates

- [x] Stage 2: the documentation tree holds each reference file, and AGENTS.md names them (#173).
- [x] The qmd index is project-local, and one vendored search skill serves qmd and semble (#179).
- [ ] Stage 7: the issue template gains the how-to-test section, the scope lines, and the size rule (#166).
- [ ] Stage 7: write the runbook of a produced project, and the final content pass of every reference file (#166).
