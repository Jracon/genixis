// Package shell quotes the words of the shell command lines that this tool
// builds: the viewer pane command, and the apiKeyHelper value inside the
// settings JSON.
//
// Quote is the POSIX single-quote form, the same bytes jq's @sh produces.
// The fish string escape is a different discipline and stays in internal/ide
// (see ide.FishEscape), because its contract is the output of fish and not
// POSIX quoting.
package shell

import "strings"

// Quote writes s for a POSIX shell command line: always single-quoted, with
// an embedded quote closed and reopened the POSIX way, the form jq's @sh
// produces. The shells of this fleet read the result as one literal word.
func Quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
