# The plan decisions of the project tool

Record 10 of the register. The index of the register sits in docs/decisions.md.

10. The plan decisions of the project tool. Made: early November 2026, in the plans design thread of issue 38; the origin record sits on issue 218. Decision: only the commands that start a session take a plan. The token of a plan is an agenix secret. No token sits on a command line. Reasons: the token rule of docs/secrets.md, because a token reaches a process only through a file that the process reads; only the commands that start a session route an endpoint. Alternatives that lost: a token in an environment variable or a command argument; a plan flag on every command. Reopens: a second harness, or a new form of endpoint.
