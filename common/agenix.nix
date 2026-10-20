{
  agenix,
  config,
  pkgs,
  system,
  ...
}:

{
  age.identityPaths =
    if pkgs.stdenv.hostPlatform.isDarwin then
      [
        "/Users/${config.system.primaryUser}/.ssh/genixis_secrets"
      ]
    else
      [
        "/root/.ssh/genixis_secrets"
      ];

  environment.systemPackages = [
    agenix.packages.${system}.default
  ];
}
