# Regenerates the golden fixtures next to this script. Run it from anywhere:
#
#     fish <repo>/modules/programs/cli/project/internal/ide/testdata/generate.fish
#
# with fish 4.x and jq on PATH. The case list below is the contract: a new
# case changes escape-cases.json and escape-golden.txt together, and the Go
# test walks them in order. Record the reason for a deliberate change in the
# commit message; an accidental change fails the test.

set here (path resolve (path dirname (status filename)))

set cases \
    plain/path \
    /var/folders/5w/l20byfk56ql0pzm2klvb9xjr0000gn/T//nvim-ide-96324-80.sock \
    /var/folders/5w/l20byfk56ql0pzm2klvb9xjr0000gn/T//nvim-ide-96324-80-claude.fish \
    /var/folders/5w/l20byfk56ql0pzm2klvb9xjr0000gn/T//nvim-ide-96324-80.vim \
    /home/dev/my\ file.md \
    '#hash' \
    'a#b' \
    'x #y' \
    'a$b' \
    'sp ace' \
    'a(b)c&d;e' \
    'a|b<c>d' \
    'a~b*c' \
    'a?b!c' \
    'a=b,c:d@e' \
    'a[b]{c}' \
    'a}b]c' \
    'a[b c' \
    'a}b c' \
    'a?b c' \
    'a#b c' \
    'it\'s' \
    'a"b' \
    'a\'b$c' \
    'bo\'th"and' \
    'a\'b\\c' \
    'a\b' \
    'a\\\\b' \
    '%42' \
    é日 \
    --settings \
    --continue \
    --permission-mode \
    acceptEdits \
    nvim \
    --listen \
    -S \
    -c \
    'call delete(v:this_session)' \
    '{"autoMemoryDirectory":"/home/dev/proj/.claude/memory","permissions":{"allow":["Read(//home/dev/proj/main/.git/worktrees/feat-x)","Read(//home/dev/proj/main/.git/worktrees/feat-x/**)","Bash(ls /home/dev/proj/main/.git)"],"deny":["Edit(//home/dev/proj/main/.git)","Edit(//home/dev/proj/main/.git/**)"]},"env":{"PROJECT_SPAWN_SESSION":"1","PROJECT_PLAN":""}}' \
    '{"autoMemoryDirectory":"/home/dev/proj/.claude/memory","env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic","PROJECT_PLAN":"zai"},"apiKeyHelper":"cat \'/run/agenix/zai_token\'"}' \
    'do the work on issue 74 (it\'s "phase 3")' \
    (printf 'a\tb' | string collect) \
    (printf 'a\tb c' | string collect) \
    (printf 'a\nb' | string collect) \
    (printf 'a b\nc' | string collect) \
    (printf 'a\'b\nb' | string collect) \
    (printf 'a\rb' | string collect) \
    (printf 'a\x01b c' | string collect) \
    (printf 'a\x07b' | string collect) \
    (printf 'a\x08b' | string collect) \
    (printf 'a\x0bb' | string collect) \
    (printf 'a\x0cb' | string collect) \
    (printf 'a\x19b' | string collect) \
    (printf 'a\x1bb' | string collect) \
    (printf 'a\x1ab' | string collect) \
    (printf 'a\x1ab c' | string collect) \
    (printf 'a\x1fb' | string collect) \
    (printf 'a\x1fb c' | string collect) \
    (printf 'a\x7fb' | string collect) \
    (printf 'a\x7fb c' | string collect) \
    (printf '\xc3\xa9\n\xe6\x97\xa5' | string collect) \
    ''

jq -cn '$ARGS.positional' --args -- $cases >$here/escape-cases.json

for c in $cases
    string escape -- $c
end >$here/escape-golden.txt

# The claude start script of an agent pane, from the fish implementation of
# __ide_claude before the Go rewrite, for one fixed socket and command line.
set sock /var/folders/5w/l20byfk56ql0pzm2klvb9xjr0000gn/T//nvim-ide-96324-80.sock
set claude_args --continue --settings '{"autoMemoryDirectory":"/home/dev/proj/.claude/memory","env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic","PROJECT_PLAN":"zai"},"apiKeyHelper":"cat \'/run/agenix/zai_token\'"}' --permission-mode acceptEdits -- 'do the work on issue 74 (it\'s "phase 3")'
set start (string replace --regex -- '\.sock$' -claude.fish $sock)
printf '%s\n' "command rm -f $(string escape -- $start)" (string join -- " " claude (string escape -- $claude_args)) >$here/claude-start.txt
