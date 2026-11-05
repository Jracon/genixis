// Package ide holds the pure parts of the ide window builder: the socket
// path derivation, the layout proportions, the fish word escaping that the
// typed pane commands need, the bytes of the claude start script, and the
// @ide_* window-option writes.
//
// These are frozen consumer contracts, the way the --settings bytes are: the
// nvim socket and the start script sit beside a window for its whole life, so
// a window that an older build made must keep working, and the tmux hooks and
// the yazi openers of an older build read the same option names. The tests
// pin each part against golden fixtures that fish itself produced (see
// testdata/GENERATE.md). A change in these values is a consumer change that
// the tests must record.
package ide

import (
	"encoding/json"
	"os"
	"regexp"
	"strings"
)

// TmpDir is the temporary directory the way the fish implementation read it:
// the TMPDIR value when the variable is set, even when it is empty, and /tmp
// otherwise. On macOS TMPDIR ends in a slash, and the socket path below then
// carries a double slash, which is the frozen form.
func TmpDir() string {
	if dir, set := os.LookupEnv("TMPDIR"); set {
		return dir
	}
	return "/tmp"
}

// SocketPath derives the nvim --listen socket of an ide window from its
// editor pane. pidPane is tmux's '#{pid}-#{pane_id}' of that pane, and the %
// of the pane id goes away. The result is a plain concatenation, not a
// filepath.Join: it must not clean the double slash of a TMPDIR that ends in
// a slash.
func SocketPath(pidPane string) string {
	return TmpDir() + "/nvim-ide-" + strings.ReplaceAll(pidPane, "%", "") + ".sock"
}

var sockExt = regexp.MustCompile(`\.sock$`)

// SessionFile is the nvim session file of a socket, for the reload path: the
// socket path with .vim for .sock.
func SessionFile(sock string) string {
	return sockExt.ReplaceAllString(sock, ".vim")
}

// ClaudeScript is the fish script that starts claude in the agent pane: the
// socket path with -claude.fish for .sock.
func ClaudeScript(sock string) string {
	return sockExt.ReplaceAllString(sock, "-claude.fish")
}

// LayoutSizes proportions the three panes of an ide window to a window size:
// yazi gets 15% of the width clamped to 24 through 40 columns, claude 30%
// with at least 40, and the shell 20% of the height with at least 6 rows.
func LayoutSizes(width, height int) (filesWidth, agentWidth, shellHeight int) {
	filesWidth = clamp(width*15/100, 24, 40)
	agentWidth = atLeast(width*30/100, 40)
	shellHeight = atLeast(height*20/100, 6)
	return filesWidth, agentWidth, shellHeight
}

func clamp(v, low, high int) int {
	if v < low {
		return low
	}
	if v > high {
		return high
	}
	return v
}

func atLeast(v, low int) int {
	if v < low {
		return low
	}
	return v
}

// specials are the characters that make fish quote a word (brackets and
// braces included: a word of brackets alone still quotes).
const specials = " \\$*&;()<>~%'\"[]{}"

// FishEscape reproduces fish's `string escape --` (verified against fish
// 4.9): an empty word comes back as two single quotes; a word that needs no
// quoting comes back unchanged; a word with a special character but no
// escaped control
// character comes back quoted, single quotes preferred, double quotes only
// when the word holds a single quote and no double quote and no dollar; a
// word with an escaped control character comes back in the backslash form.
// A # is special only as the first character, and four control characters
// (0x1a and 0x1c through 0x1f) pass through raw in every form. The golden
// fixtures in testdata are fish's own output for the whole table.
func FishEscape(s string) string {
	if s == "" {
		return "''"
	}
	hasEscapedControl := false
	needsQuote := s[0] == '#'
	for _, r := range s {
		if strings.ContainsRune(specials, r) {
			needsQuote = true
		}
		if escapedControl(r) {
			needsQuote = true
			hasEscapedControl = true
		}
	}
	if !needsQuote {
		return s
	}
	if hasEscapedControl {
		var b strings.Builder
		for i, r := range s {
			switch {
			case r == 0x08:
				b.WriteString(`\b`)
			case r == '\t':
				b.WriteString(`\t`)
			case r == '\n':
				b.WriteString(`\n`)
			case r == '\r':
				b.WriteString(`\r`)
			case r == 0x1b:
				b.WriteString(`\e`)
			case r < 0x1a:
				// the caret form, with the letter that the control character
				// becomes in ASCII held lowercase: \ca for 0x01 through \cy
				// for 0x19
				b.WriteString(`\c`)
				b.WriteRune(r + 0x60)
			case r == 0x7f:
				b.WriteString(`\x7f`)
			case strings.ContainsRune(specials, r) || (i == 0 && r == '#'):
				b.WriteByte('\\')
				b.WriteRune(r)
			default:
				b.WriteRune(r)
			}
		}
		return b.String()
	}
	if strings.Contains(s, `'`) && !strings.Contains(s, `"`) && !strings.Contains(s, `$`) {
		return `"` + strings.ReplaceAll(s, `\`, `\\`) + `"`
	}
	var b strings.Builder
	b.WriteByte('\'')
	for _, r := range s {
		if r == '\\' || r == '\'' {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	b.WriteByte('\'')
	return b.String()
}

// escapedControl reports whether fish gives a control character its own
// escape sequence. The rest (0x1a and 0x1c through 0x1f) never transform.
func escapedControl(r rune) bool {
	return r < 0x1a || r == 0x1b || r == 0x7f
}

// ClaudeStartScript is the script that starts claude in the agent pane of an
// ide window: one line that removes the script itself, then the claude
// command line with each argument fish-escaped. Typed-ahead input waits in
// the tty and macOS drops what passes about 1 KiB, so a long command goes
// through this script instead of the pane input; the pane sources it with a
// leading space, which keeps the line out of the fish history.
func ClaudeStartScript(start string, args []string) []byte {
	parts := make([]string, 0, len(args)+1)
	parts = append(parts, "claude")
	for _, arg := range args {
		parts = append(parts, FishEscape(arg))
	}
	return []byte("command rm -f " + FishEscape(start) + "\n" + strings.Join(parts, " ") + "\n")
}

// ClaudePaneSource is the line that the pane sources the start script with.
func ClaudePaneSource(start string) string {
	return " source " + FishEscape(start)
}

// OptionWrites are the @ide_* window-option writes of a finished ide window,
// in emission order: the tmux argument vector of each write, on the editor
// pane, with the pane ids and paths that the tmux hooks, the yazi openers,
// and `project open` read. The plan is empty when the claude session runs no
// plan, and the yazi client id is empty outside a repository, where no
// watchdog runs (issue #128).
func OptionWrites(editor, agent, dir, files, plan, shell, sock, yazi string) [][]string {
	return [][]string{
		{"set-option", "-w", "-t", editor, "@ide_agent", agent},
		{"set-option", "-w", "-t", editor, "@ide_dir", dir},
		{"set-option", "-w", "-t", editor, "@ide_editor", editor},
		{"set-option", "-w", "-t", editor, "@ide_files", files},
		{"set-option", "-w", "-t", editor, "@ide_plan", plan},
		{"set-option", "-w", "-t", editor, "@ide_shell", shell},
		{"set-option", "-w", "-t", editor, "@ide_sock", sock},
		{"set-option", "-w", "-t", editor, "@ide_yazi", yazi},
	}
}

// ExtractPlan reads the plan name out of a --settings JSON value, the way the
// fish implementation piped it through jq: `.env.PROJECT_PLAN // empty`. A
// missing key, a non-string value, or bytes that are not JSON give no plan.
func ExtractPlan(settingsJSON string) string {
	var parsed struct {
		Env struct {
			ProjectPlan string `json:"PROJECT_PLAN"`
		} `json:"env"`
	}
	if err := json.Unmarshal([]byte(settingsJSON), &parsed); err != nil {
		return ""
	}
	return parsed.Env.ProjectPlan
}
