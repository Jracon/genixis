{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    vscode
  ];

  programs.vscode = {
    enable = true;
  };
}
