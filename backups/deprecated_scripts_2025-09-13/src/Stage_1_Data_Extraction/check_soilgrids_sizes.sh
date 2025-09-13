#!/bin/bash
# Check file sizes for SoilGrids 1km data

echo "Checking SoilGrids 1km file sizes..."
echo "====================================="
echo ""

BASE_URL="https://files.isric.org/soilgrids/latest/data_aggregated/1000m"

# Properties to check
PROPERTIES=(
    "phh2o"
    "soc"
    "clay"
    "sand"
    "cec"
    "nitrogen"
    "bdod"
)

# Just check 0-5cm depth for each
DEPTH="0-5cm"

TOTAL_SIZE=0

echo "Property    | File Size (MB)"
echo "------------|---------------"

for prop in "${PROPERTIES[@]}"; do
    url="$BASE_URL/$prop/${prop}_${DEPTH}_mean_1000.tif"
    
    # Get file size via HEAD request
    size_bytes=$(curl -sI "$url" | grep -i content-length | awk '{print $2}' | tr -d '\r')
    
    if [ -n "$size_bytes" ]; then
        size_mb=$((size_bytes / 1048576))
        TOTAL_SIZE=$((TOTAL_SIZE + size_bytes))
        printf "%-11s | %d MB\n" "$prop" "$size_mb"
    else
        printf "%-11s | Unknown\n" "$prop"
    fi
done

echo ""
echo "Estimated total for all properties and depths:"
echo "  Single depth: $((TOTAL_SIZE / 1048576)) MB"
echo "  All 3 depths: $((TOTAL_SIZE * 3 / 1048576)) MB (~$((TOTAL_SIZE * 3 / 1073741824)) GB)"
echo "  All 6 depths: $((TOTAL_SIZE * 6 / 1048576)) MB (~$((TOTAL_SIZE * 6 / 1073741824)) GB)"

echo ""
echo "Download time estimates (at different speeds):"
echo "  1 MB/s:  $((TOTAL_SIZE * 3 / 1048576 / 60)) minutes for 3 depths"
echo "  5 MB/s:  $((TOTAL_SIZE * 3 / 1048576 / 300)) minutes for 3 depths"
echo "  10 MB/s: $((TOTAL_SIZE * 3 / 1048576 / 600)) minutes for 3 depths"