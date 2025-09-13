#!/bin/bash
# Ultra-fast SoilGrids download using aria2 with direct COG access
# This bypasses VRT and downloads the actual Cloud-Optimized GeoTIFFs

OUTDIR="/home/olier/ellenberg/data/soilgrids_250m_global"
LOGFILE="$OUTDIR/aria2_ultra.log"
mkdir -p "$OUTDIR"

echo "=====================================" | tee "$LOGFILE"
echo "ULTRA-FAST ARIA2 DOWNLOAD" | tee -a "$LOGFILE"
echo "=====================================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Check aria2
if ! command -v aria2c &> /dev/null; then
    echo "ERROR: aria2c not installed!" | tee -a "$LOGFILE"
    exit 1
fi

echo "✓ aria2c version: $(aria2c --version | head -1)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Properties and depths
PROPERTIES=("phh2o" "soc" "clay" "sand" "cec" "nitrogen" "bdod")
DEPTHS=("0-5cm" "5-15cm" "15-30cm" "30-60cm" "60-100cm" "100-200cm")

# Build URLs using the pattern we know works
BASE_URL="https://files.isric.org/soilgrids/latest/data"
ARIA2_INPUT="$OUTDIR/download_list.txt"
> "$ARIA2_INPUT"

echo "Building download list..." | tee -a "$LOGFILE"

for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        # The VRT files point to the actual data
        # We can construct the URL pattern
        vrt_url="${BASE_URL}/${prop}/${prop}_${depth}_mean.vrt"
        
        # For now, let's try the direct mean files
        # These might be large COGs that we can download directly
        tif_url="${BASE_URL}/${prop}/${prop}_${depth}_mean.tif"
        
        # Add to download list
        echo "$tif_url" >> "$ARIA2_INPUT"
        echo "  out=${prop}_${depth}_global_250m.tif" >> "$ARIA2_INPUT"
        echo "  Added: ${prop}_${depth}" | tee -a "$LOGFILE"
    done
done

TOTAL_FILES=$((${#PROPERTIES[@]} * ${#DEPTHS[@]}))
echo "" | tee -a "$LOGFILE"
echo "Total files to download: $TOTAL_FILES" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Start time
START_TIME=$(date +%s)

echo "Starting download with maximum parallelization..." | tee -a "$LOGFILE"
echo "=====================================" | tee -a "$LOGFILE"

# Run aria2 with MAXIMUM speed settings for 10Gbps
aria2c \
    --input-file="$ARIA2_INPUT" \
    --dir="$OUTDIR" \
    --max-connection-per-server=16 \
    --split=16 \
    --min-split-size=1M \
    --max-concurrent-downloads=6 \
    --continue=true \
    --auto-file-renaming=false \
    --file-allocation=none \
    --max-tries=5 \
    --retry-wait=2 \
    --timeout=600 \
    --connect-timeout=60 \
    --lowest-speed-limit=100K \
    --piece-length=1M \
    --allow-overwrite=true \
    --console-log-level=notice \
    --summary-interval=5 \
    --human-readable=true \
    --download-result=full \
    --log="$OUTDIR/aria2.log" \
    2>&1 | tee -a "$LOGFILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "" | tee -a "$LOGFILE"
echo "=====================================" | tee -a "$LOGFILE"
echo "DOWNLOAD COMPLETE" | tee -a "$LOGFILE"
echo "=====================================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Check results
SUCCESS_COUNT=$(ls -1 "$OUTDIR"/*.tif 2>/dev/null | wc -l)
echo "Successfully downloaded: $SUCCESS_COUNT/$TOTAL_FILES files" | tee -a "$LOGFILE"
echo "Time elapsed: $((ELAPSED / 60)) minutes $((ELAPSED % 60)) seconds" | tee -a "$LOGFILE"

if [ $SUCCESS_COUNT -gt 0 ]; then
    TOTAL_SIZE=$(du -sh "$OUTDIR" | cut -f1)
    echo "Total size: $TOTAL_SIZE" | tee -a "$LOGFILE"
    
    # Calculate speed
    SIZE_BYTES=$(du -sb "$OUTDIR" | cut -f1)
    SPEED_MBPS=$((SIZE_BYTES * 8 / ELAPSED / 1000000))
    echo "Average speed: ${SPEED_MBPS} Mbps" | tee -a "$LOGFILE"
fi

# List any failed downloads
echo "" | tee -a "$LOGFILE"
if [ $SUCCESS_COUNT -lt $TOTAL_FILES ]; then
    echo "Failed downloads:" | tee -a "$LOGFILE"
    for prop in "${PROPERTIES[@]}"; do
        for depth in "${DEPTHS[@]}"; do
            if [ ! -f "$OUTDIR/${prop}_${depth}_global_250m.tif" ]; then
                echo "  ✗ ${prop}_${depth}" | tee -a "$LOGFILE"
            fi
        done
    done
fi

echo "" | tee -a "$LOGFILE"
echo "Log saved to: $LOGFILE" | tee -a "$LOGFILE"