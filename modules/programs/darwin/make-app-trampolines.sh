fromDir="$HOME/Applications/Home Manager Apps"
toDir="$HOME/Applications/Home Manager Trampolines"
mkdir -p "$toDir"

(
  cd "$fromDir" || exit 1
  for app in *.app; do
    [ -d "$app" ] || continue

    /usr/bin/osacompile -o "$toDir/$app" -e "do shell script \"open '$fromDir/$app'\""

    srcResources="$fromDir/$app/Contents/Resources"
    dstResources="$toDir/$app/Contents/Resources"
    mkdir -p "$dstResources"

    icnsFiles=("$srcResources"/*.icns)

    if [ "${#icnsFiles[@]}" -eq 1 ]; then
      # Only one icon — copy it as applet.icns
      cp "${icnsFiles[0]}" "$dstResources/applet.icns"
    else
      # Multiple icons — look for one starting with a capital letter
      capitalIcns=$(find "$srcResources" -maxdepth 1 -type f -name '[A-Z]*.icns' | head -n 1)
      if [ -n "$capitalIcns" ]; then
        cp "$capitalIcns" "$dstResources/applet.icns"
      else
        echo "Warning: No capitalized .icns found for $app" >&2
      fi
    fi
  done
)

# cleanup
(
  cd "$toDir" || exit 1
  for app in *.app; do
    [ -d "$app" ] || continue
    if [ ! -d "$fromDir/$app" ]; then
      rm -rf "$app"
    fi
  done
)
