{
  ...
}:

{
  programs.yt-dlp = {
    enable = true;

    settings = {
      merge-output-format = "mkv";
      remux-video = "mkv";
      sub-lang = "en.*";
      write-subs = true;
    };
  };
}
