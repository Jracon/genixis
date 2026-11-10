{
  ...
}:

{
  # fastfetch prints the OS logo and the system information in the home tab
  # of the host WezTerm window (wezterm-attach of the project tool starts
  # it); no shell of this configuration runs it anywhere else; every host
  # and every standalone home installs the package (issue #131). The panel
  # follows the aesthetic document: exactly these modules in this order,
  # glyph keys on the stock colours and the stock separator, the root file
  # system only, IPv4 only, and no network call (docs/terminal-aesthetic.md)
  programs.fastfetch = {
    enable = true;

    settings = {
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = " OS";
        }
        {
          type = "host";
          key = " Host";
        }
        {
          type = "kernel";
          key = " Kernel";
        }
        {
          type = "uptime";
          key = " Uptime";
        }
        {
          type = "packages";
          key = " Packages";
        }
        {
          type = "shell";
          key = " Shell";
        }
        {
          type = "display";
          key = " Display";
        }
        {
          type = "cpu";
          key = " CPU";
        }
        {
          type = "gpu";
          key = " GPU";
        }
        {
          type = "memory";
          key = " Memory";
        }
        {
          type = "disk";
          key = " Disk";
          folders = [ "/" ];
        }
        {
          type = "localip";
          key = " Local IP";
          showIpv4 = true;
          showIpv6 = false;
          showLoop = false;
        }
      ];
    };
  };
}
