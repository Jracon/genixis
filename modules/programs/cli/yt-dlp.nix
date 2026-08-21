{
  programs.yt-dlp = {
    enable = true;

    settings = {
      merge-output-format = "mkv";
      sub-langs = "en.*";
      write-subs = true;
    };
  };
}
