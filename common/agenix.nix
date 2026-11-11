{
  agenix,
  config,
  pkgs,
  system,
  ...
}:

{
  # the system channel reads only the host key of this host (see docs/secrets.md);
  # a host that declares no system secret decrypts nothing, so the file need not exist there
  age.identityPaths =
    if pkgs.stdenv.hostPlatform.isDarwin then
      [
        "/Users/${config.system.primaryUser}/.ssh/genixis_host"
      ]
    else
      [
        "/root/.ssh/genixis_host"
      ];

  environment.systemPackages = [
    agenix.packages.${system}.default
  ];
}
