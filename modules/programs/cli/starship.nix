{
  config,
  ...
}:

let
  # the prompt glyphs of the aesthetic document, one Nerd Font glyph for one
  # concept (docs/terminal-aesthetic.md). A private-use byte renders no shape
  # in a plain editor, so the codepoints ride here: the segment join arrow is
  # U+E0B0 (nf-pl-left-hard-divider); the git states are the warning triangle
  # U+F071 (conflicted), the cross U+F00D (deleted), the pencil U+F040
  # (modified), the crossing arrows U+F074 (renamed), the plus U+F067
  # (staged), the inbox U+F01C (stashed), and the question mark in a circle
  # U+F059 (untracked); the python icon is U+E606 (seti-python). The line ends
  # round, in the manner of the gruvbox-rainbow preset: the left cap is
  # U+E0B6 and the right cap is U+E0B4. The git branch is the branch fork
  # U+E0A0. The os icons and the ahead and behind arrows ride raw at their
  # use sites.
  nf = {
    branch = "";
    capLeft = "";
    capRight = "";
    arrow = "";
    conflicted = "";
    deleted = "";
    modified = "";
    python = "";
    renamed = "";
    staged = "";
    stashed = "";
    untracked = "";
  };
  # the os icon marks the machine in the signature colour of the palette
  # (docs/terminal-aesthetic.md); the ANSI slot holds the palette hue.
  # Starship names the magenta ANSI slot purple and silently drops the name
  # magenta, so the palette value needs the translation
  signatureAnsi = config.genixis.palette.colors.signatureAnsi;
  signature = if signatureAnsi == "magenta" then "purple" else signatureAnsi;
in
{
  programs.starship = {
    enable = true;

    # fish.nix runs the starship init itself, so the transient prompt wrapper
    # can copy the prompt function that the init defines (fish 4.1 final
    # rendering, docs/terminal-aesthetic.md)
    enableFishIntegration = false;

    settings = {
      # line one: filled segments with arrow joins, line two: unfilled
      # (docs/terminal-aesthetic.md). A join lives on the module that follows
      # it, so it hides with that module: outside a git repo no green arrow
      # dangles after the directory segment. The round caps of the two line
      # ends follow the same rule: the left cap rides the username segment,
      # and the right cap rides the git status segment, so outside a git repo
      # the line ends flat
      format = "$username[@](bg:purple fg:bright-white)$hostname$localip$directory$git_branch$git_status$line_break$os$python$cmd_duration$character";

      character = {
        error_symbol = "[>](bold red)";
        success_symbol = "[>](bold green)";
      };
      cmd_duration = {
        format = "[$duration]($style) ";
        min_time = 0;
        show_milliseconds = true;
      };
      directory = {
        format = "[$path ]($style)[$read_only]($read_only_style)";
        read_only = " ro";
        read_only_style = "bg:cyan fg:bright-white";
        style = "bg:cyan fg:bright-white";
        truncation_length = -1;
      };
      git_branch = {
        format = "[${nf.arrow}](fg:cyan bg:green)[$symbol$branch]($style)";
        style = "bg:green fg:bright-white";
        symbol = "${nf.branch} ";
      };
      git_status = {
        # one glyph for one concept, counts as plain digits behind the glyph;
        # each glyph carries one leading space, so the states stay apart
        ahead = " 󰁝$count";
        behind = " 󰅅$count";
        conflicted = " ${nf.conflicted}$count";
        deleted = " ${nf.deleted}$count";
        diverged = " 󰅅$behind_count 󰁝$ahead_count";
        format = "[$all_status$ahead_behind ]($style)[${nf.capRight}](fg:green)";
        modified = " ${nf.modified}";
        renamed = " ${nf.renamed}$count";
        staged = " ${nf.staged}$count";
        stashed = " ${nf.stashed}";
        style = "bg:green fg:bright-white";
        untracked = " ${nf.untracked}";
      };
      hostname = {
        format = "[$hostname]($style)";
        ssh_only = false;
        ssh_symbol = "";
        style = "bg:purple fg:bright-white";
      };
      localip = {
        # the trailing arrow joins the identity segment onto the directory
        disabled = false;
        format = "[ $localipv4 ]($style)[${nf.arrow}](fg:purple bg:cyan)";
        ssh_only = false;
        style = "bg:purple fg:bright-white";
      };
      os = {
        disabled = false;
        # the style key of the os module applies nothing in starship 1.27, so
        # the signature colour rides inline in the format string
        format = "[$symbol ](${signature})";
        symbols = {
          Linux = "󰌽";
          Macos = "󰀵";
          NixOS = "󱄅";
          Unknown = "";
          Windows = "󰖳";
        };
      };
      python = {
        format = "[\${symbol}\${pyenv_prefix}(\${version} )]($style)";
        symbol = nf.python;
        version_format = "\${raw}";
      };
      username = {
        # the round left cap opens the line on the fill of this segment; the
        # username always shows, so the cap always shows
        format = "[${nf.capLeft}](fg:purple)[$user]($style)";
        show_always = true;
        style_root = "bg:purple fg:bright-white";
        style_user = "bg:purple fg:bright-white";
      };
    };
  };
}
