{
  pkgs, 
  ...
}:

{
  age.identityPaths = [ "/root/.ssh/genixis_secrets" ];

  environment.systemPackages = with pkgs; [
    agenix
  ];
}
