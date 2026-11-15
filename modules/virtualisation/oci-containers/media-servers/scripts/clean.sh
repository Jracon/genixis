#!/usr/bin/env bash
# fail on any error
set -euo pipefail

# required for season poster check
shopt -s extglob

# globals
DRY=true
SHOWS_KEEP=("backdrop.jpg" "backdrop.png" "folder.url" "landscape.png" "landscape.jpg" "season.nfo" "tvshow.nfo" "folder.png" "folder.jpg" "poster.jpg" "logo.png" "logo.svg" "season*poster.jpg" "season*poster.png" "season*poster.url" "season*.torrent" "source*.torrent")
MOVIES_KEEP=("backdrop.jpg" "folder.jpg" "folder.png" "folder.url" "landscape.png" "landscape.jpg" "logo.png" "logo.svg" "movie.nfo" "source.torrent")
SPECIALS_KEEP=("backdrop.jpg" "folder.jpg" "folder.png" "folder.url" "landscape.png" "landscape.jpg" "movie.nfo" "source.torrent")

# the removal log lands in the current directory, never inside a cleaned tree
cleanup_log="$PWD/cleanup.txt"

check_season_poster() {
	local show_dir="$1"
	local subfolder_name="$2"

	local season_key
	local poster_file

	# normalize subfolder name into poster filename pattern
	case "$subfolder_name" in
	[Ss]pecials)
		season_key="season-specials"
		;;
	[Ss]eason*([[:space:]])*([0-9]))
		# extract season number
		season_num=$(echo "$subfolder_name" | grep -oE '[0-9]+' | awk '{printf "%02d", $1}')
		season_key="season${season_num}"
		;;
	*)

		season_key=$(echo "$subfolder_name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
		;;
	esac

	# check for matching poster existence
	for ext in jpg png; do
		poster_file="$show_dir/${season_key}-poster.$ext"
		if [[ -f "$poster_file" ]]; then
			return 0
		fi
	done

	echo "    [WARN] Missing poster for subfolder '$subfolder_name' → expected '${season_key}-poster.jpg/png'"
	return 1
}

remove_file() {
	local file="$1"
	if $DRY; then
		echo "    [--wet] Would remove: $file"
		echo "$file" >>"$cleanup_log"
	else
		echo "    Removing: $file"

		# remove directories recursively, files normally
		if [[ -d $file ]]; then
			rm -r "$file"
		else
			rm "$file"
		fi
	fi
}

cleanup_show() {
	local folder="$1"
	echo "Cleaning $folder"

	# required for wildcard matching
	shopt -s nullglob

	# define allowed files
	root_keep=("season.nfo" "folder.png" "folder.jpg" "logo.png")
	allowed=("${root_keep[@]}" "${SHOWS_KEEP[@]}")

	# remove unallowed files
	for file in "$folder"/*; do
		# skip irregular files
		[[ -f "$file" ]] || continue

		# get file basename
		fname=$(basename "$file")

		keep=false

		# mark allowed files to keep
		# exact matching
		for a in "${allowed[@]}"; do
			[[ "$fname" == "$a" ]] && keep=true && break
		done

		# glob matching
		for pat in "${allowed[@]}"; do
			# shellcheck disable=SC2053
			[[ "$fname" == $pat ]] && keep=true && break
		done

		# remove unallowed files
		if ! $keep; then
			remove_file "$file"
		fi
	done

	# parse show subfolders (seasons)
	for subfolder in "$folder"/*/; do
		# skip non-directories
		[[ -d "$subfolder" ]] || continue

		# get subfolder basename
		subname=$(basename "$subfolder")

		# Check for matching season poster in show root
		check_season_poster "$folder" "$subname" || true

		# check for video file existence
		video_files=("$subfolder"/*.mkv "$subfolder"/*.mp4 "$subfolder"/*.avi)
		[[ ${#video_files[@]} -eq 0 ]] && continue

		# set initial allowed list
		allowed=("season.nfo" "source*.torrent")
		for video in "${video_files[@]}"; do
			base=$(basename "$video")
			name="${base%.*}"

			allowed+=("$base")
			allowed+=("$name.eng.srt" "$name.en.srt" "$name.en.sdh.srt" "$name.eng.sdh.srt" "$name.en.srt" "$name.en.cc.srt" "$name.srt" "$name.ass" "$name.en.vtt")
			allowed+=("$name.nfo")
			allowed+=("$name-thumb.jpg")
			allowed+=("$name.xml")
			allowed+=("$name.trickplay")
		done

		# remove unwanted files in subfolder
		for file in "$subfolder"/*; do
			fname=$(basename "$file")

			keep=false

			# exact matching
			for a in "${allowed[@]}"; do
				[[ "$fname" == "$a" ]] && keep=true && break
			done

			# pattern matching
			for pat in "${allowed[@]}"; do
				# shellcheck disable=SC2053
				[[ "$fname" == $pat ]] && keep=true && break
			done

			if ! $keep; then
				remove_file "$file"
			fi
		done
	done

	# unset null globbing
	shopt -u nullglob
}

cleanup_single() {
	local folder="$1"
	local type="$2" # "movie" or "special"

	echo "Cleaning $folder"

	# get keep list
	local keep_list
	if [[ "$type" == "movie" ]]; then
		keep_list=("${MOVIES_KEEP[@]}")
	else
		keep_list=("${SPECIALS_KEEP[@]}")
	fi

	# find main video file
	local video=""
	for extension in mkv mp4 avi; do
		for file in "$folder"/*."$extension"; do
			[[ -f "$file" ]] || continue
			video="$file"
			break 2
		done
	done

	# return if no video file found
	[[ -z "$video" ]] && echo "  No video file found in $folder" && return

	# get the video basename and extension
	local base
	base=$(basename "$video")
	local name="${base%.*}"

	# Allowed files for this folder
	allowed=("${keep_list[@]}" "$name.nfo" "$name-thumb.jpg")
	allowed+=("$name.eng.srt" "$name.en.srt" "$name.en.sdh.srt" "$name.eng.sdh.srt" "$name.en.srt" "$name.en.cc.srt" "$name.srt" "$name.ass" "$name.en.vtt")

	# remove unwanted files
	for file in "$folder"/*; do
		# if the file is irregular, skip
		[[ -f "$file" ]] || continue

		# get file basename and skip if it is the video file
		local fname
		fname=$(basename "$file")
		[[ "$fname" == "$base" ]] && continue

		# mark allowed files to keep
		local keep=false
		for a in "${allowed[@]}"; do
			[[ "$fname" == "$a" ]] && keep=true && break
		done

		# delete unallowed files
		if ! $keep; then
			remove_file "$file"
		fi
	done
}

# print usage for incorrect argument count
if [[ $# -lt 1 ]]; then
	echo "Usage: $0 /path/to/media/folder [--wet]"
	exit 1
fi

# initialize media path array
MEDIA_PATHS=()

# iterate args, set --wet and MEDIA_PATHS
for arg in "$@"; do
	case "$arg" in
	--wet)
		DRY=false
		;;
	*)
		MEDIA_PATHS+=("$(realpath "$arg")")
		;;
	esac
done

# ensure a media path argument is actually passed
if [[ ${#MEDIA_PATHS[@]} -eq 0 ]]; then
	echo "Error: must provide at least one media path"
	exit 1
fi

touch "$cleanup_log"

# iterate media paths
for MEDIA_PATH in "${MEDIA_PATHS[@]}"; do
	# warn if path is not directory
	if [[ ! -d "$MEDIA_PATH" ]]; then
		echo "Error: $MEDIA_PATH is not a directory"
		continue
	fi

	# process path
	if [[ "$MEDIA_PATH" == *"/shows"* ]]; then
		cleanup_show "$MEDIA_PATH"
	elif [[ "$MEDIA_PATH" == *"/specials"* ]]; then
		cleanup_single "$MEDIA_PATH" "special"
	elif [[ "$MEDIA_PATH" == *"/movies"* ]]; then
		cleanup_single "$MEDIA_PATH" "movie"
	else
		echo "Could not determine type from path: $MEDIA_PATH"
		exit 1
	fi
done
