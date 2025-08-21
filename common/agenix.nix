{
  agenix, 
  system, 
  ...
}:

{
  age.identityPaths = [ 
    "/root/.ssh/genixis_secrets" # TODO: add darwin path
  ];

  environment.systemPackages = [
    agenix.packages.${system}.default
  ];
}
