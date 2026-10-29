{
  config,
  lib,
  pkgs,
  ...
}:

let
  # merged into ~/.claude/settings.json on each switch: routine read-only commands and local git writes
  # that every project needs, and actions that no agent may take; projects add their own build, push
  # and forge rules
  permissions = pkgs.writeText "claude-permissions.json" (
    builtins.toJSON {
      allow = [
        "Bash(ast-grep run *)"
        "Bash(fd *)"
        "Bash(fd)"
        "Bash(gh issue list*)"
        "Bash(gh issue view *)"
        "Bash(gh pr checks *)"
        "Bash(gh pr diff *)"
        "Bash(gh pr list*)"
        "Bash(gh pr view *)"
        "Bash(git add *)"
        "Bash(git branch --list*)"
        "Bash(git branch --show-current)"
        "Bash(git commit *)"
        "Bash(git diff*)"
        "Bash(git fetch*)"
        "Bash(git log*)"
        "Bash(git ls-files*)"
        "Bash(git merge --no-ff *)"
        "Bash(git merge-base *)"
        "Bash(git mv *)"
        "Bash(git rev-parse *)"
        "Bash(git show*)"
        "Bash(git status*)"
        "Bash(git switch *)"
        "Bash(git worktree list)"
        "Bash(jq *)"
        "Bash(project add *)"
        "Bash(project clean*)"
        "Bash(project close*)"
        "Bash(project spawn *)"
        "Bash(qmd collection list)"
        "Bash(qmd get *)"
        "Bash(qmd query *)"
        "Bash(qmd search *)"
        "Bash(rg *)"
        "Bash(semble find-related *)"
        "Bash(semble search *)"
        "Bash(tea comments list*)"
        "Bash(tea comments ls*)"
        "Bash(tea issues create --repo jracon/genixis *)"
        "Bash(tea issues list*)"
        "Bash(tea pulls list*)"
      ];
      deny = [
        # these flags make an allowed search tool run other programs or write files; --exec* also
        # covers fd --exec-batch, and --custom-languages allow|trust loads native libraries
        "Bash(ast-grep * --custom-languages*)"
        "Bash(ast-grep * --interactive*)"
        "Bash(ast-grep * --update-all*)"
        "Bash(ast-grep * -i*)"
        "Bash(ast-grep * -U*)"
        "Bash(fd * --exec*)"
        "Bash(fd * -X *)"
        "Bash(fd * -x *)"
        "Bash(fd --exec*)"
        "Bash(fd -X *)"
        "Bash(fd -x *)"
        "Bash(rg * --pre*)"
        "Bash(rg --pre*)"

        "Bash(gh pr merge*)"
        "Bash(git commit * --no-verify*)"
        "Bash(git commit * -n *)"
        "Bash(git commit --no-verify*)"
        "Bash(git commit -n *)"
        "Bash(git push * --force*)"
        "Bash(git push * --mirror*)"
        "Bash(git push * --no-verify*)"
        "Bash(git push * -f*)"
        "Bash(git push --force*)"
        "Bash(git push --mirror*)"
        "Bash(git push --no-verify*)"
        "Bash(git push -f*)"
        "Bash(project discard*)"
        "Bash(tea pr merge*)"
        "Bash(tea pull merge*)"
        "Bash(tea pulls merge*)"
        "Edit(**/.env)"
        "Read(**/.env)"
      ];
    }
  );

  tools = lib.mapAttrsToList (
    name: tool: "- `${name}`: ${tool.description}"
  ) config.genixis.claude.tools;
in
{
  # user-level Claude Code context: it tells agents in any project about the tools of this machine
  config.home = {
    # Claude Code rewrites settings.json itself (for example on "always allow"), so the file stays mutable: each
    # switch adds the rules above and removes only the rules that the previous switch added and Nix no longer lists
    activation.claudePermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.claude/settings.json"
      state="$HOME/.claude/.genixis-permissions.json"
      run mkdir -p "$HOME/.claude"
      [ -f "$settings" ] || run sh -c 'echo "{}" > "$1"' sh "$settings"
      [ -f "$state" ] || run sh -c 'echo "{\"allow\": [], \"deny\": []}" > "$1"' sh "$state"
      if [ -z "''${DRY_RUN:-}" ]; then
        merged="$(${lib.getExe pkgs.jq} \
          --slurpfile new ${permissions} \
          --slurpfile old "$state" \
          'reduce ("allow", "deny") as $k (.;
            .permissions[$k] = (((.permissions[$k] // []) - $old[0][$k]) + $new[0][$k] | unique))' \
          "$settings")"
        printf '%s\n' "$merged" > "$settings"
        cp ${permissions} "$state"
        chmod u+w "$state"
      fi
    '';

    file = {
      ".claude/CLAUDE.md".text = ''
        ${lib.removeSuffix "\n" (builtins.readFile ./claude/CLAUDE.md)}

        # Installed tools

        Prefer these to the older equivalents.

        ${lib.concatStringsSep "\n" tools}
      '';
      ".claude/skills/asd-ste100/SKILL.md".source = ./claude/skills/asd-ste100/SKILL.md;
      ".claude/skills/project/SKILL.md".source = ./claude/skills/project/SKILL.md;
      ".claude/skills/rewrite-fidelity/SKILL.md".source = ./claude/skills/rewrite-fidelity/SKILL.md;
    };

    # no automatic session recaps; the variable beats awaySummaryEnabled in every settings file and /config,
    # and unlike ~/.claude/settings.json (which Claude Code rewrites itself) it can be declared here
    sessionVariables.CLAUDE_CODE_ENABLE_AWAY_SUMMARY = "0";

    packages = lib.concatMap (tool: lib.optional (tool.package != null) tool.package) (
      lib.attrValues config.genixis.claude.tools
    );
  };

  # modules that install a general-purpose tool declare it here, next to the install, so the list in
  # ~/.claude/CLAUDE.md always matches what is installed
  options.genixis.claude.tools = lib.mkOption {
    default = { };
    description = "General-purpose tools to document for agents, by command name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            description = "One line for ~/.claude/CLAUDE.md: what the tool does and which tool it replaces. Write it from the documentation of the tool (its --help), not from memory.";
            type = lib.types.str;
          };

          package = lib.mkOption {
            default = null;
            description = "A package to install. Leave it null when a programs.<name> module installs the tool.";
            type = lib.types.nullOr lib.types.package;
          };
        };
      }
    );
  };
}
