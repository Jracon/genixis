{
  programs.starship = {
    enable = true;

    enableZshIntegration = true;

    settings = {
      format = "$username$hostname$localip$directory$git_branch$git_status$line_break$character";
      right_format = "$cmd_duration";

      character = {
        error_symbol = "[>](bold red)";
        success_symbol = "[>](bold green)";
      };
      cmd_duration = {
        format = "completed in [$duration]($style)";
        min_time = 0;
        min_time_to_notify = 300000;
        show_milliseconds = true;
        show_notifications = true;
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
        format = "@[$ssh_symbol$hostname]($style)";
        ssh_only = false;
        ssh_symbol = "ssh:";
        style = "bold dimmed purple";
      };
      localip = {
        disabled = false;
        format = " \\([$localipv4]($style)\\)";
        ssh_only = false;
        style = "bold dimmed blue";
      };
      username = {
        format = "[$user]($style)";
        show_always = true;
        style_user = "bold bright-white";
      };
    };
  };
}
