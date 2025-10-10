fromDir="$HOME/Applications/Home Manager Apps"
toDir="$HOME/Applications/Home Manager Trampolines"
mkdir -p "$toDir"
echo "Starting App Trampoline Creation!"

(
  cd "$fromDir"
  for app in *.app; do
    /usr/bin/osacompile -o "$toDir/$app" -e "do shell script \"open '$fromDir/$app'\""

    # Just clobber the applet icon laid down by osacompile rather than do
    # surgery on the plist.
    cp "$fromDir/$app/Contents/Resources"/*.icns "$toDir/$app/Contents/Resources/applet.icns"
  done
)

# cleanup
(
  cd "$toDir"
  for app in *.app; do
    if [ ! -d "$fromDir/$app" ]; then
      rm -rf "$toDir/$app"
    fi
  done
)