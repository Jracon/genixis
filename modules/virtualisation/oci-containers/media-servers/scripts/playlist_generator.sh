#!/usr/bin/env bash

# Regenerates the Jellyfin playlist XML files from the txt manifests.
# Usage: playlist_generator.sh [manifests directory | one manifest file]
# Without an argument, it reads the manifests of the current directory.
# PLAYLIST_DIRECTORY overrides the playlists root of the Jellyfin data tree.
# The default is the playlists path of the linuxserver image layout.
# The log lands beside the manifests.

target=${1:-$PWD}

# anchor a relative target to the working directory of the caller: the script
# enters the manifests directory below, and the log path and the manifest glob
# must resolve against the base the caller gave, not against the directory
# the script enters
case $target in
	""|/*) ;;
	*) target=$PWD/$target ;;
esac

if [[ -f "$target" ]]; then
	manifests_directory=$(dirname "$target")
else
	manifests_directory=$target
fi

# resolve relative manifest lines against the manifests directory, the base
# that the working directory of the old timer service gave them
cd "$manifests_directory" || exit 1

logfile="$manifests_directory/playlist_generator.log"
if [[ -f "$logfile" ]]; then
	rm "$logfile"
fi

# the playlists root of the Jellyfin data tree: the linuxserver image
# layout by default, because the deployed Jellyfin runs that image.
# PLAYLIST_DIRECTORY overrides the root for another image layout.
playlists_root=${PLAYLIST_DIRECTORY:-/mnt/jellyfin/data/data/playlists}

# one header line per run: a reader of the log sees which playlists root
# the run wrote to
echo "playlist directory: $playlists_root" >>"$logfile"

# valid media file extensions
extensions=("avi" "cbz" "epub" "mkv" "mp3" "mp4" "webm")

generate_playlist() {
	local playlist_manifest=$1
	local playlist_manifest_basename
	local playlist_name
	local playlist_path
	local playlist_file
	local existing_file
	local -a resolved_paths=()

	# extract the filename and remove the extension to get the playlist name
	playlist_manifest_basename=$(basename "$playlist_manifest")
	playlist_name="${playlist_manifest_basename%.*}"
	echo "$playlist_name"
	echo "$playlist_name" >>"$logfile"

	# initialize the path to the playlist file and create it if it does not exist
	playlist_path="$playlists_root/$playlist_name"
	playlist_file="$playlist_path/playlist.xml"

	# loop through each line of the manifest
	while IFS= read -r line || [[ -n "$line" ]]; do
		# add playlist cover image
		if [[ -n "$line" && "$line" == !* ]]; then
			poster="${line#!}"

			cp "$poster" "$playlist_path"
			chown 1000:1000 -R "$playlist_path"
		fi

		# skip empty lines
		if [[ -n "$line" && ! "$line" =~ ^# && ! "$line" == !* ]]; then
			potential_files=()

			# search for files with matching extensions
			for extension in "${extensions[@]}"; do
				matches=("$line"*."$extension")

				# Add found matches to the array if they exist
				for match in "${matches[@]}"; do
					if [[ -f "$match" ]]; then
						if [[ "$line" =~ S[0-9]{2}E[0-9]{2}$ ]]; then
							if [[ "$match" =~ S[0-9]{2}E[0-9]{2}[^0-9] ]]; then
								potential_files+=("$match")
							fi
						else
							potential_files+=("$match")
						fi
					fi
				done
			done

			# handle potential files
			if [[ ${#potential_files[@]} -eq 1 ]]; then
				# exactly one match
				existing_file="${potential_files[0]}"
				echo -e "  $existing_file added successfully!" >>"$logfile"

				# properly escape XML characters
				existing_file=$(echo "$existing_file" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&apos;/g" -e 's/"/\&quot;/g')

				# collect the resolved entry: the playlist file is written
				# once, after the loop resolved every entry
				resolved_paths+=("$existing_file")
			elif [[ ${#potential_files[@]} -gt 1 ]]; then
				# multiple matches
				echo -e "\n  ERROR: Multiple video files found for $line:"
				echo -e "\n  ERROR: Multiple video files found for $line:" >>"$logfile"
				printf '  %s\n' "${potential_files[@]}"
				printf '  %s\n' "${potential_files[@]}" >>"$logfile"
				echo "  Exiting"
			else
				# no matches
				echo "  ERROR: No valid file found for $line"
				echo "  ERROR: No valid file found for $line" >>"$logfile"
				echo "  Exiting"
			fi
		fi
	done <"$playlist_manifest"

	# write the playlist file once, after every entry is resolved: one
	# xmlstarlet process rewrites the file one time, whatever the entry
	# count. The delete of PlaylistItems and its rebuild in the same pass
	# replace the items of the previous run.
	local -a write_ops=(
		--inplace
		-d '//Item/PlaylistItems'
		-s '/Item' -t elem -n 'PlaylistItems' -v ''
	)
	for existing_file in "${resolved_paths[@]}"; do
		write_ops+=(
			-s '//Item/PlaylistItems' -t elem -n 'PlaylistItem' -v ''
			-s '//Item/PlaylistItems/PlaylistItem[last()]' -t elem -n 'Path' -v "$existing_file"
		)
	done
	xmlstarlet ed "${write_ops[@]}" "$playlist_file"

	echo -e "  $playlist_name finished successfully!\n"
	echo "" >>"$logfile"
}

if [[ -f "$target" ]]; then
	generate_playlist "$target"
	exit 0
fi

# iterate through each .txt file in the manifests directory
for playlist_manifest in "$manifests_directory"/*.txt; do
	# if there are no .txt files present
	if [[ ! -f "$playlist_manifest" ]]; then
		echo "No .txt files found in $manifests_directory"
		echo "Exiting"
		exit 1
	fi

	dt=$(date '+%d/%m/%Y %H:%M:%S')
	echo "$dt" >>"$logfile"

	generate_playlist "$playlist_manifest"
done
