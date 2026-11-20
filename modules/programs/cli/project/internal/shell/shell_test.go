package shell

import "testing"

// Quote is jq's @sh form: every input comes back single-quoted, whatever it
// holds, and an embedded quote closes and reopens the quoting. The settings
// bytes and the viewer pane command pin this form end to end; this table
// pins the escaper itself.
func TestQuote(t *testing.T) {
	for _, table := range []struct{ in, want string }{
		{"", "''"},
		{"plain", "'plain'"},
		{"/nix/store/x-project-0.1.0/bin/project", "'/nix/store/x-project-0.1.0/bin/project'"},
		{"it's", `'it'\''s'`},
		{`back\slash`, `'back\slash'`},
		{"two ' quotes ' here", `'two '\'' quotes '\'' here'`},
		{"a b\"c d", `'a b"c d'`},
	} {
		if got := Quote(table.in); got != table.want {
			t.Errorf("Quote(%q) = %q, want %q", table.in, got, table.want)
		}
	}
}
