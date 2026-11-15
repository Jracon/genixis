{
  lib,
  pkgs,
  ...
}:

let
  # installs one script of scripts/ as a command of the media host; the scripts
  # carry no nix-shell shebang, so their tools come from the wrapper PATH
  mediaScript =
    name: runtimeInputs: source:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      (
        if runtimeInputs == [ ] then
          ''
            install -Dm 0755 ${source} $out/bin/${name}
          ''
        else
          ''
            install -Dm 0755 ${source} $out/${name}.sh
            mkdir -p $out/bin
            makeWrapper $out/${name}.sh $out/bin/${name} --prefix PATH : ${lib.makeBinPath runtimeInputs}
          ''
      );
in
{
  environment.systemPackages = [
    (mediaScript "media-playlist-generator" [ pkgs.xmlstarlet ] ./scripts/playlist_generator.sh)
    (mediaScript "media-path-generator" [ ] ./scripts/path_generator.sh)
    (mediaScript "media-clean" [ ] ./scripts/clean.sh)
    (mediaScript "media-fetch-posters" [
      pkgs.curl
      pkgs.file
    ] ./scripts/download_media_images.sh)
  ];
}
