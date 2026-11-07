# Renders docs/keymap.md for the Option+K popup (tmux.nix runs this at rebuild time): the
# title, the layer sentence of the intro, and one block per table row - the layer and the
# key on one line, the action wrapped under it. The conflict-check column stays in the
# markdown; the popup drops it, and the transport notes below the intro too. No cell of
# the table holds a pipe character, so splitting on "|" is safe.

function clean(s) {
    gsub(/`/, "", s)
    gsub(/ +/, " ", s)
    gsub(/^ | $/, "", s)
    return s
}

# prints text wrapped to width 92, every continuation line indented like the first
function wrap(text, indent,   pad, line, n, i) {
    pad = sprintf("%" indent "s", "")
    line = ""
    n = split(text, words, " ")
    for (i = 1; i <= n; i++) {
        if (line == "") {
            line = words[i]
        } else if (length(line) + 1 + length(words[i]) <= 92 - indent) {
            line = line " " words[i]
        } else {
            print pad line
            line = words[i]
        }
    }
    if (line != "") {
        print pad line
    }
}

BEGIN {
    FS = "|"
}

/^# / {
    print substr($0, 3)
    print ""
    next
}

# the layer rules: the first sentence of the paragraph that opens with them
/^One modifier per layer/ {
    sub(/\..*/, ".")
    wrap($0, 0)
    print ""
    next
}

# one block per row of the table: "Layer  Key", then the wrapped action
/^\|/ {
    layer = clean($2)
    if (layer == "Layer" || layer ~ /^-/) {
        next
    }
    printf "%-6s  %s\n", layer, clean($3)
    wrap(clean($4), 8)
    print ""
    next
}

END {
    print "The full table, with the conflict check of each key, is docs/keymap.md."
}
