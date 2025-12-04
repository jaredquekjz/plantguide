#!/bin/bash
# convert_to_webp.sh
#
# Converts PNG heatmaps to WebP format for optimal web delivery
#
# Usage:
#   ./convert_to_webp.sh

OUTPUT_DIR="/home/olier/ellenberg/shipley_checks/stage4/distribution_maps"

cd "$OUTPUT_DIR" || exit 1

echo "Converting PNGs to WebP..."
echo "Directory: $OUTPUT_DIR"

# Count PNGs
PNG_COUNT=$(ls -1 *.png 2>/dev/null | wc -l)
echo "PNG files to convert: $PNG_COUNT"

if [ "$PNG_COUNT" -eq 0 ]; then
    echo "No PNG files found."
    exit 0
fi

# Check if cwebp is available
if ! command -v cwebp &> /dev/null; then
    echo "cwebp not found. Installing webp..."
    sudo apt-get install -y webp
fi

# Convert with progress
CONVERTED=0
FAILED=0

for f in *.png; do
    if [ -f "$f" ]; then
        OUTPUT="${f%.png}.webp"
        if cwebp -q 80 "$f" -o "$OUTPUT" -quiet 2>/dev/null; then
            ((CONVERTED++))
            # Remove PNG after successful conversion
            rm "$f"
        else
            echo "Failed: $f"
            ((FAILED++))
        fi

        # Progress every 500 files
        if [ $((CONVERTED % 500)) -eq 0 ]; then
            echo "  Converted: $CONVERTED / $PNG_COUNT"
        fi
    fi
done

echo ""
echo "=== Conversion Complete ==="
echo "Converted: $CONVERTED"
echo "Failed: $FAILED"

# Size summary
WEBP_COUNT=$(ls -1 *.webp 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh . | cut -f1)
echo "WebP files: $WEBP_COUNT"
echo "Total size: $TOTAL_SIZE"
