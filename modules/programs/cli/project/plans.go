package main

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"genixis/project/internal/settings"
)

// plansDir is where claude.nix writes one <name>.json per plan:
// <xdg config home>/project/plans. The xdg config home is ~/.config also on
// Darwin, which is the Home Manager convention, so os.UserConfigDir (which
// answers ~/Library/Application Support on Darwin) cannot serve here.
func plansDir() string {
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return filepath.Join(dir, "project", "plans")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join(".config", "project", "plans")
	}
	return filepath.Join(home, ".config", "project", "plans")
}

// planNames lists the plans that exist, for the unknown-plan error and the
// completion protocol.
func planNames() []string {
	entries, err := os.ReadDir(plansDir())
	if err != nil {
		return nil
	}
	var names []string
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".json") {
			names = append(names, strings.TrimSuffix(entry.Name(), ".json"))
		}
	}
	sort.Strings(names)
	return names
}

// loadPlan resolves one plan by name. It returns the plan and its name, or
// a toolError that carries the reason. A token file that cannot be read
// stops the session, because every request through the endpoint would fail.
func loadPlan(name string) (*settings.Plan, *toolError) {
	if strings.Contains(name, "/") {
		return nil, errNotFound("no plan %s; plans: %s", name, planList())
	}
	path := filepath.Join(plansDir(), name+".json")
	if info, err := os.Stat(path); err != nil || info.IsDir() {
		return nil, errNotFound("no plan %s; plans: %s", name, planList())
	}
	plan, err := settings.LoadPlanFile(path)
	if err != nil {
		return nil, wrapGeneral(err)
	}
	if plan.TokenFile == "" {
		return nil, errGeneral("plan %s names no token file", name)
	}
	if info, err := os.Stat(plan.TokenFile); err != nil || info.IsDir() {
		return nil, errGeneral("plan %s can't read its token file %s (is its agenix secret decrypted?)", name, plan.TokenFile)
	}
	return &plan, nil
}

func planList() string {
	names := planNames()
	if len(names) == 0 {
		return "none"
	}
	return strings.Join(names, ", ")
}
