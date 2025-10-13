{
  agenix,
  pkgs,
  system,
  ...
}:

{
  age.identityPaths =
    if pkgs.stdenv.isDarwin then
      [ "/Users/jademeskill/.ssh/genixis_secrets" ]
    else
      [ "/root/.ssh/genixis_secrets" ];

  environment.systemPackages = [
    agenix.packages.${system}.default
  ];
}
