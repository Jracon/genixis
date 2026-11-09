package identity

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"genixis/project/internal/backend"
)

func newProject(t *testing.T) (main, tree string, git *backend.Git) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not available")
	}
	// the build sandbox has no user identity, and git refuses to commit
	// with the auto-detected one on linux, so the tests name one
	t.Setenv("GIT_AUTHOR_NAME", "test")
	t.Setenv("GIT_AUTHOR_EMAIL", "test@example")
	t.Setenv("GIT_COMMITTER_NAME", "test")
	t.Setenv("GIT_COMMITTER_EMAIL", "test@example")
	dir := t.TempDir()
	main = filepath.Join(dir, "main")
	if err := os.MkdirAll(main, 0o755); err != nil {
		t.Fatal(err)
	}
	git = backend.NewGit()
	for _, args := range [][]string{
		{"init", "--quiet", "--initial-branch", "main"},
		{"commit", "--quiet", "--allow-empty", "--message", "initial"},
	} {
		cmd := exec.Command("git", args...)
		cmd.Dir = main
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v: %s", args, err, out)
		}
	}
	tree = filepath.Join(dir, "feat-x")
	if err := git.AddWorktree(main, tree, "feat-x", backend.AddNew, "main"); err != nil {
		t.Fatal(err)
	}
	return main, tree, git
}

func writeSettings(t *testing.T, main, body string) {
	t.Helper()
	path := filepath.Join(main, ".claude", "settings.local.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// The agent profile is the legacy env block of settings.local.json.
func TestAgentProfileFromLegacyEnv(t *testing.T) {
	main, tree, git := newProject(t)
	writeSettings(t, main, `{
		"env": {
			"GIT_SSH_COMMAND": "ssh -i ~/.ssh/claude-bot -o IdentitiesOnly=yes",
			"GIT_AUTHOR_NAME": "claude-bot",
			"GIT_AUTHOR_EMAIL": "claude-bot@users.noreply"
		},
		"project": {
			"identity": {
				"owner": { "name": "Jade Meskill", "email": "jade@example" }
			}
		}
	}`)
	id, err := Resolve(main, Agent)
	if err != nil {
		t.Fatal(err)
	}
	if id.Name != "claude-bot" || id.Email != "claude-bot@users.noreply" || id.SSHCommand == "" {
		t.Fatalf("agent identity = %+v", id)
	}
	if err := Apply(git, main, tree, id); err != nil {
		t.Fatal(err)
	}
	if got := git.ConfigGet(tree, "user.name"); got != "claude-bot" {
		t.Errorf("worktree user.name = %q", got)
	}

	// an owner leg re-claims the same worktree: the agent values are gone
	owner, err := Resolve(main, Owner)
	if err != nil {
		t.Fatal(err)
	}
	if owner.Name != "Jade Meskill" {
		t.Fatalf("owner identity = %+v", owner)
	}
	if err := Apply(git, main, tree, owner); err != nil {
		t.Fatal(err)
	}
	if got := git.ConfigGet(tree, "user.name"); got != "Jade Meskill" {
		t.Errorf("worktree user.name after owner leg = %q", got)
	}
	if got := git.ConfigGet(tree, "core.sshCommand"); got != "" {
		t.Errorf("the agent push key survived the owner leg: %q", got)
	}
	// main keeps its own identity
	if got := git.ConfigGet(main, "user.name"); got == "Jade Meskill" {
		t.Error("owner identity leaked into main")
	}
}

// A missing settings file means no identity: nothing is written, not even
// the per-worktree config setup.
func TestMissingSettingsWritesNothing(t *testing.T) {
	main, tree, git := newProject(t)
	// git reads the global and system config of the machine beyond the local
	// one: point both at an empty file, or the user.name of this machine
	// answers the read and the test sees a write that none made
	empty := filepath.Join(t.TempDir(), "empty")
	if err := os.WriteFile(empty, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", empty)
	t.Setenv("GIT_CONFIG_SYSTEM", empty)
	id, err := Resolve(main, Agent)
	if err != nil || id != (Identity{}) {
		t.Fatalf("identity = %+v, %v", id, err)
	}
	if err := Apply(git, main, tree, id); err != nil {
		t.Fatal(err)
	}
	if got := git.ConfigGet(tree, "user.name"); got != "" {
		t.Errorf("an empty identity must write nothing, got %q", got)
	}
	if git.WorktreeConfigEnabled(main) {
		t.Error("an empty identity must leave the repository config unchanged")
	}
}

// An unknown profile name is an error, never a silent agent identity.
func TestUnknownProfileIsAnError(t *testing.T) {
	main, _, _ := newProject(t)
	writeSettings(t, main, `{"env": {}}`)
	if _, err := Resolve(main, "reviwer"); err == nil {
		t.Fatal("a typo in a profile name must fail")
	}
}
