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
        mkdir -p "$playlists" "$jellyfin/anime" "$jellyfin/movies" "$library/anime" "$library/movies" "$root/empty"
        printf '<Item/>\n' >"$jellyfin/anime/playlist.xml"
        printf '<Item/>\n' >"$jellyfin/movies/playlist.xml"
        printf 'one\n' >"$library/anime/Show S01E01.mkv"
        printf 'two\n' >"$library/movies/Film.mkv"
        printf '# a comment line\n%s\n' "$library/anime/Show S01E01" >"$playlists/anime.txt"
        printf '%s\n' "$library/movies/Film" >"$playlists/movies.txt"
        sed "s|/mnt/jellyfin/data/data/playlists|$jellyfin|" \
          ${self}/modules/virtualisation/oci-containers/media-servers/scripts/playlist_generator.sh \
          >"$root/playlist_generator.sh"

        # the playlist of one name holds exactly one item, and the item
        # carries the library file of its manifest line
        one_item() {
          count=$(xmlstarlet sel -t -v 'count(/Item/PlaylistItems/PlaylistItem)' "$jellyfin/$1/playlist.xml")
          test "$count" = 1
          path=$(xmlstarlet sel -t -v '/Item/PlaylistItems/PlaylistItem/Path' "$jellyfin/$1/playlist.xml")
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
        one_item anime "$library/anime/Show S01E01.mkv"
        one_item movies "$library/movies/Film.mkv"

        # the absolute directory of the timer: a rerun replaces the items
        # instead of appending them
        bash "$root/playlist_generator.sh" "$playlists"
        one_item anime "$library/anime/Show S01E01.mkv"
        one_item movies "$library/movies/Film.mkv"

        # a relative manifest file from the parent directory
        bash "$root/playlist_generator.sh" playlists/anime.txt
        one_item anime "$library/anime/Show S01E01.mkv"

        # no argument: the manifests of the current directory
        cd "$playlists"
        bash "$root/playlist_generator.sh"
        one_item anime "$library/anime/Show S01E01.mkv"
        one_item movies "$library/movies/Film.mkv"

        # a relative empty directory: the run fails and names the anchored
        # directory
        cd "$root"
        if bash "$root/playlist_generator.sh" empty >"$root/empty.out" 2>&1; then
          echo "the empty directory did not fail"
          exit 1
        fi
        grep -Fq "No .txt files found in $root/empty" "$root/empty.out"
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
