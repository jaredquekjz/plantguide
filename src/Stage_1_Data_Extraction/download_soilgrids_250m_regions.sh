#!/bin/bash
# download_soilgrids_250m_regions.sh - Download 250m SoilGrids by regions
# Full depth (0-200cm) for tree modeling

# Configuration
OUTDIR="/home/olier/ellenberg/data/soilgrids_250m"
LOGFILE="$OUTDIR/download_progress.log"

mkdir -p "$OUTDIR"

# Logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log_message "Starting 250m SoilGrids download (regional approach)"

# Properties for EIVE + trees
PROPERTIES=(
    "phh2o"     # pH
    "soc"       # Organic carbon
    "clay"      # Clay %
    "sand"      # Sand %
    "cec"       # Cation exchange
    "nitrogen"  # Total N
    "bdod"      # Bulk density
    "wv0033"    # Water at field capacity (important for trees!)
    "wv1500"    # Water at wilting point (critical for drought)
)

# ALL depths for trees
DEPTHS=(
    "0-5cm"
    "5-15cm"
    "15-30cm"
    "30-60cm"
    "60-100cm"
    "100-200cm"
)

# Define regions based on your species distribution
# Adjust these based on where your 559 species are!
declare -A REGIONS=(
    ["europe"]="-15,34,45,72"        # W Europe to Urals
    ["mediterranean"]="-10,30,45,45"  # Med basin
    ["scandinavia"]="-5,55,35,72"     # N Europe
    ["east_europe"]="20,40,50,60"     # E Europe
    ["west_asia"]="25,35,50,45"       # Turkey/Caucasus
    ["north_africa"]="-10,20,40,38"   # N Africa
)

# Base URL for 250m data
BASE_URL="/vsicurl/https://files.isric.org/soilgrids/latest/data"

log_message "Downloading ${#PROPERTIES[@]} properties × ${#DEPTHS[@]} depths × ${#REGIONS[@]} regions"

# Function to download one region
download_region() {
    local prop=$1
    local depth=$2
    local region=$3
    local bbox=$4
    
    input_vrt="${BASE_URL}/${prop}/${prop}_${depth}_mean.vrt"
    output_tif="${OUTDIR}/${prop}_${depth}_${region}_250m.tif"
    
    # Skip if exists
    if [ -f "$output_tif" ]; then
        log_message "  Exists: $(basename $output_tif)"
        return 0
    fi
    
    log_message "  Downloading: ${prop}_${depth} for ${region}"
    
    # Use gdalwarp to extract region and reproject to WGS84
    if gdalwarp \
        -te $bbox \
        -t_srs EPSG:4326 \
        -tr 0.00225 0.00225 \
        -co COMPRESS=LZW \
        -co TILED=YES \
        -co BIGTIFF=IF_SAFER \
        -wo NUM_THREADS=2 \
        --config GDAL_HTTP_TIMEOUT 300 \
        --config GDAL_HTTP_MAX_RETRY 3 \
        "$input_vrt" \
        "$output_tif" 2>&1 | tail -5; then
        
        size=$(du -h "$output_tif" | cut -f1)
        log_message "    ✓ Success: ${region} (${size})"
        return 0
    else
        log_message "    ✗ Failed: ${region}"
        rm -f "$output_tif"
        return 1
    fi
}

# Process each combination
TOTAL=$((${#PROPERTIES[@]} * ${#DEPTHS[@]} * ${#REGIONS[@]}))
CURRENT=0

for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        log_message "Processing ${prop} at ${depth}..."
        
        for region in "${!REGIONS[@]}"; do
            CURRENT=$((CURRENT + 1))
            bbox="${REGIONS[$region]}"
            
            echo "  [$CURRENT/$TOTAL] ${region}..."
            download_region "$prop" "$depth" "$region" "$bbox"
            
            # Small delay to avoid overwhelming server
            sleep 2
        done
    done
done

# Create global mosaics from regional tiles
log_message "Creating global mosaics from regional tiles..."

for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        mosaic="${OUTDIR}/${prop}_${depth}_global_250m.vrt"
        
        # Build VRT from all regional tiles
        gdalbuildvrt "$mosaic" "${OUTDIR}/${prop}_${depth}_"*_250m.tif 2>/dev/null
        
        if [ -f "$mosaic" ]; then
            log_message "  Created mosaic: $(basename $mosaic)"
        fi
    done
done

# Summary
total_size=$(du -sh "$OUTDIR" | cut -f1)
log_message "=== DOWNLOAD COMPLETE ==="
log_message "Total size: $total_size"
log_message "Files in: $OUTDIR"

# Alternative: Download full global files (WARNING: HUGE!)
echo ""
echo "================================================================"
echo "NOTE: This script downloads by regions to manage file sizes."
echo ""
echo "If you want FULL GLOBAL 250m files instead, use:"
echo "  gdalwarp -t_srs EPSG:4326 -tr 0.00225 0.00225 \\"
echo "    /vsicurl/.../phh2o_0-5cm_mean.vrt \\"
echo "    phh2o_0-5cm_global_250m.tif"
echo ""
echo "WARNING: Each global file is 20-50GB at 250m resolution!"
echo "================================================================"