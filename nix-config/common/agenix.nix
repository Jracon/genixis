{
  agenix, 
  system, 
  ...
}:

{
  age.identityPaths = [ "/root/.ssh/genixis_secrets" ];

  environment.systemPackages = [
    agenix.packages.${system}.default
  ];
}
