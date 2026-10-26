{
  ...
}:

{
  # user-level Claude Code context: it tells agents in any project about the tools of this machine
  home.file = {
    ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
    ".claude/skills/project/SKILL.md".source = ./claude/skills/project/SKILL.md;
  };
}
