#!/usr/bin/env bash

# Regenerates the Jellyfin playlist XML files from the txt manifests.
# Usage: playlist_generator.sh [manifests directory | one manifest file]
# Without an argument, it reads the manifests of the current directory.
# The log lands beside the manifests.

target=${1:-$PWD}

if [[ -f "$target" ]]; then
	manifests_directory=$(dirname "$target")
else
	manifests_directory=$target
fi

logfile="$manifests_directory/playlist_generator.log"
if [[ -f "$logfile" ]]; then
	rm "$logfile"
fi

# valid media file extensions
extensions=("avi" "cbz" "epub" "mkv" "mp3" "mp4" "webm")

generate_playlist() {
	local playlist_manifest=$1
	local playlist_manifest_basename
	local playlist_name
	local playlist_path
	local playlist_file

	# extract the filename and remove the extension to get the playlist name
	playlist_manifest_basename=$(basename "$playlist_manifest")
	playlist_name="${playlist_manifest_basename%.*}"
	echo "$playlist_name"
	echo "$playlist_name" >>"$logfile"

	# initialize the path to the playlist file and create it if it does not exist
	playlist_path="/mnt/jellyfin/data/data/playlists/$playlist_name"
	playlist_file="$playlist_path/playlist.xml"

	# ensure PlaylistItems exists
	if ! xmlstarlet sel -t -v "count(/Item/PlaylistItems)" "$playlist_file" | grep -q '^1$'; then
		xmlstarlet ed --inplace \
			-s "/Item" -t elem -n "PlaylistItems" -v "" \
			"$playlist_file"
	fi

	# remove any existing PlaylistItem tags from the playlist file
	xmlstarlet ed --inplace -d "//Item/PlaylistItems/PlaylistItem" "$playlist_file"

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
			existing_file=""
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

				# insert a new PlaylistItem with the file path into the XML
				xmlstarlet ed --inplace -s "//Item/PlaylistItems" -t elem -n "PlaylistItem" \
					-v "" -s "//Item/PlaylistItems/PlaylistItem[last()]" -t elem -n "Path" \
					-v "$existing_file" "$playlist_path/playlist.xml"
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
