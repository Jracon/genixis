package settings

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

const (
	fixtureDir    = "/home/dev/proj"
	fixtureMain   = "/home/dev/proj/main"
	fixtureTree   = "/home/dev/proj/feat-x"
	fixtureGitDir = "/home/dev/proj/main/.git/worktrees/feat-x"
)

var fixtureReads = []string{
	fixtureGitDir,
	fixtureMain + "/.git/HEAD",
	fixtureMain + "/.git/config",
	fixtureMain + "/.git/description",
	fixtureMain + "/.git/hooks",
	fixtureMain + "/.git/info",
	fixtureMain + "/.git/objects",
	fixtureMain + "/.git/packed-refs",
	fixtureMain + "/.git/refs",
}

var zaiPlan = &Plan{
	Env: []EnvPair{
		{Key: "ANTHROPIC_BASE_URL", Value: "https://api.z.ai/api/anthropic"},
		{Key: "ANTHROPIC_DEFAULT_HAIKU_MODEL", Value: "glm-4.6"},
		{Key: "ANTHROPIC_DEFAULT_OPUS_MODEL", Value: "glm-4.6"},
		{Key: "ANTHROPIC_DEFAULT_SONNET_MODEL", Value: "glm-4.6"},
	},
	TokenFile: "/run/agenix/zai_token",
}

func golden(t *testing.T, name string) []byte {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read golden fixture: %v", err)
	}
	return bytes.TrimRight(raw, "\n")
}

func windowed() []EnvPair { return SpawnMarkers(false) }
func headless() []EnvPair { return SpawnMarkers(true) }

// The four spawn shapes and the two open shapes, byte for byte.
func TestBuildMatchesFrozenBytes(t *testing.T) {
	cases := []struct {
		name string
		in   Settings
	}{
		{"open.json", Settings{MemoryDir: fixtureDir + "/.claude/memory", PlanName: ""}},
		{"open-plan.json", Settings{MemoryDir: fixtureDir + "/.claude/memory", Plan: zaiPlan, PlanName: "zai"}},
		{"spawn-windowed.json", Settings{
			MemoryDir:   fixtureDir + "/.claude/memory",
			Permissions: &Permissions{Reads: fixtureReads, GitDir: fixtureMain + "/.git"},
			Markers:     windowed(),
			PlanName:    "",
		}},
		{"spawn-headless.json", Settings{
			MemoryDir:   fixtureDir + "/.claude/memory",
			Permissions: &Permissions{Reads: fixtureReads, GitDir: fixtureMain + "/.git"},
			Markers:     headless(),
			PlanName:    "",
		}},
		{"spawn-windowed-plan.json", Settings{
			MemoryDir:   fixtureDir + "/.claude/memory",
			Permissions: &Permissions{Reads: fixtureReads, GitDir: fixtureMain + "/.git"},
			Plan:        zaiPlan,
			Markers:     windowed(),
			PlanName:    "zai",
		}},
		{"spawn-headless-plan.json", Settings{
			MemoryDir:   fixtureDir + "/.claude/memory",
			Permissions: &Permissions{Reads: fixtureReads, GitDir: fixtureMain + "/.git"},
			Plan:        zaiPlan,
			Markers:     headless(),
			PlanName:    "zai",
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Build(tc.in)
			want := golden(t, tc.name)
			if !bytes.Equal(got, want) {
				t.Errorf("settings bytes drifted from the frozen contract\n got: %s\nwant: %s", got, want)
			}
		})
	}
}

// The marker order is part of the frozen bytes: headless first, spawn beside
// it, plan name last.
func TestMarkerOrder(t *testing.T) {
	markers := headless()
	if len(markers) != 2 || markers[0].Key != "PROJECT_HEADLESS_SESSION" || markers[1].Key != "PROJECT_SPAWN_SESSION" {
		t.Errorf("headless markers out of order: %v", markers)
	}
	markers = windowed()
	if len(markers) != 1 || markers[0].Key != "PROJECT_SPAWN_SESSION" {
		t.Errorf("windowed markers wrong: %v", markers)
	}
}

// A path with jq-relevant characters must come out exactly as jq writes it.
func TestJqStringEscapes(t *testing.T) {
	got := Build(Settings{MemoryDir: "a\tb\nc<d>e&f\"ü\\g", PlanName: ""})
	want := `{"autoMemoryDirectory":"a\tb\nc<d>e&f\"ü\\g","env":{"PROJECT_PLAN":""}}`
	if string(got) != want {
		t.Errorf("escaping drift\n got: %s\nwant: %s", got, want)
	}
}

// @sh always single-quotes and escapes an embedded quote the POSIX way.
func TestShQuoting(t *testing.T) {
	plan := &Plan{TokenFile: "/run/it's token"}
	got := Build(Settings{MemoryDir: "/m", Plan: plan, PlanName: ""})
	want := `{"autoMemoryDirectory":"/m","env":{"PROJECT_PLAN":""},"apiKeyHelper":"cat '/run/it'\''s token'"}`
	if string(got) != want {
		t.Errorf("@sh drift\n got: %s\nwant: %s", got, want)
	}
}

// A plan env key that repeats a marker keeps its first position and takes
// the marker's value, which is jq's deep-merge behaviour.
func TestRepeatedEnvKeyTakesLaterValueInPlace(t *testing.T) {
	plan := &Plan{
		Env: []EnvPair{
			{Key: "PROJECT_PLAN", Value: "stale"},
			{Key: "A", Value: "1"},
		},
		TokenFile: "/run/tok",
	}
	got := Build(Settings{MemoryDir: "/m", Plan: plan, PlanName: "zai"})
	want := `{"autoMemoryDirectory":"/m","env":{"PROJECT_PLAN":"zai","A":"1"},"apiKeyHelper":"cat '/run/tok'"}`
	if string(got) != want {
		t.Errorf("merge drift\n got: %s\nwant: %s", got, want)
	}
}

// DiscoverReads puts the worktree's own git dir first and skips worktrees/.
func TestDiscoverReads(t *testing.T) {
	main := t.TempDir()
	for _, name := range []string{"HEAD", "refs", "objects", "worktrees", "config"} {
		if err := os.MkdirAll(filepath.Join(main, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	reads := DiscoverReads(filepath.Join(main, "worktrees", "feat-x"), main)
	want := []string{
		filepath.Join(main, "worktrees", "feat-x"),
		filepath.Join(main, "HEAD"),
		filepath.Join(main, "config"),
		filepath.Join(main, "objects"),
		filepath.Join(main, "refs"),
	}
	if len(reads) != len(want) {
		t.Fatalf("got %d reads, want %d: %v", len(reads), len(want), reads)
	}
	for i := range want {
		if reads[i] != want[i] {
			t.Errorf("reads[%d] = %s, want %s", i, reads[i], want[i])
		}
	}
}

// A plan file keeps its env key order through LoadPlanFile.
func TestLoadPlanFileKeepsOrder(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "zai.json")
	body := `{"env":{"B":"2","A":"1"},"tokenFile":"/run/tok"}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	plan, err := LoadPlanFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if plan.TokenFile != "/run/tok" || len(plan.Env) != 2 || plan.Env[0].Key != "B" || plan.Env[1].Key != "A" {
		t.Errorf("plan = %+v", plan)
	}
}
