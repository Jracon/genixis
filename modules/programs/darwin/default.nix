{
  lib,
  pkgs,
  ...
}:

{
  home.activation.makeSpotlightApps =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
      ]
      ''
        fromDir="$HOME/Applications/Home Manager Apps"
        toDir="$HOME/Applications/Home Manager Spotlight Apps"
        mkdir -p "$toDir"

        (
          cd "$fromDir" || exit 1
          for app in *.app; do
            [ -d "$app" ] || continue

            /usr/bin/osacompile -o "$toDir/$app" -e "do shell script \"open '$fromDir/$app'\""

            # Copy CFBundleIconFile and CFBundleIconName from source Info.plist
            srcPlist="$fromDir/$app/Contents/Info.plist"
            dstPlist="$toDir/$app/Contents/Info.plist"
            for key in CFBundleIconFile CFBundleIconName; do
              val=$(/usr/libexec/PlistBuddy -c "Print :$key" "$srcPlist" 2>/dev/null || true)
              if [ -n "$val" ]; then
                /usr/libexec/PlistBuddy -c "Set :$key $val" "$dstPlist" 2>/dev/null \
                  || /usr/libexec/PlistBuddy -c "Add :$key string $val" "$dstPlist"
              fi
            done

            # Sync icons: remove osacompile's default Assets.car, then copy source icons
            srcRes="$fromDir/$app/Contents/Resources"
            dstRes="$toDir/$app/Contents/Resources"
            rm -f "$dstRes/Assets.car"
            find "$dstRes" -name '*.icns' -delete
            if [ -d "$srcRes" ]; then
              ${pkgs.rsync}/bin/rsync -a --include='*.icns' --include='Assets.car' --exclude='*' "$srcRes/" "$dstRes/"
            fi

            touch "$toDir/$app"
          done
        )

        (
          cd "$toDir" || exit 1
          for app in *.app; do
            [ -d "$app" ] || continue
            if [ ! -d "$fromDir/$app" ]; then
              rm -rf "$app"
            fi
          done
        )
      '';
}
