{
  config,
  ...
}:

let
  # the os icon marks the machine in the signature colour of the palette
  # (docs/terminal-aesthetic.md); the ANSI slot holds the palette hue.
  # The os symbols and the python symbol are set, because the stock starship
  # defaults are emoji, and the symbol set of the document has no emoji.
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
      # dangles after the directory segment, and a segment that no segment
      # follows ends flat
      format = "$os$username[@](bg:purple fg:bright-white)$hostname$localip$directory$git_branch$git_status$line_break$python$cmd_duration$character";

      character = {
        error_symbol = "[>](bold red)";
        success_symbol = "[>](bold green)";
      };
      cmd_duration = {
        format = "completed in [$duration]($style) ";
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
        format = "[](fg:cyan bg:green)[$symbol$branch]($style)";
        style = "bg:green fg:bright-white";
        symbol = "";
      };
      git_status = {
        # one glyph for one concept, counts as plain digits behind the glyph;
        # each glyph carries one leading space, so the states stay apart
        ahead = " 󰁝$count";
        behind = " 󰅅$count";
        conflicted = " $count";
        deleted = " $count";
        diverged = " 󰅅$behind_count 󰁝$ahead_count";
        format = "[$all_status$ahead_behind ]($style)[](fg:green)";
        modified = " ";
        renamed = " $count";
        staged = " $count";
        stashed = " ";
        style = "bg:green fg:bright-white";
        untracked = " ";
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
        format = "[ $localipv4 ]($style)[](fg:purple bg:cyan)";
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
        symbol = "";
        version_format = "\${raw}";
      };
      username = {
        format = "[$user]($style)";
        show_always = true;
        style_root = "bg:red fg:bright-white";
        style_user = "bg:purple fg:bright-white";
      };
    };
  };
}
