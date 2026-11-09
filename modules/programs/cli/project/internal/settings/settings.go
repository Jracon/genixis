// Package settings builds the --settings JSON that starts a Claude Code
// session for `project open` and `project spawn`.
//
// The bytes are a frozen consumer contract: the forge hook, the ide window
// builder, and spawned sessions read the markers in the env object
// (PROJECT_SPAWN_SESSION, PROJECT_HEADLESS_SESSION, PROJECT_PLAN), so the
// output must stay byte-for-byte what the former fish implementation
// produced with jq. The hooks key (issue #190) is the one part that the fish
// implementation never wrote; testdata/GENERATE.md gives its jq form. The
// tests pin the bytes against golden fixtures that jq itself generated (see
// testdata/GENERATE.md). Never switch to a struct marshaller here: Go sorts
// map keys, and the key order is part of the contract only by accident of
// jq, but the bytes are what the tests froze, and a byte change is a
// contract change that the tests must record.
package settings

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// EnvPair is one environment entry of a settings env object, in order.
type EnvPair struct {
	Key   string
	Value string
}

// Plan is one plan file of ~/.config/project/plans, as claude.nix writes it:
// an env object and a token file. Env preserves the file's key order.
type Plan struct {
	Env       []EnvPair
	TokenFile string
}

// LoadPlanFile reads one plan file. It keeps the env keys in file order,
// which the frozen byte shape needs.
func LoadPlanFile(path string) (Plan, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return Plan{}, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	tok, err := dec.Token()
	if err != nil {
		return Plan{}, fmt.Errorf("%s: %w", path, err)
	}
	if delim, ok := tok.(json.Delim); !ok || delim != '{' {
		return Plan{}, fmt.Errorf("%s: not a JSON object", path)
	}
	var plan Plan
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return Plan{}, fmt.Errorf("%s: %w", path, err)
		}
		key, _ := tok.(string)
		switch key {
		case "env":
			tok, err := dec.Token()
			if err != nil {
				return Plan{}, fmt.Errorf("%s: env: %w", path, err)
			}
			if delim, ok := tok.(json.Delim); !ok || delim != '{' {
				return Plan{}, fmt.Errorf("%s: env is not an object", path)
			}
			for dec.More() {
				tok, err := dec.Token()
				if err != nil {
					return Plan{}, fmt.Errorf("%s: env: %w", path, err)
				}
				envKey, _ := tok.(string)
				var value json.RawMessage
				if err := dec.Decode(&value); err != nil {
					return Plan{}, fmt.Errorf("%s: env.%s: %w", path, envKey, err)
				}
				var str string
				if err := json.Unmarshal(value, &str); err != nil {
					return Plan{}, fmt.Errorf("%s: env.%s is not a string", path, envKey)
				}
				plan.Env = append(plan.Env, EnvPair{Key: envKey, Value: str})
			}
			if _, err := dec.Token(); err != nil { // closing brace of env
				return Plan{}, fmt.Errorf("%s: env: %w", path, err)
			}
		case "tokenFile":
			if err := dec.Decode(&plan.TokenFile); err != nil {
				return Plan{}, fmt.Errorf("%s: tokenFile: %w", path, err)
			}
		default:
			if err := dec.Decode(new(json.RawMessage)); err != nil {
				return Plan{}, fmt.Errorf("%s: %s: %w", path, key, err)
			}
		}
	}
	return plan, nil
}

// Settings describes one session start. Permissions is nil for `project
// open`, which passes no permission block.
type Settings struct {
	// MemoryDir is <project>/.claude/memory, the autoMemoryDirectory value.
	MemoryDir string
	// Permissions, when set, adds the per-worktree read rules and the
	// main/.git deny rules of a spawn.
	Permissions *Permissions
	// Plan, when set, merges the plan's env and apiKeyHelper.
	Plan *Plan
	// Markers are the session marker entries, in emission order: windowed
	// spawn passes PROJECT_SPAWN_SESSION only, headless spawn passes
	// PROJECT_HEADLESS_SESSION then PROJECT_SPAWN_SESSION.
	Markers []EnvPair
	// PlanName names the plan in PROJECT_PLAN; the empty string means none.
	PlanName string
}

// Permissions is the permissions object of a spawn settings file.
type Permissions struct {
	// Reads are the paths the session may read: the git metadata of its own
	// worktree first, then every entry of main/.git except worktrees, in
	// list order.
	Reads []string
	// GitDir is main/.git, for the exact ls allow rule and the deny rules.
	GitDir string
}

// followHook is the hooks object that every settings file carries since issue
// #190: one PostToolUse hook on the tools that write files, which runs
// `project ide follow`. The verb reads the tool input from stdin and makes
// the nvim pane of the ide window of the working directory follow the file
// that the session wrote. When no ide window holds the directory, the verb
// exits 0 at once, so a session outside a window never sees a failure of the
// follow.
const followHook = `,"hooks":{"PostToolUse":[{"matcher":"Write|Edit|NotebookEdit","hooks":[{"type":"command","command":"project ide follow"}]}]}`

// Build renders the settings as the frozen bytes, without a trailing
// newline, exactly as the fish implementation's jq pipeline did.
func Build(s Settings) []byte {
	var b bytes.Buffer
	b.WriteString(`{"autoMemoryDirectory":"`)
	writeEscaped(&b, s.MemoryDir)
	b.WriteByte('"')
	if s.Permissions != nil {
		b.WriteString(`,"permissions":{"allow":[`)
		for i, read := range s.Permissions.Reads {
			if i > 0 {
				b.WriteByte(',')
			}
			// each rule is one JSON string: Read(, the path, and ) or
			// /**), with the leading / of an absolute path making the
			// double slash of a session rule
			b.WriteString(`"Read(/`)
			writeEscaped(&b, read)
			b.WriteString(`)","Read(/`)
			writeEscaped(&b, read)
			b.WriteString(`/**)"`)
		}
		b.WriteString(`,"Bash(ls `)
		writeEscaped(&b, s.Permissions.GitDir)
		b.WriteString(`)"],"deny":["Edit(/`)
		writeEscaped(&b, s.Permissions.GitDir)
		b.WriteString(`)","Edit(/`)
		writeEscaped(&b, s.Permissions.GitDir)
		b.WriteString(`/**)"]}`)
	}
	// env: the plan's keys first (file order), then the markers, then
	// PROJECT_PLAN last; a repeated key keeps its first position and takes
	// the later value, which is jq's deep-merge order
	env := orderedMerge(s.Plan, s.Markers, s.PlanName)
	b.WriteString(`,"env":{`)
	for i, pair := range env {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteByte('"')
		writeEscaped(&b, pair.Key)
		b.WriteString(`":"`)
		writeEscaped(&b, pair.Value)
		b.WriteByte('"')
	}
	b.WriteString(`}`)
	if s.Plan != nil {
		// apiKeyHelper cats the token file, so the token is in no settings
		// value and on no command line; Claude Code caches the helper result
		// (five minutes by default, re-run on expiry or auth failure), so a
		// rotated token reaches a running session only then; @sh
		// single-quotes the path
		b.WriteString(`,"apiKeyHelper":"cat `)
		writeShQuoted(&b, s.Plan.TokenFile)
		b.WriteByte('"')
	}
	b.WriteString(followHook)
	b.WriteString(`}`)
	return b.Bytes()
}

func orderedMerge(plan *Plan, markers []EnvPair, planName string) []EnvPair {
	var env []EnvPair
	set := func(key, value string) {
		for i := range env {
			if env[i].Key == key {
				env[i].Value = value
				return
			}
		}
		env = append(env, EnvPair{Key: key, Value: value})
	}
	if plan != nil {
		for _, pair := range plan.Env {
			set(pair.Key, pair.Value)
		}
	}
	for _, pair := range markers {
		set(pair.Key, pair.Value)
	}
	set("PROJECT_PLAN", planName)
	return env
}

// writeEscaped writes the content of a JSON string with jq's escaping: only
// the mandatory escapes, no HTML escapes, UTF-8 raw. The string delimiters
// belong to the caller, because the frozen bytes embed paths inside larger
// strings (Read(//<path>)). Go's encoder would escape <, >, & and sort map
// keys, so this is hand-rolled to match the frozen bytes.
func writeEscaped(b *bytes.Buffer, s string) {
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r < 0x20 {
				fmt.Fprintf(b, `\u%04x`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
}

// writeShQuoted writes s in jq's @sh form: always single-quoted, with an
// embedded quote closed and reopened the POSIX way.
func writeShQuoted(b *bytes.Buffer, s string) {
	b.WriteByte('\'')
	b.WriteString(strings.ReplaceAll(s, `'`, `'\''`))
	b.WriteByte('\'')
}

// DiscoverReads lists the paths a spawned session may read: the git metadata
// of its own worktree first, then every entry of main/.git except worktrees,
// in directory order. The entries are captured when the session starts, so
// one that git makes later still prompts.
func DiscoverReads(treeGitDir, mainGitDir string) []string {
	entries, err := os.ReadDir(mainGitDir)
	if err != nil {
		return []string{treeGitDir}
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.Name() == "worktrees" {
			continue
		}
		names = append(names, entry.Name())
	}
	sort.Strings(names)
	reads := make([]string, 0, len(names)+1)
	reads = append(reads, treeGitDir)
	for _, name := range names {
		reads = append(reads, filepath.Join(mainGitDir, name))
	}
	return reads
}

// SpawnMarkers are the marker entries of a spawn session: windowed passes
// the spawn marker only, headless passes the headless marker first and the
// spawn marker beside it, in the frozen order.
func SpawnMarkers(headless bool) []EnvPair {
	if headless {
		return []EnvPair{
			{Key: "PROJECT_HEADLESS_SESSION", Value: "1"},
			{Key: "PROJECT_SPAWN_SESSION", Value: "1"},
		}
	}
	return []EnvPair{{Key: "PROJECT_SPAWN_SESSION", Value: "1"}}
}
