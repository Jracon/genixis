{
  config,
  lib,
  themes,
  ...
}:

{
  config.genixis.palette.colors = themes.lib.resolve config.genixis.palette.name;

  options.genixis.palette = {
    colors = lib.mkOption {
      description = "The selected palette from the themes flake: dark and light colours, signature hue, ANSI slots.";
      readOnly = true;
      type = lib.types.attrs;
    };

    name = lib.mkOption {
      default = "violet";
      description = "Which palette from the themes flake to use.";
      type = lib.types.enum themes.lib.names;
    };
  };
}
