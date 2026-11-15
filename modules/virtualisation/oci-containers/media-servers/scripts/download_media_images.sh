#!/usr/bin/env bash

# Recursively find .url files, fetch images, and save them as .jpg or .png
set -euo pipefail

# Base directory (use current directory if none provided)
BASE_DIR="${1:-.}"

# Find all .url files recursively
find "$BASE_DIR" -type f -name "*.url" | while read -r urlfile; do
	# Read the URL from the file (ignore blank lines or comments)
	url=$(grep -Eo 'https?://[^ ]+' "$urlfile" | head -n 1)

	if [[ -z "$url" ]]; then
		echo "Skipping $(realpath "$urlfile") (no valid URL found)"
		continue
	fi

	echo "Processing: $(realpath "$urlfile") ($url)"

	# Create a temporary file for download
	tmpfile=$(mktemp)

	# Download file with curl
	curl -sL \
		-H "Accept: image/avif,image/webp,image/apng,image/*,*/*;q=0.8" \
		-H "Accept-Language: en-US,en;q=0.9" \
		-H "Referer: https://theposterdb.com/" \
		-H "Cache-Control: no-cache" \
		-H "Pragma: no-cache" \
		-H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" \
		"$url" -o "$tmpfile"

	# Determine file type
	filetype=$(file --mime-type -b "$tmpfile")

	case "$filetype" in
	image/jpeg)
		newext="jpg"
		;;
	image/png)
		newext="png"
		;;
	*)
		echo "  Unsupported type: $filetype — dumping response snippet:"
		head -c 500 "$tmpfile"
		echo -e "\n--- END OF DUMP ---"
		continue
		;;
	esac

	# Build output filename (same path, replace .url with correct extension)
	outfile="${urlfile%.url}.$newext"

	# Remove any existing jpg/png with same base name
	find "$(dirname "$outfile")" -maxdepth 1 -type f \
		\( -name "$(basename "${outfile%.*}").jpg" -o -name "$(basename "${outfile%.*}").png" \) \
		-not -name "$(basename "$outfile")" \
		-exec rm -f {} +

	# Move downloaded file to final destination
	mv "$tmpfile" "$outfile"

	# fix ownership
	chown 1000:1000 "$outfile"

	echo "  -> $(realpath "$outfile")"

	sleep 2
done
