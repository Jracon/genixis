// Package identity resolves and applies the per-worktree git identity of a
// leg.
//
// A leg is one session on one worktree: an agent session, or the owner in
// the inverted pairing of standing principle 10. The identity of a leg is
// selectable per leg, so a leg that the owner writes commits with the owner
// as author. Every process in the worktree then commits and pushes under
// that identity, because it lives in the per-worktree git config.
//
// The profiles come from main/.claude/settings.local.json, a machine-local
// file that git never commits:
//
//	{
//	  "env": { "GIT_SSH_COMMAND": "ssh -i ~/.ssh/claude-bot -o IdentitiesOnly=yes", ... },
//	  "project": { "identity": {
//	    "owner": { "name": "Jade Meskill", "email": "jade@example" }
//	  }}
//	}
//
// The agent profile (the default) falls back to the legacy env keys
// GIT_SSH_COMMAND and GIT_AUTHOR_*/GIT_COMMITTER*, which is the identity the
// tool has always written. The owner profile falls back to the global git
// config of the user, and clears the ssh command override, so an owner leg
// pushes through the login key of the person. Any other profile name comes
// from the project.identity table only.
package identity

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"genixis/project/internal/backend"
)

// Identity is the git identity of one leg.
type Identity struct {
	// Name and Email are user.name and user.email. Empty means inherit.
	Name string
	// Email is user.email. Empty means inherit.
	Email string
	// SSHCommand is core.sshCommand, the push key of the leg. Empty means
	// the ssh config of the user applies.
	SSHCommand string
}

// Default profiles.
const (
	Agent = "agent"
	Owner = "owner"
)

type settingsFile struct {
	Env     map[string]string `json:"env"`
	Project struct {
		Identity map[string]Identity `json:"identity"`
	} `json:"project"`
}

// Resolve picks the identity of a leg. mainDir is the project's main
// checkout, whose settings.local.json holds the profiles. Unknown profile
// names are an error, so a typo never silently writes the agent identity
// into an owner leg.
func Resolve(mainDir, profile string) (Identity, error) {
	if profile == "" {
		profile = Agent
	}
	raw, err := os.ReadFile(filepath.Join(mainDir, ".claude", "settings.local.json"))
	if err != nil {
		if os.IsNotExist(err) {
			if profile == Agent || profile == Owner {
				return Identity{}, nil
			}
			return Identity{}, fmt.Errorf("no identity profile %s and no settings.local.json in main", profile)
		}
		return Identity{}, err
	}
	var file settingsFile
	if err := json.Unmarshal(raw, &file); err != nil {
		return Identity{}, fmt.Errorf("settings.local.json: %w", err)
	}
	chosen, ok := file.Project.Identity[profile]
	if ok {
		return chosen, nil
	}
	switch profile {
	case Agent:
		name := file.Env["GIT_AUTHOR_NAME"]
		if name == "" {
			name = file.Env["GIT_COMMITTER_NAME"]
		}
		email := file.Env["GIT_AUTHOR_EMAIL"]
		if email == "" {
			email = file.Env["GIT_COMMITTER_EMAIL"]
		}
		return Identity{
			Name:       name,
			Email:      email,
			SSHCommand: file.Env["GIT_SSH_COMMAND"],
		}, nil
	case Owner:
		git := backend.NewGit()
		return Identity{
			Name:  git.GlobalConfig("user.name"),
			Email: git.GlobalConfig("user.email"),
		}, nil
	}
	return Identity{}, fmt.Errorf("no identity profile %s in main/.claude/settings.local.json", profile)
}

// Apply writes the identity as the per-worktree git config of tree. It also
// applies to a worktree that already exists, so a leg can re-claim a
// worktree under another identity. Empty fields are cleared, not left from
// an earlier leg. Git then applies the identity to every process in the
// worktree, not only to the shells of a session. An empty identity writes
// nothing and leaves the repository config unchanged, as the fish
// implementation did. This function is part of the spine the owner reviews
// line by line: it rewrites repository config.
func Apply(git backend.Backend, mainDir, tree string, id Identity) error {
	if id == (Identity{}) {
		return nil
	}
	if err := git.EnableWorktreeConfig(mainDir); err != nil {
		return err
	}
	if err := setOrClearWorktree(git, tree, "core.sshCommand", id.SSHCommand); err != nil {
		return err
	}
	if err := setOrClearWorktree(git, tree, "user.name", id.Name); err != nil {
		return err
	}
	return setOrClearWorktree(git, tree, "user.email", id.Email)
}

func setOrClearWorktree(git backend.Backend, tree, key, value string) error {
	if value == "" {
		return git.ConfigUnsetWorktree(tree, key)
	}
	return git.ConfigSetWorktree(tree, key, value)
}
