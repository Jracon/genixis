{
  programs.starship = {
    enable = true;

    settings = {
      format = "$username[@](purple)$hostname$localip$directory$git_branch$git_status$line_break$python$character";
      right_format = "$cmd_duration";

      character = {
        error_symbol = "[>](bold red)";
        success_symbol = "[>](bold green)";
      };
      cmd_duration = {
        format = "completed in [$duration]($style)";
        min_time = 0;
        show_milliseconds = true;
      };
      directory = {
        format = " in [$path]($style)[$read_only]($read_only_style) ";
        read_only = " [ro]";
        truncation_length = -1;
      };
      git_branch = {
        symbol = "";
      };
      git_status = {
        ahead = "->$count";
        behind = "$count<-";
        conflicted = "!=";
        deleted = "x";
        diverged = "$behind_count<->$ahead_count";
        renamed = "=";
        staged = "+$count";
      };
      hostname = {
        format = "[$ssh_symbol$hostname]($style)";
        ssh_only = false;
        ssh_symbol = "";
        style = "purple";
      };
      localip = {
        disabled = false;
        format = " \\([$localipv4]($style)\\)";
        ssh_only = false;
        style = "blue";
      };
      python = {
        format = "[\${symbol}\${pyenv_prefix}(\${version} )]($style)";
        symbol = "🐍";
        version_format = "\${raw}";
      };
      username = {
        format = "[$user]($style)";
        show_always = true;
        style_root = "bright-red";
        style_user = "bright-white";
      };
    };
  };
}
