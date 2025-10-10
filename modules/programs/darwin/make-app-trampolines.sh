fromDir="$HOME/Applications/Home Manager Apps"
toDir="$HOME/Applications/Home Manager Trampolines"
mkdir -p "$toDir"

(
  cd "$fromDir" || exit 1
  for app in *.app; do
    [ -d "$app" ] || continue

    /usr/bin/osacompile -o "$toDir/$app" -e "do shell script \"open '$fromDir/$app'\""
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
