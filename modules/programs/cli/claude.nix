{
  config,
  lib,
  pkgs,
  ...
}:

let
  # merged into ~/.claude/settings.json on each switch: routine read-only commands and local git writes
  # that every project needs, actions that no agent may take, and the forge hook; projects add their own
  # build, push and forge rules
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

        # these run any code; with --impure, an expression also reads any file and uses the network
        "Bash(direnv exec *)"
        "Bash(nix eval *--apply*)"
        "Bash(nix eval *--expr*)"
        "Bash(nix repl*)"

        "Bash(gh pr merge*)"
        "Bash(git -C *)"
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
        "Edit(**/.env)"
        "Read(**/.env)"
      ];

      # the hook answers allow, deny, or ask for tea, gh, and git push commands, by the working repository
      hooks.PreToolUse = [
        {
          hooks = [
            {
              command = "${lib.getExe pkgs.python3} ${./claude/forge-hook.py}";
              type = "command";
            }
          ];
          matcher = "Bash";
        }
      ];
    }
  );

  tools = lib.mapAttrsToList (
    name: tool: "- `${name}`: ${tool.description}"
  ) config.genixis.claude.tools;
in
{
  config = {
    # the token of a plan is an agenix secret of the user, decrypted with the ~/.ssh/genixis_secrets that every
    # user already has (see ssh.nix); a secret that agenix can't decrypt fails every secret of the user, so the
    # plan is on for every user exactly when the encrypted token is committed (`agenix -e` creates the file)
    age.secrets = lib.mkIf (builtins.pathExists ./claude/zai_token.age) {
      zai_token = {
        file = ./claude/zai_token.age;
        path = "${config.xdg.configHome}/project/plans/zai.token";
      };
    };

    genixis.claude.plans = lib.mkIf (builtins.pathExists ./claude/zai_token.age) {
      # the models of the manual setup on https://docs.z.ai/devpack/tool/claude, with its 1M-token context
      zai = {
        baseUrl = "https://api.z.ai/api/anthropic";
        extraEnv = {
          API_TIMEOUT_MS = "3000000";
          CLAUDE_CODE_AUTO_COMPACT_WINDOW = "1000000";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        };
        models = {
          haiku = "glm-5.3-flash[1m]";
          opus = "glm-5.3[1m]";
          sonnet = "glm-5.3[1m]";
        };
        tokenFile = config.age.secrets.zai_token.path;
      };
    };

    # user-level Claude Code context: it tells agents in any project about the tools of this machine
    home = {
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
              .permissions[$k] = (((.permissions[$k] // []) - $old[0][$k]) + $new[0][$k] | unique))
             | .hooks.PreToolUse = (
                 ((.hooks.PreToolUse // []) - ($old[0].hooks.PreToolUse // [])) + $new[0].hooks.PreToolUse | unique)' \
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
        ".claude/skills/forgejo/SKILL.md".source = ./claude/skills/forgejo/SKILL.md;
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

    # `project open|spawn --plan <name>` reads these; the token stays in its file, and Claude Code reads it
    # through apiKeyHelper, so it never shows in a settings value or on a command line
    xdg.configFile = lib.mapAttrs' (
      name: plan:
      lib.nameValuePair "project/plans/${name}.json" {
        text = builtins.toJSON {
          env = {
            ANTHROPIC_BASE_URL = plan.baseUrl;
            ANTHROPIC_DEFAULT_HAIKU_MODEL = plan.models.haiku;
            ANTHROPIC_DEFAULT_OPUS_MODEL = plan.models.opus;
            ANTHROPIC_DEFAULT_SONNET_MODEL = plan.models.sonnet;
          }
          // plan.extraEnv;
          inherit (plan) tokenFile;
        };
      }
    ) config.genixis.claude.plans;
  };

  options.genixis.claude = {
    plans = lib.mkOption {
      default = { };
      description = "Anthropic-compatible endpoints that `project open --plan <name>` and `project spawn --plan <name>` start a Claude Code session against, by plan name. With a plan, the prompts and the code of the session go to the third party that runs the endpoint, not to Anthropic.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            baseUrl = lib.mkOption {
              description = "The endpoint, as ANTHROPIC_BASE_URL.";
              type = lib.types.str;
            };

            extraEnv = lib.mkOption {
              default = { };
              description = "More environment variables for the session. Never put a token here: the file is in the Nix store.";
              type = lib.types.attrsOf lib.types.str;
            };

            models = {
              haiku = lib.mkOption {
                description = "The model for the haiku tier, as ANTHROPIC_DEFAULT_HAIKU_MODEL.";
                type = lib.types.str;
              };

              opus = lib.mkOption {
                description = "The model for the opus tier, as ANTHROPIC_DEFAULT_OPUS_MODEL.";
                type = lib.types.str;
              };

              sonnet = lib.mkOption {
                description = "The model for the sonnet tier, as ANTHROPIC_DEFAULT_SONNET_MODEL.";
                type = lib.types.str;
              };
            };

            tokenFile = lib.mkOption {
              description = "The path of a file that holds the token of the endpoint, for example an agenix secret. It is read when the session sends a request.";
              type = lib.types.str;
            };
          };
        }
      );
    };

    # modules that install a general-purpose tool declare it here, next to the install, so the list in
    # ~/.claude/CLAUDE.md always matches what is installed
    tools = lib.mkOption {
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
  };
}
