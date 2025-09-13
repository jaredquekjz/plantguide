#!/bin/bash
# Bulk download SoilGrids using aria2 with aggressive parallelization
# Optimized for 10Gbps connection to bypass per-connection throttling

OUTDIR="/home/olier/ellenberg/data/soilgrids_250m_global"
LOGFILE="$OUTDIR/aria2_download.log"
mkdir -p "$OUTDIR"

echo "=========================================" | tee "$LOGFILE"
echo "ARIA2 BULK DOWNLOAD - SOILGRIDS 250m" | tee -a "$LOGFILE"
echo "Using aggressive parallelization" | tee -a "$LOGFILE"
echo "=========================================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Properties and depths
PROPERTIES=("phh2o" "soc" "clay" "sand" "cec" "nitrogen" "bdod")
DEPTHS=("0-5cm" "5-15cm" "15-30cm" "30-60cm" "60-100cm" "100-200cm")

# First, try to find direct download URLs (if COGs exist)
echo "Checking for direct download URLs..." | tee -a "$LOGFILE"

# Create aria2 input file
ARIA2_INPUT="$OUTDIR/aria2_urls.txt"
> "$ARIA2_INPUT"

TOTAL_FILES=0
for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        echo "Checking $prop $depth..." | tee -a "$LOGFILE"
        
        # Try different possible direct URLs
        URLS=(
            "https://files.isric.org/soilgrids/latest/data/${prop}/${prop}_${depth}_mean_250m.tif"
            "https://files.isric.org/soilgrids/latest/data/${prop}/${prop}_${depth}_mean.tif"
            "https://files.isric.org/soilgrids/latest/data_250m/${prop}/${prop}_${depth}_mean.tif"
        )
        
        FOUND=0
        for url in "${URLS[@]}"; do
            # Quick check if URL exists (timeout after 2 seconds)
            if timeout 2 curl -sI "$url" 2>/dev/null | grep -q "200 OK\|206 Partial"; then
                echo "  ✓ Found: $url" | tee -a "$LOGFILE"
                # Add to aria2 input file
                echo "$url" >> "$ARIA2_INPUT"
                echo "  out=${prop}_${depth}_global_250m.tif" >> "$ARIA2_INPUT"
                FOUND=1
                TOTAL_FILES=$((TOTAL_FILES + 1))
                break
            fi
        done
        
        if [ $FOUND -eq 0 ]; then
            echo "  ✗ No direct URL found for $prop $depth" | tee -a "$LOGFILE"
            # Fall back to VRT approach - we'll handle this separately
        fi
    done
done

echo "" | tee -a "$LOGFILE"
echo "Found $TOTAL_FILES direct download URLs" | tee -a "$LOGFILE"

if [ $TOTAL_FILES -gt 0 ]; then
    echo "" | tee -a "$LOGFILE"
    echo "Starting aria2 download with aggressive settings..." | tee -a "$LOGFILE"
    echo "=========================================" | tee -a "$LOGFILE"
    
    # Run aria2 with maximum optimization for your 10Gbps connection
    aria2c \
        --input-file="$ARIA2_INPUT" \
        --dir="$OUTDIR" \
        --max-connection-per-server=16 \
        --split=16 \
        --min-split-size=5M \
        --max-concurrent-downloads=4 \
        --continue=true \
        --auto-file-renaming=false \
        --file-allocation=none \
        --console-log-level=notice \
        --summary-interval=10 \
        --download-result=full \
        --log="$OUTDIR/aria2_detailed.log" \
        --log-level=info \
        2>&1 | tee -a "$LOGFILE"
    
    echo "" | tee -a "$LOGFILE"
    echo "Download complete!" | tee -a "$LOGFILE"
else
    echo "" | tee -a "$LOGFILE"
    echo "No direct URLs found. Falling back to tile-based approach..." | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    # Alternative: Download VRT files and extract tile URLs
    echo "This would require downloading individual tiles from VRT metadata" | tee -a "$LOGFILE"
    echo "For global coverage, this means downloading thousands of tiles" | tee -a "$LOGFILE"
fi

# Summary
echo "" | tee -a "$LOGFILE"
echo "=========================================" | tee -a "$LOGFILE"
echo "DOWNLOAD SUMMARY" | tee -a "$LOGFILE"
echo "=========================================" | tee -a "$LOGFILE"

SUCCESS_COUNT=$(ls -1 "$OUTDIR"/*.tif 2>/dev/null | wc -l)
echo "Successfully downloaded: $SUCCESS_COUNT files" | tee -a "$LOGFILE"

if [ $SUCCESS_COUNT -gt 0 ]; then
    TOTAL_SIZE=$(du -sh "$OUTDIR" | cut -f1)
    echo "Total size: $TOTAL_SIZE" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "Check log for details: $LOGFILE" | tee -a "$LOGFILE"