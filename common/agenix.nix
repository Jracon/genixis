{
  pkgs,
  ...
}:

{
  age.identityPaths =
    if pkgs.stdenv.isDarwin then
      [ "/Users/jademeskill/.ssh/genixis_secrets" ]
    else
      [
        "/root/.ssh/genixis_secrets"
        # "/run/credentials/@system/genixis_secrets"
      ];
}
