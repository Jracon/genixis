{
  self,
  pkgs,
}:
let
  # one gate check: the script fails its derivation on a finding, so the gate
  # step of the workflow and nix flake check run it as a gate (docs/ci.md)
  check =
    name: tools: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = tools;
      }
      ''
        ${script}
        touch $out
      '';

  # one report check: the script writes the report to the derivation output
  # and never fails, so the gate stays green and the reports job prints it
  report =
    name: tools: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = tools;
      }
      ''
        ${script}
      '';
in
{
  # an unused let binding is dead code; module argument names stay out of the
  # check, because a module declares its interface through them
  deadnix = check "deadnix" [ pkgs.deadnix ] ''
    deadnix --fail --no-lambda-arg --no-lambda-pattern-names ${self}
  '';

  # the empty-pattern rule is off, because the module header convention
  # writes a no-argument module as `{ ... }:` (lib/statix.toml)
  statix = check "statix" [ pkgs.statix ] ''
    statix check --config ${./statix.toml} ${self}
  '';

  # the go module imports nothing outside the standard library, so both
  # analyzers need no network (modules/programs/cli/project/go.mod); cgo
  # stays off, because the check sandbox holds no C compiler
  go-vet = check "go-vet" [ pkgs.go ] ''
    export HOME="$TMPDIR" GOCACHE="$TMPDIR/go-cache" GOTOOLCHAIN=local CGO_ENABLED=0
    cd ${self}/modules/programs/cli/project
    go vet ./...
  '';

  staticcheck =
    check "staticcheck"
      [
        pkgs.go
        pkgs.go-tools
      ]
      ''
        export HOME="$TMPDIR" GOCACHE="$TMPDIR/go-cache" GOTOOLCHAIN=local CGO_ENABLED=0
        cd ${self}/modules/programs/cli/project
        staticcheck ./...
      '';

  # the rule set stays pinned, because the default set of a new ruff
  # release carries opinion rules, and a rule upgrade must not redden
  # the gate on its own
  ruff = check "ruff" [ pkgs.ruff ] ''
    ruff check --select E4,E7,E9,F ${self}/modules/programs/cli/claude ${self}/modules/services/dispatcher
  '';

  # the lua tree reads the api of neovim through the global `vim`
  luacheck = check "luacheck" [ pkgs.luajitPackages.luacheck ] ''
    luacheck --globals vim --max-line-length 120 ${self}/modules/programs/cli/neovim/lua
  '';

  # the documentation sweep of the gate: cited paths must resolve, the
  # files must be listed in AGENTS.md, every record file must sit in the
  # register index, and the two writing rules hold
  # (docs/adr/deep-homes-of-subsumed-products.md, docs/adr/gate-writing-rules.md)
  docs =
    check "docs"
      [
        pkgs.findutils
        pkgs.gnugrep
      ]
      ''
        set -eu
        cd "${self}"
        missing=0
        # the record files of docs/adr are exempt as citation sources,
        # because each record is append-only and names historical paths
        for p in $(grep -rhoE 'docs/([a-z0-9-]+/)?[a-z0-9-]+\.md' . \
            --include='*.nix' --include='*.go' --include='*.py' --include='*.md' \
            --exclude-dir=adr | sort -u); do
          test -f "$p" || { echo "missing: $p"; missing=1; }
        done
        for f in docs/*.md; do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        for f in docs/adr/*.md; do
          grep -q "$f" docs/decisions.md || { echo "unindexed: $f"; missing=1; }
        done
        for f in $(find modules -name README.md); do
          grep -q "$f" AGENTS.md || { echo "unlisted: $f"; missing=1; }
        done
        # a citation carries no line number, and each sub-list item is
        # lettered; docs/decisions.md is exempt, because the index and the
        # rejected list are append-only, and the record files of docs/adr
        # sit outside the glob of this loop for the same reason
        for f in docs/*.md AGENTS.md; do
          case "$f" in docs/decisions.md) continue ;; esac
          grep -nE '\.(md|nix|go|py|lua|sh|awk|json|ya?ml|toml|age|pub):[0-9]+' "$f" && missing=1 || true
          grep -nE '^ +([-*+]|[0-9]+\.) ' "$f" && missing=1 || true
        done
        test "$missing" -eq 0
      '';

  # an input age is a signal, not a failure: the nightly update renews the
  # lock, and a growing age names an update that stopped (issue 355, M8)
  input-age =
    report "input-age"
      [
        pkgs.gawk
        pkgs.jq
      ]
      ''
        jq -r '.nodes | to_entries[] | select(.value.locked.lastModified != null) | "\(.value.locked.lastModified) \(.key)"' ${self}/flake.lock \
          | sort -k1,1nr \
          | awk -v now="$(date +%s)" '{ printf "%4d days  %s  %s\n", int((now - $1) / 86400), strftime("%Y-%m-%d", $1), $2 }' \
          > "$out"
      '';

  # no secret in the clear, and no agenix file that decrypts to nothing
  # (docs/secrets.md, security law item 1; docs/runbook.md names the gap
  # that agenix verifies the recipients, not the content)
  secrets =
    check "secrets"
      [
        pkgs.age
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gitleaks
      ]
      ''
        set -eu
        gitleaks dir --redact ${self}
        # an agenix file with an empty plaintext carries only the age header,
        # the recipient stanzas, and the 16-byte payload tag, so its size
        # equals the size of a file that encrypts an empty plaintext with the
        # same count of recipients: the check calibrates those sizes itself,
        # for one and for two recipients, and flags every exact match up to
        # eight recipients
        age-keygen -o "$TMPDIR/key"
        pub="$(sed -n 's/^# public key: //p' "$TMPDIR/key")"
        : > "$TMPDIR/empty"
        age -r "$pub" -o "$TMPDIR/empty1.age" "$TMPDIR/empty"
        age -r "$pub" -r "$pub" -o "$TMPDIR/empty2.age" "$TMPDIR/empty"
        one=$(stat -c %s "$TMPDIR/empty1.age")
        stanza=$(($(stat -c %s "$TMPDIR/empty2.age") - one))
        while read -r size file; do
          body=$((size - one))
          if test $((body % stanza)) -eq 0 && test "$body" -ge 0 && test $((body / stanza)) -le 7; then
            echo "empty plaintext: $file ($size bytes)"
            exit 1
          fi
        done < <(find ${self} -name '*.age' -printf '%s %p\n')
      '';

  # the port-claim detector: two services that claim one host port with one
  # protocol cannot both bind it (issue 370). The claims come from the
  # evaluated tree, so the check is deterministic and cheap, and it gates
  # (docs/ci.md names the posture rule). Claims that the tree cannot name
  # stay outside: a container with host networking publishes its ports
  # directly (jellyfin today), the rnsd discovery ports ride multicast
  # packet rules, the dispatcher receiver binds the podman bridge behind an
  # interface-scoped rule, and rclone-webdav serves with no firewall port
  port-claims =
    let
      inherit (pkgs) lib;

      # the default ports of the syncthing daemon, as its own documentation
      # lists them: the gui binds 8384, transfers hold 22000 over tcp and
      # udp, and local discovery holds 21027 over udp. The module opens all
      # but the gui port through openDefaultPorts
      syncthingPorts = [
        "8384/tcp"
        "22000/tcp"
        "22000/udp"
        "21027/udp"
      ];

      # one claim line: host, port with protocol, claimant
      claim =
        host: port: claimant:
        "${host} ${port} ${claimant}";

      # the host port of one container ports entry, with the protocol from
      # the entry suffix
      containerClaim =
        host: name: entry:
        claim host "${lib.head (lib.splitString ":" entry)}/${
          if lib.hasSuffix "/udp" entry then "udp" else "tcp"
        }" "container ${name}";

      claims =
        let
          hostClaims =
            hostName:
            let
              cfg = self.nixosConfigurations.${hostName}.config;
            in
            lib.flatten (
              lib.mapAttrsToList (
                name: container: map (containerClaim hostName name) container.ports
              ) cfg.virtualisation.oci-containers.containers
              ++ lib.optionals cfg.services.syncthing.enable (
                map (port: claim hostName port "the native syncthing service") syncthingPorts
              )
              ++ lib.optionals (cfg.services.tailscale.enable && cfg.services.tailscale.openFirewall) [
                (claim hostName "${toString cfg.services.tailscale.port}/udp" "tailscale")
              ]
            );
        in
        lib.sortOn (x: x) (lib.flatten (map hostClaims (builtins.attrNames self.nixosConfigurations)));
    in
    check "port-claims" [ pkgs.gawk ] ''
      gawk '
        {
          claimant = $3
          for (i = 4; i <= NF; i++) claimant = claimant " " $i
          key = $1 " " $2
          if (key in first && first[key] != claimant) {
            printf "two services claim one port: %s %s: %s and %s\n", $1, $2, first[key], claimant
            bad = 1
          } else if (!(key in first)) {
            first[key] = claimant
          }
        }
        END { exit bad }
      ' ${pkgs.writeText "port-claims" (lib.concatStringsSep "\n" claims + "\n")}
    '';

  # the playlist generator fixture of the media-servers group: the sandbox
  # cannot write /mnt, so the fixture rewrites the one deployed playlist
  # prefix of a copy to a fixture tree and runs that copy through every
  # argument form. The argument resolution is the code under test, and the
  # rewrite leaves it untouched. The check lands with the fix of the
  # relative manifests directory, so no gate run held the defect (issue 401)
  playlist-fixture =
    check "playlist-fixture"
      [
        pkgs.gnugrep
        pkgs.gnused
        pkgs.xmlstarlet
      ]
      ''
        set -eu
        root=$PWD/fixture
        media=$root/media
        playlists=$media/playlists
        library=$root/library
        jellyfin=$root/jellyfin/data/data/playlists
        altplay=$root/altplay
        mkdir -p "$playlists" "$jellyfin/anime" "$jellyfin/movies" \
          "$altplay/anime" "$altplay/movies" "$library/anime" "$library/movies" "$root/empty"
        printf '<Item/>\n' >"$jellyfin/anime/playlist.xml"
        printf '<Item/>\n' >"$jellyfin/movies/playlist.xml"
        printf '<Item/>\n' >"$altplay/anime/playlist.xml"
        printf '<Item/>\n' >"$altplay/movies/playlist.xml"
        printf 'one\n' >"$library/anime/Show S01E01.mkv"
        printf 'two\n' >"$library/movies/Film.mkv"
        printf '# a comment line\n%s\n' "$library/anime/Show S01E01" >"$playlists/anime.txt"
        printf '%s\n' "$library/movies/Film" >"$playlists/movies.txt"
        sed "s|/mnt/jellyfin/data/data/playlists|$jellyfin|" \
          ${self}/modules/virtualisation/oci-containers/media-servers/scripts/playlist_generator.sh \
          >"$root/playlist_generator.sh"

        # the playlist directory of one name holds exactly one item, and
        # the item carries the library file of its manifest line
        one_item() {
          count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$1/playlist.xml")
          test "$count" = 1
          path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem/Path' "$1/playlist.xml")
          test "$path" = "$2"
        }

        # a relative manifests directory from the parent directory: the log
        # and the manifest glob resolve against the path as the caller gave
        # it, and no nested playlists tree appears
        cd "$media"
        bash "$root/playlist_generator.sh" playlists
        test -f "$playlists/playlist_generator.log"
        test ! -e "$playlists/playlists"
        grep -qx anime "$playlists/playlist_generator.log"
        grep -qx movies "$playlists/playlist_generator.log"
        grep -Fx "playlist directory: $jellyfin" "$playlists/playlist_generator.log"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # the absolute directory of the timer: a rerun replaces the items
        # instead of appending them
        bash "$root/playlist_generator.sh" "$playlists"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # a relative manifest file from the parent directory
        bash "$root/playlist_generator.sh" playlists/anime.txt
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"

        # no argument: the manifests of the current directory
        cd "$playlists"
        bash "$root/playlist_generator.sh"
        one_item "$jellyfin/anime" "$library/anime/Show S01E01.mkv"
        one_item "$jellyfin/movies" "$library/movies/Film.mkv"

        # the playlists root override: PLAYLIST_DIRECTORY moves the write
        # target, the default root stays untouched, and the log names the
        # root the run used
        printf '<Item/>\n' >"$jellyfin/anime/playlist.xml"
        printf '<Item/>\n' >"$jellyfin/movies/playlist.xml"
        cd "$media"
        PLAYLIST_DIRECTORY="$altplay" bash "$root/playlist_generator.sh" playlists
        one_item "$altplay/anime" "$library/anime/Show S01E01.mkv"
        one_item "$altplay/movies" "$library/movies/Film.mkv"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems)' "$jellyfin/anime/playlist.xml")
        test "$count" = 0
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems)' "$jellyfin/movies/playlist.xml")
        test "$count" = 0
        grep -Fx "playlist directory: $altplay" "$playlists/playlist_generator.log"

        # a manifest with two entries: one run writes both items, and a
        # rerun replaces them instead of appending them
        mkdir -p "$jellyfin/shows" "$library/shows"
        printf '<Item/>\n' >"$jellyfin/shows/playlist.xml"
        printf 'one\n' >"$library/shows/Show A S01E01.mkv"
        printf 'two\n' >"$library/shows/Show B S01E01.mkv"
        printf '%s\n%s\n' "$library/shows/Show A S01E01" "$library/shows/Show B S01E01" >"$playlists/shows.txt"
        bash "$root/playlist_generator.sh" "$playlists"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/shows/playlist.xml")
        test "$count" = 2
        path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem[1]/Path' "$jellyfin/shows/playlist.xml")
        test "$path" = "$library/shows/Show A S01E01.mkv"
        path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem[2]/Path' "$jellyfin/shows/playlist.xml")
        test "$path" = "$library/shows/Show B S01E01.mkv"
        bash "$root/playlist_generator.sh" "$playlists"
        count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/shows/playlist.xml")
        test "$count" = 2

        # a relative empty directory: the run fails and names the anchored
        # directory
        cd "$root"
        if bash "$root/playlist_generator.sh" empty >"$root/empty.out" 2>&1; then
          echo "the empty directory did not fail"
          exit 1
        fi
        grep -Fq "No .txt files found in $root/empty" "$root/empty.out"
      '';

  # the clean script fixture of the media-servers group: it runs the
  # repository file itself, because the store install copies it
  # verbatim, and covers the probe surface of the ingestion pull and
  # the edges of the deduplication: a dry run names each candidate file
  # once and logs it once, the wet run deletes the stray files and keeps
  # the videos, the sidecars, the thumbs, and the posters, a season
  # without a video and a folder without a video keep their files, a
  # directory is never a candidate, and the season number pads to two
  # digits without grep and awk, also under a leading zero. A movie
  # folder with a bracket group in its video name keeps its sidecar,
  # its thumb, and its subtitle through the wet run, and the family
  # match of the bracket entry stays pinned. The fixture resolves its
  # tree through realpath first, because the script prints resolved
  # paths and /build of the sandbox is a symlink. The check landed with
  # the deduplication, so no gate run held the double listing (issue
  # 397). The bracket edge landed with the exact comparison of the keep
  # helper, so no gate run held the sidecar loss (issue 414)
  clean-fixture =
    check "clean-fixture"
      [
        pkgs.gnugrep
        pkgs.gnused
      ]
      ''
        set -eu
        mkdir "$PWD/fixture"
        root=$(realpath "$PWD/fixture")
        run=$root/run
        script=${self}/modules/virtualisation/oci-containers/media-servers/scripts/clean.sh
        shows=$root/media/shows
        movies=$root/media/movies
        specials=$root/media/specials
        one="$shows/Show One"
        two="$shows/Show Two"
        s1="$one/Season 1"

        # one removal candidate of the dry run: the output and the log
        # each name it exactly once; a failure names the file
        listed_once() {
          count=$(grep -cF "$2" "$1" || true)
          if test "$count" -ne 1; then
            echo "FAIL listed_once count=$count file=$2 in=$1" >&2
            cat "$1" >&2
            exit 1
          fi
        }

        # one keep file: no output line names it
        listed_never() {
          if grep -qF "$2" "$1"; then
            echo "FAIL listed_never file=$2 in=$1" >&2
            exit 1
          fi
        }

        # one line the output must hold
        holds_line() {
          if ! grep -qF "$2" "$1"; then
            echo "FAIL holds_line missing: $2 in=$1" >&2
            exit 1
          fi
        }

        # the fixture tree: one show with its posters, one show without,
        # three movie folders of which one holds no video and one holds a
        # video name with a bracket group, and one special
        mkdir -p "$s1/extras" "$one/Season 2" "$one/Specials" "$one/extrafanart" \
          "$two/Season 1" "$two/Season 08" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" "$run"
        for f in \
          "$one/banner.jpg" "$one/clearart.png" "$one/fanart.jpg" "$one/poster.jpg" \
          "$one/folder.jpg" "$one/tvshow.nfo" "$one/landscape.jpg" \
          "$one/season01-poster.jpg" "$one/season-specials-poster.png" \
          "$s1/Show One S01E01.mkv" "$s1/Show One S01E01.en.srt" "$s1/Show One S01E01.nfo" \
          "$s1/Show One S01E01-thumb.jpg" "$s1/season.nfo" "$s1/source456.torrent" \
          "$s1/stray.txt" "$s1/extras/inside.bin" "$one/Season 2/stray2.txt" \
          "$one/Specials/Show One S00E01.mkv" "$one/Specials/note.txt" \
          "$one/extrafanart/art.jpg" \
          "$two/tvshow.nfo" "$two/Season 1/Show Two S01E01.mkv" "$two/Season 1/junk.bin" \
          "$two/Season 08/Show Two S08E01.avi" "$two/Season 08/junk8.bin" \
          "$movies/Film One/poster.jpg" "$movies/Film One/clearart.png" \
          "$movies/Film One/disc.png" "$movies/Film One/extrafanart.jpg" \
          "$movies/Film One/folder.jpg" "$movies/Film One/movie.nfo" \
          "$movies/Film One/backdrop.jpg" "$movies/Film One/Film One.mkv" \
          "$movies/Film One/Film One.en.srt" "$movies/Film One/Film One-thumb.jpg" \
          "$movies/Film One/stray.dat" "$movies/Film Two/poster.jpg" "$movies/Film Two/junk.tmp" \
          "$movies/Film Three/Film Three [2004].mkv" "$movies/Film Three/Film Three [2004].nfo" \
          "$movies/Film Three/Film Three [2004]-thumb.jpg" \
          "$movies/Film Three/Film Three [2004].en.srt" "$movies/Film Three/Film Three 2.nfo" \
          "$movies/Film Three/junk.meta" \
          "$specials/Special Film/clearart.png" "$specials/Special Film/poster.jpg" \
          "$specials/Special Film/backdrop.jpg" "$specials/Special Film/movie.nfo" \
          "$specials/Special Film/source.torrent" "$specials/Special Film/Special Film.mp4" \
          "$specials/Special Film/Special Film.srt" "$specials/Special Film/stray.spec"; do
          printf 'x\n' >"$f"
        done

        gone_list=(
          "$one/banner.jpg" "$one/clearart.png" "$one/fanart.jpg"
          "$s1/stray.txt" "$one/Specials/note.txt"
          "$two/Season 1/junk.bin" "$two/Season 08/junk8.bin"
          "$movies/Film One/poster.jpg" "$movies/Film One/clearart.png"
          "$movies/Film One/disc.png" "$movies/Film One/extrafanart.jpg"
          "$movies/Film One/stray.dat" "$movies/Film Three/junk.meta"
          "$specials/Special Film/clearart.png" "$specials/Special Film/poster.jpg"
          "$specials/Special Film/stray.spec"
        )
        kept_list=(
          "$one/poster.jpg" "$one/folder.jpg" "$one/tvshow.nfo" "$one/landscape.jpg"
          "$one/season01-poster.jpg" "$one/season-specials-poster.png"
          "$one/Season 2/stray2.txt" "$one/extrafanart/art.jpg"
          "$s1/Show One S01E01.mkv" "$s1/Show One S01E01.en.srt" "$s1/Show One S01E01.nfo"
          "$s1/Show One S01E01-thumb.jpg" "$s1/season.nfo" "$s1/source456.torrent"
          "$s1/extras/inside.bin"
          "$one/Specials/Show One S00E01.mkv"
          "$two/Season 1/Show Two S01E01.mkv" "$two/Season 08/Show Two S08E01.avi"
          "$movies/Film One/Film One.mkv" "$movies/Film One/Film One.en.srt"
          "$movies/Film One/Film One-thumb.jpg" "$movies/Film One/movie.nfo"
          "$movies/Film One/backdrop.jpg" "$movies/Film One/folder.jpg"
          "$movies/Film Two/poster.jpg" "$movies/Film Two/junk.tmp"
          "$specials/Special Film/Special Film.mp4" "$specials/Special Film/Special Film.srt"
          "$specials/Special Film/backdrop.jpg" "$specials/Special Film/source.torrent"
          # the bracket group keeps its own video, sidecar, thumb, and
          # subtitle, and Film Three 2.nfo matches the [2004] entry as a
          # pattern, so the family reach of a bracket entry stays pinned
          "$movies/Film Three/Film Three [2004].mkv" "$movies/Film Three/Film Three [2004].nfo"
          "$movies/Film Three/Film Three [2004]-thumb.jpg" "$movies/Film Three/Film Three [2004].en.srt"
          "$movies/Film Three/Film Three 2.nfo"
        )

        # the dry run: each candidate is listed once and logged once. The
        # script takes one folder per argument, and the type comes from the
        # path: each show folder, movie folder, and special folder is its
        # own argument
        cd "$run"
        if ! bash "$script" "$one" "$two" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" >"$root/dry.out" 2>&1; then
          echo "FAIL the dry run exited nonzero" >&2
          cat "$root/dry.out" >&2
          exit 1
        fi

        # the season paths carry a doubled slash, because the season glob
        # ends on a slash; the assertions read the normalized copies
        sed "s|//\+|/|g" "$root/dry.out" >"$root/dry.norm"
        sed "s|//\+|/|g" "$run/cleanup.txt" >"$root/log.norm"
        for gone in "''${gone_list[@]}"; do
          listed_once "$root/dry.norm" "$gone"
          listed_once "$root/log.norm" "$gone"
        done
        for kept in "''${kept_list[@]}"; do
          listed_never "$root/dry.norm" "$kept"
        done

        # the season number pads in bash: a one-digit season and a
        # leading-zero season both name their two-digit poster
        holds_line "$root/dry.norm" "expected 'season01-poster.jpg/png'"
        holds_line "$root/dry.norm" "expected 'season08-poster.jpg/png'"

        # a directory is never a removal candidate
        listed_never "$root/dry.norm" "$s1/extras"
        listed_never "$root/dry.norm" "$one/extrafanart"

        # a folder without a video keeps its files
        holds_line "$root/dry.norm" "No video file found in $movies/Film Two"

        # the wet run: the gone files are gone, the kept files stay
        mkdir "$root/run2"
        cd "$root/run2"
        if ! bash "$script" --wet "$one" "$two" "$movies/Film One" "$movies/Film Two" \
          "$movies/Film Three" "$specials/Special Film" >"$root/wet.out" 2>&1; then
          echo "FAIL the wet run exited nonzero" >&2
          cat "$root/wet.out" >&2
          exit 1
        fi
        for gone in "''${gone_list[@]}"; do
          if test -e "$gone"; then
            echo "FAIL survived the wet run: $gone" >&2
            exit 1
          fi
        done
        for kept in "''${kept_list[@]}"; do
          if ! test -e "$kept"; then
            echo "FAIL lost in the wet run: $kept" >&2
            exit 1
          fi
        done
      '';

  # the scan set of the CVE report: a pinned image carries a digest or a
  # version tag, and a version tag holds a digit; everything else floats,
  # and the pinning work itself rides item C3 of issue 350
  pinned-images =
    report "pinned-images"
      [
        pkgs.gnugrep
        pkgs.gnused
      ]
      ''
        grep -rhoE 'image = "[^"]+"' ${self}/modules/virtualisation \
          | sed -e 's/^image = "//' -e 's/"$//' \
          | grep -E '(@sha256|:[0-9])' \
          | sort -u > "$out"
      '';

  # the duplicate-sentence report of the audit: one fact lives in one home
  # (docs/design.md, Documentation Law item 9), so the report names each
  # sentence of twelve words or more that two files of the documentation
  # tree hold word for word, after case and punctuation fold away. It
  # reports and never fails, because a repetition needs a reader to judge
  # whether an exception applies (issue 366, pass A3)
  doc-duplicates =
    report "doc-duplicates"
      [
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
      ''
        cd "${self}"
        for f in docs/*.md AGENTS.md README.md; do
          case "$f" in docs/decisions.md) continue ;; esac
          tr '\n' ' ' < "$f" \
            | grep -oE '[^.]+\.' \
            | awk -v file="$f" 'NF >= 12 {
                s = tolower($0)
                gsub(/[^a-z0-9 ]/, " ", s)
                gsub(/ +/, " ", s)
                print s "\t" file
              }'
        done \
          | sort -u \
          | awk -F'\t' '
              { files[$1] = files[$1] " " $2 }
              END {
                for (s in files) {
                  n = split(files[s], a, " ")
                  if (n > 1) print s ":" files[s]
                }
              }' > "$out"
      '';
}
