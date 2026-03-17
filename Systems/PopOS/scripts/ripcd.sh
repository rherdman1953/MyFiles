#!/bin/bash

cd "$HOME" || exit 1

OUTPUT_DIR="$HOME/out/rip"

echo "Starting secure FLAC rip..."
echo "Output directory: $OUTPUT_DIR"
echo ""

# Make sure output directory exists
mkdir -p "$OUTPUT_DIR"

abcde -d /dev/sr0 -V

echo ""
echo "Rip complete."
echo "Files saved to: $OUTPUT_DIR"
echo "You can now tag/verify in Picard if desired."
