# Pinned fixtures

These two files are verbatim copies from the CLI agent specification repository
(<https://github.com/cli-agent-spec/cli-agent-spec>), MIT licensed:

- `exit-code.json` from `schemas/exit-code.json`
- `response-envelope.json` from `schemas/response-envelope.json`

Pinned revision: commit `9eaca2e520562483ca9f00db77f7cbfd509f0235` (`master`),
fetched on 2026-11-03 from
`https://raw.githubusercontent.com/cli-agent-spec/cli-agent-spec/9eaca2e520562483ca9f00db77f7cbfd509f0235/schemas/`.

The tool adopts the exit-code table and the response envelope as internal
conventions (issue #74, phase 3; investigation on issue #66). It does not
adopt the conformance kit or the skills of that specification, and it takes no
runtime dependency on it: the files exist so the tests can pin this tool's
contracts against a known source. If the specification dies, these fixtures
survive as the contract.

To re-vendor: fetch both files at a chosen revision, replace them here, and
update the revision above. The tests in `../spec_test.go` then fail on any
change to the table or the envelope shape that this tool does not follow.
