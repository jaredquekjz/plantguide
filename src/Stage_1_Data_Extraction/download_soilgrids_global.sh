#!/bin/bash
# download_soilgrids_global.sh - Download global SoilGrids data
# Run in background: nohup bash download_soilgrids_global.sh > download.log 2>&1 &

# Configuration
OUTDIR="/home/olier/ellenberg/data/soilgrids_global"
LOGFILE="$OUTDIR/download_progress.log"

# Create output directory
mkdir -p "$OUTDIR"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log_message "Starting SoilGrids global download"
log_message "Output directory: $OUTDIR"

# Properties needed for EIVE prediction
# Using 1km resolution for manageable file sizes
PROPERTIES=(
    "phh2o"     # pH - critical for R (Reaction)
    "soc"       # Soil organic carbon - for N (Nutrients)  
    "clay"      # Clay content - for M (Moisture)
    "sand"      # Sand content - drainage
    "cec"       # Cation exchange capacity
    "nitrogen"  # Total nitrogen
    "bdod"      # Bulk density
)

DEPTHS=(
    "0-5cm"
    "5-15cm" 
    "15-30cm"
    "30-60cm"    # Important for shrubs and small trees
    "60-100cm"   # Critical for tree stability
    "100-200cm"  # Deep taproot zone for mature trees
)

# Base URL for 1km aggregated data (smaller files, faster)
BASE_URL="https://files.isric.org/soilgrids/latest/data_aggregated/1000m"

# Track progress
TOTAL=$((${#PROPERTIES[@]} * ${#DEPTHS[@]}))
CURRENT=0

log_message "Downloading $TOTAL files (${#PROPERTIES[@]} properties × ${#DEPTHS[@]} depths)"

# Download function with retry
download_with_retry() {
    local url=$1
    local output=$2
    local max_retries=5
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if wget -c -t 3 --timeout=30 --waitretry=5 \
               --progress=dot:giga \
               -O "$output.tmp" "$url" 2>&1 | tail -1; then
            mv "$output.tmp" "$output"
            return 0
        else
            retry=$((retry + 1))
            log_message "  Retry $retry/$max_retries for $(basename $output)"
            sleep 10
        fi
    done
    
    return 1
}

# Download each property-depth combination
for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        CURRENT=$((CURRENT + 1))
        
        # Construct filename (corrected: _1000.tif not _1000m.tif)
        filename="${prop}_${depth}_mean_1000.tif"
        url="$BASE_URL/$prop/$filename"
        output="$OUTDIR/${prop}_${depth}_1km.tif"
        
        log_message "[$CURRENT/$TOTAL] Downloading $prop at $depth..."
        
        # Skip if already exists
        if [ -f "$output" ]; then
            size=$(du -h "$output" | cut -f1)
            log_message "  Already exists ($size), skipping"
            continue
        fi
        
        # Download with retry
        if download_with_retry "$url" "$output"; then
            size=$(du -h "$output" | cut -f1)
            log_message "  ✓ Success: $output ($size)"
        else
            log_message "  ✗ Failed: $output (check URL)"
        fi
        
        # Small delay between downloads
        sleep 2
    done
done

# Create a summary
log_message "Creating download summary..."

echo "=== SoilGrids Download Summary ===" > "$OUTDIR/summary.txt"
echo "Date: $(date)" >> "$OUTDIR/summary.txt"
echo "Files downloaded:" >> "$OUTDIR/summary.txt"

total_size=0
for file in "$OUTDIR"/*.tif; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        total_size=$((total_size + size))
        echo "  $(basename $file): $(du -h $file | cut -f1)" >> "$OUTDIR/summary.txt"
    fi
done

echo "Total size: $(echo $total_size | awk '{printf "%.2f GB\n", $1/1073741824}')" >> "$OUTDIR/summary.txt"

log_message "Download complete!"
log_message "Total size: $(echo $total_size | awk '{printf "%.2f GB", $1/1073741824}')"
log_message "Summary saved to: $OUTDIR/summary.txt"

# Optional: Create VRT mosaic for each property (combines depths)
log_message "Creating VRT mosaics..."

for prop in "${PROPERTIES[@]}"; do
    vrt_file="$OUTDIR/${prop}_all_depths.vrt"
    gdalbuildvrt "$vrt_file" "$OUTDIR/${prop}_"*_1km.tif 2>/dev/null
    if [ -f "$vrt_file" ]; then
        log_message "  Created: $(basename $vrt_file)"
    fi
done

log_message "=== DOWNLOAD COMPLETE ==="
log_message "Next step: Run extraction script using local files"