{
  config,
  ...
}:

{
  age.secrets.hermes_secrets.file = ./secrets.age;

  services.hermes-agent = {
    enable = true;

    addToSystemPackages = true;
    settings.model.default = "anthropic/claude-sonnet-4";

    environmentFiles = [
      config.age.secrets.hermes_secrets.path
    ];
  };
}
