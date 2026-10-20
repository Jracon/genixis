{
  pkgs,
  ...
}:

{
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    ark
    baloo-widgets
    discover
    dolphin
    dolphin-plugins
    elisa
    ffmpegthumbs
    gwenview
    kate
    khelpcenter
    konsole
    krdp
    ktexteditor
    okular
    plasma-browser-integration
    plasma-keyboard
    plasma-workspace-wallpapers
    qrca
    qtvirtualkeyboard
    spectacle
    union
  ];

  # konsole is excluded above, so point Terminal=true launchers (e.g. yazi.desktop) at WezTerm.
  # A system-wide default: ~/.config/kdeglobals stays writable by Plasma and still overrides it.
  environment.etc."xdg/kdeglobals".text = ''
    [General]
    TerminalApplication=wezterm
    TerminalService=org.wezfurlong.wezterm.desktop
  '';
}
