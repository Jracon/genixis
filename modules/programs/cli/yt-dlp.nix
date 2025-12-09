{
  programs.yt-dlp = {
    enable = true;

    settings = {
      merge-output-format = "mkv";
      remux-video = "mkv";
      sub-langs = "en.*";
      write-subs = true;
    };
  };
}
