{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    isd
    lazydocker
  ];
}
