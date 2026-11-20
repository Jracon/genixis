# backups

The backup set of the agent-generated state and the forge data, and the check that a restore passes.

## The Backup Set

The backup set covers four members. Each member states its archive name and its source on the host `services`:

1. `transcripts`: `/home/dev/.claude/projects`, the transcripts of the sessions.
2. `dispatcher-state`: `/home/dev/.local/state/dispatcher`, the queue and the in-flight map of the loop.
3. `memory`: `/home/dev/projects/genixis/.claude/memory`, the memory files of the project.
4. `forgejo-data`: `/mnt/forgejo/data`, the repositories, the issues, and the database of the forge.

Measured at the design date, 2026-11-18: transcripts 730 MB, dispatcher state 1.7 MB, memory 11 KB, forge data 156 MB. One full archive holds about 0.9 GB.

The working harness state stays out of the set: the jobs, the file history, the session environment, and the tasks. It is ephemeral by design (the design record below). The credential file `.credentials.json` stays out of the set. It sits in the same tree as the transcripts. The timer stages each member by name, so no file outside the four members enters an archive.

## Realization

One timer on `services` writes one archive each day (modules/services/backup/):

1. The timer starts the oneshot unit `backups.service` once a day, through the shared daily timer shape (lib/oci-containers.nix).
2. The unit runs as root and links each source under its member name in one staging directory.
3. One pipe carries the archive. `tar` collects the four links with the `-h` option into one stream, so each source lands under its member name. `age` encrypts the stream with the public half of the recipient key. No unencrypted archive lands on the disk (issue 528).
4. The stream lands under `/mnt/backups` as `backups-YYYY-MM-DD.tar.age.part`. The unit moves it to `backups-YYYY-MM-DD.tar.age` after `age` wrote the complete stream, so the final name never holds a partial archive.
5. Before each archive lands, the unit removes every stray `backups-*.tar` and every stray `.part` of an earlier failed run. So a failed run leaves no unencrypted archive, and no stray survives a later run (issue 528).
6. The unit keeps the newest 30 archives and removes the older ones.

The activation script gives `/mnt/backups` the mode 700, so only the root user reads the landing (issue 528).

The recipient key is one `age` key pair in the ssh form. Its public half sits in the tree as `modules/services/backup/backups.pub`. Its private half stays with the owner and sits on no host of this repository. The key is no agenix secret, because no host ever decrypts an archive. Only the owner decrypts, at a restore.

The landing sits on the same host. It survives the loss or the corruption of a source tree, and it does not survive the loss of the host. The offsite copy through `rclone` to a remote of the owner is the named next step of the design record below. The offsite gap of the vaultwarden backup is a separate TODO (docs/containers.md).

## Design Record

Context: docs/services.md claimed that the agent-generated state joins a backup set, and no mechanism wrote one (issue 377). A backup design is a novel decision, so the owner stated it under the authorship scheme (docs/adr/glue-novel-boundary.md; docs/adr/socratic-contract.md).

Decision, made by the owner on 2026-11-18 on issue 377: the set covers the three agent-state members and the forge data. The archives land on a local second mount of `services`, age-encrypted at rest. A restore passes when the data is available and well-formed: the archive of the date exists, it decrypts with the private half of the recipient key, and it lists the four members. The design lands in this file, and the restore steps sit in docs/runbook.md.

Options that lost:

a. The three agent-state members alone. A loop restored without the forge loses every issue and every pull request.
b. The three members plus the working harness state. The working harness state is ephemeral.
c. An offsite landing now. No remote of the owner exists today.
d. The reuse of the recipient key of the vaultwarden backup. A dedicated key keeps the two sets separate: one leaked key voids one set, not two.
e. A retention without a bound. One full archive a day grows the landing by about 27 GB each month.

Consequences: the host `services` writes one full archive each day, and the retention bounds the landing at about 27 GB. A restore needs the private half of the recipient key, which no host holds. The landing does not survive the loss of the host, and the offsite copy through `rclone` is the next step. The forge member is a live copy: the database file can hold a state between two transactions. The check of a restore reads the files, not the database.

Status: accepted.

Reopen trigger: the remote of the offsite step exists, or a restore fails its check.

## Restore the Set

The restore steps sit in docs/runbook.md, because a restore crosses the topics of this tree.

## Purpose of the Backups

Purpose of the topic: the agent state and the forge data survive the loss or the corruption of a source tree, and the owner verifies a restore as available and well-formed.
