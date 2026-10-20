{
  nix-cachyos-kernel,
  pkgs,
  ...
}:

{
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

  nix.settings = {
    substituters = [
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    ];
  };

  nixpkgs.overlays = [
    nix-cachyos-kernel.overlays.pinned
  ];
}
