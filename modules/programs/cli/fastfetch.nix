{
  ...
}:

let
  # the key glyphs of the panel, one Nerd Font glyph for one concept
  # (docs/terminal-aesthetic.md). A private-use byte renders no shape in a
  # plain editor, so the codepoints ride here: the desktop U+F108 (os), the
  # server U+F233 (host), the cog U+F013 (kernel), the clock U+F017 (uptime),
  # the archive box U+F187 (packages), the console U+F120 (shell), the screen
  # U+F26C (display), the chip U+F2DB (cpu), the picture U+F03E (gpu), the
  # cubes U+F1B3 (memory), the drive U+F0A0 (disk), and the globe U+F0AC
  # (localip).
  glyph = {
    cpu = "";
    disk = "";
    display = "";
    gpu = "";
    host = "";
    kernel = "";
    localip = "";
    memory = "";
    os = "";
    packages = "";
    shell = "";
    uptime = "";
  };
in

{
  # fastfetch prints the OS logo and the system information at the start of
  # every interactive shell: the fish init runs it
  # (modules/programs/cli/fish.nix, issue #297). Every host and every
  # standalone home installs the package (issue #131). The panel follows
  # the aesthetic document: exactly these modules in this order, glyph keys
  # on the stock colours and the stock separator, one aligned column of
  # values, the root file system only, IPv4 only, and no network call
  # (docs/terminal-aesthetic.md)
  programs.fastfetch = {
    enable = true;

    settings = {
      # the width of the key column: the widest key, the glyph, the space,
      # and the label Local IP, fills it, and fastfetch puts every value at
      # its end, so each separator and each value sits on one column. Keep
      # the width in step with the widest key (docs/terminal-aesthetic.md)
      display.key.width = 13;
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = "${glyph.os} OS";
        }
        {
          type = "host";
          key = "${glyph.host} Host";
        }
        {
          type = "kernel";
          key = "${glyph.kernel} Kernel";
        }
        {
          type = "uptime";
          key = "${glyph.uptime} Uptime";
        }
        {
          type = "packages";
          key = "${glyph.packages} Packages";
        }
        {
          type = "shell";
          key = "${glyph.shell} Shell";
        }
        {
          type = "display";
          key = "${glyph.display} Display";
        }
        {
          type = "cpu";
          key = "${glyph.cpu} CPU";
        }
        {
          type = "gpu";
          key = "${glyph.gpu} GPU";
        }
        {
          type = "memory";
          key = "${glyph.memory} Memory";
        }
        {
          type = "disk";
          key = "${glyph.disk} Disk";
          folders = [ "/" ];
        }
        {
          type = "localip";
          key = "${glyph.localip} Local IP";
          showIpv4 = true;
          showIpv6 = false;
          showLoop = false;
        }
      ];
    };
  };
}
