{
  config,
  lib,
  ...
}:

let
  tools = lib.mapAttrsToList (
    name: tool: "- `${name}`: ${tool.description}"
  ) config.genixis.claude.tools;
in
{
  # user-level Claude Code context: it tells agents in any project about the tools of this machine
  config.home = {
    file = {
      ".claude/CLAUDE.md".text = ''
        ${lib.removeSuffix "\n" (builtins.readFile ./claude/CLAUDE.md)}

        # Installed tools

        Prefer these to the older equivalents.

        ${lib.concatStringsSep "\n" tools}
      '';
      ".claude/skills/project/SKILL.md".source = ./claude/skills/project/SKILL.md;
    };

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
            description = "One line for ~/.claude/CLAUDE.md: what the tool does and which tool it replaces.";
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
