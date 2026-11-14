#!/bin/bash

# Input directory is the first argument
INPUT_DIR="$1"

# Check if input directory was provided
if [ -z "$INPUT_DIR" ]; then
	echo "Usage: $0 /path/to/input_directory"
	exit 1
fi

# Remove trailing slash if present
INPUT_DIR="${INPUT_DIR%/}"

# Output directory (prepended with 'cropped')
OUTPUT_DIR="$(dirname "$INPUT_DIR")/cropped$(basename "$INPUT_DIR")"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Loop through all .jpeg files in the input directory
for file in "$INPUT_DIR"/*.jpeg; do
	filename=$(basename "$file")
	magick "$file" -crop 2111x3165+114+0 +repage "$OUTPUT_DIR/$filename"
	echo "Cropped $filename -> $OUTPUT_DIR/$filename"
done

echo "All images cropped and saved to: $OUTPUT_DIR"
