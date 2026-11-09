# Golden settings fixtures

These files are the exact stdout of the jq pipelines of the former fish
implementation of `project` (modules/programs/cli/project.nix, before the Go
rewrite), run with jq 1.7 on 2026-11-03. They freeze the `--settings` bytes
that a Claude Code session of `project open` and `project spawn` receives.
The forge hook and the ide window builder read the marker keys inside, so a
byte change is a consumer change.

Fixed inputs of the fixtures:

- project directory: `/home/dev/proj`
- worktree: `/home/dev/proj/feat-x`, branch `feat-x`
- worktree git dir: `/home/dev/proj/main/.git/worktrees/feat-x`
- entries of `main/.git` (sorted, `worktrees` excluded): `HEAD`, `config`,
  `description`, `hooks`, `info`, `objects`, `packed-refs`, `refs`
- plan `zai`: env `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic`,
  the three `ANTHROPIC_DEFAULT_*_MODEL` values `glm-4.6`, token file
  `/run/agenix/zai_token`

## open, no plan (open.json)

    jq -cn --arg dir /home/dev/proj/.claude/memory --arg planName '' \
      --argjson plan '{}' \
      '{autoMemoryDirectory: $dir} * $plan * {env: {PROJECT_PLAN: $planName}}'

## open, plan zai (open-plan.json)

The plan object is what the fish built from the plan file:

    jq -cn '{env, apiKeyHelper: ("cat " + (.tokenFile | @sh))}' plan-zai.json

then:

    jq -cn --arg dir /home/dev/proj/.claude/memory --arg planName zai \
      --argjson plan "$PLAN" \
      '{autoMemoryDirectory: $dir} * $plan * {env: {PROJECT_PLAN: $planName}}'

## spawn (spawn-windowed.json, spawn-headless.json)

With `$reads` the list named above and `$mark` the marker object
(`{"env":{"PROJECT_SPAWN_SESSION":"1"}}` windowed,
`{"env":{"PROJECT_HEADLESS_SESSION":"1","PROJECT_SPAWN_SESSION":"1"}}`
headless):

    jq -cn --arg dir /home/dev/proj/.claude/memory --arg git /home/dev/proj/main/.git \
      --arg planName '' --argjson plan '{}' --argjson mark "$MARK" --args '{
        autoMemoryDirectory: $dir,
        permissions: {
          allow: ([$ARGS.positional[] | "Read(/\(.))", "Read(/\(.)/**)"] + ["Bash(ls \($git))"]),
          deny: ["Edit(/\($git))", "Edit(/\($git)/**)"]
        }
      } + $plan * $mark * {env: {PROJECT_PLAN: $planName}}' $reads

The leading `//` of each `Read(...)` path is the absolute-path form of a
session permission rule; jq renders it as `Read(/` + `/abs/path`.

## spawn with plan (spawn-windowed-plan.json, spawn-headless-plan.json)

The same command with `--arg planName zai` and `$plan` from the plan object
above.

## The hooks key (issue #190, 2026-11-09)

Every shape gained a hooks key: one PostToolUse hook on the tools that write
files, which runs `project ide follow`, so the nvim pane of the ide window
follows the file that the session wrote. The fish implementation never wrote
this key; the Go builder appends it to every shape. The jq form of the
addition is one argument and a final merge:

    --argjson follow '{"PostToolUse":[{"matcher":"Write|Edit|NotebookEdit","hooks":[{"type":"command","command":"project ide follow"}]}]}'

with each command above ending `... * {env: {PROJECT_PLAN: $planName}} * {hooks: $follow}`,
which puts the key last in every shape.

To regenerate one fixture after a deliberate contract change: rerun the jq
command with the same inputs, replace the file, and record the reason in the
commit message. The settings tests compare the Go builder's bytes against
these files, so an accidental change fails the test.
