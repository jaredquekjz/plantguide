#!/bin/bash
# download_soilgrids_250m_global.sh - Full global 250m download
# Optimized for high-bandwidth connection (10 Gbps) and large storage (2TB)

# Configuration
OUTDIR="/home/olier/ellenberg/data/soilgrids_250m_global"
LOGFILE="$OUTDIR/download_progress.log"
PARALLEL_JOBS=42  # Optimal parallel connections (one per file)

mkdir -p "$OUTDIR"

# Logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log_message "===== Starting Global 250m SoilGrids Download ====="
log_message "Storage available: 2TB"
log_message "Connection: 10 Gbps"
log_message "Output directory: $OUTDIR"

# Properties for EIVE + trees
PROPERTIES=(
    "phh2o"     # pH in water
    "soc"       # Soil organic carbon (g/kg)
    "clay"      # Clay content (%)
    "sand"      # Sand content (%)
    "cec"       # Cation exchange capacity (cmol/kg)
    "nitrogen"  # Total nitrogen (g/kg)
    "bdod"      # Bulk density (kg/dm³)
)

# All 6 depths for trees
DEPTHS=(
    "0-5cm"
    "5-15cm"
    "15-30cm"
    "30-60cm"
    "60-100cm"
    "100-200cm"
)

# Base URL for 250m VRT files
BASE_URL="/vsicurl/https://files.isric.org/soilgrids/latest/data"

# Function to download one property-depth combination
download_global() {
    local prop=$1
    local depth=$2
    
    local input_vrt="${BASE_URL}/${prop}/${prop}_${depth}_mean.vrt"
    local output_tif="${OUTDIR}/${prop}_${depth}_global_250m.tif"
    
    # Skip if exists and is valid
    if [ -f "$output_tif" ]; then
        if gdalinfo "$output_tif" &>/dev/null; then
            log_message "  [SKIP] ${prop}_${depth} already exists"
            return 0
        else
            log_message "  [CORRUPT] Removing invalid ${prop}_${depth}"
            rm -f "$output_tif"
        fi
    fi
    
    log_message "  [START] ${prop}_${depth}"
    local start_time=$(date +%s)
    
    # Download with optimized settings for high bandwidth
    if gdalwarp \
        -t_srs EPSG:4326 \
        -tr 0.00225 0.00225 \
        -co COMPRESS=DEFLATE \
        -co TILED=YES \
        -co PREDICTOR=2 \
        -co BIGTIFF=YES \
        -co NUM_THREADS=8 \
        -wo NUM_THREADS=8 \
        --config GDAL_CACHEMAX 2048 \
        --config GDAL_HTTP_TIMEOUT 300 \
        --config GDAL_HTTP_MAX_RETRY 5 \
        --config CPL_VSIL_CURL_CHUNK_SIZE 10485760 \
        --config CPL_VSIL_CURL_CACHE_SIZE 536870912 \
        "$input_vrt" \
        "$output_tif" &>"${OUTDIR}/log_${prop}_${depth}.txt"; then
        
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        local size=$(du -h "$output_tif" | cut -f1)
        
        log_message "  [DONE] ${prop}_${depth} - ${elapsed}s, ${size}"
        rm -f "${OUTDIR}/log_${prop}_${depth}.txt"
        return 0
    else
        log_message "  [FAIL] ${prop}_${depth} - check log"
        return 1
    fi
}

# Export function for parallel
export -f download_global log_message
export OUTDIR BASE_URL LOGFILE

# Calculate total files
TOTAL=$((${#PROPERTIES[@]} * ${#DEPTHS[@]}))
log_message "Total files to download: $TOTAL"

# Estimate storage
log_message "Estimated storage needed: ~1.5TB for full 250m dataset"
log_message ""

# Option 1: Sequential download (safer, progress tracking)
if [ "$1" = "--sequential" ]; then
    log_message "Running in SEQUENTIAL mode"
    CURRENT=0
    
    for prop in "${PROPERTIES[@]}"; do
        for depth in "${DEPTHS[@]}"; do
            CURRENT=$((CURRENT + 1))
            log_message "[$CURRENT/$TOTAL] Processing ${prop}_${depth}..."
            download_global "$prop" "$depth"
        done
    done
    
# Option 2: Parallel download (faster with 10Gbps)
else
    log_message "Running in PARALLEL mode (${PARALLEL_JOBS} simultaneous downloads)"
    log_message "Use --sequential flag for one-at-a-time download"
    
    # Create job list
    > "${OUTDIR}/jobs.txt"
    for prop in "${PROPERTIES[@]}"; do
        for depth in "${DEPTHS[@]}"; do
            echo "$prop $depth" >> "${OUTDIR}/jobs.txt"
        done
    done
    
    # Run parallel downloads
    cat "${OUTDIR}/jobs.txt" | \
        parallel -j ${PARALLEL_JOBS} --colsep ' ' \
        download_global {1} {2}
fi

# Create summary
log_message ""
log_message "===== Download Summary ====="

# Count successful downloads
SUCCESS_COUNT=$(ls -1 "${OUTDIR}"/*.tif 2>/dev/null | wc -l)
log_message "Successfully downloaded: $SUCCESS_COUNT/$TOTAL files"

# Calculate total size
if [ $SUCCESS_COUNT -gt 0 ]; then
    TOTAL_SIZE=$(du -sh "$OUTDIR" | cut -f1)
    log_message "Total disk usage: $TOTAL_SIZE"
fi

# List any failed downloads
log_message ""
log_message "Checking for missing files..."
for prop in "${PROPERTIES[@]}"; do
    for depth in "${DEPTHS[@]}"; do
        if [ ! -f "${OUTDIR}/${prop}_${depth}_global_250m.tif" ]; then
            log_message "  MISSING: ${prop}_${depth}"
        fi
    done
done

log_message ""
log_message "===== DOWNLOAD COMPLETE ====="
log_message "Next steps:"
log_message "1. Check log for any failures: $LOGFILE"
log_message "2. Run extraction script to process your 5M occurrences"
log_message "3. With local 250m files, extraction will be FAST!"

# Create extraction script
cat << 'EOF' > "${OUTDIR}/extract_from_250m.R"
#!/usr/bin/env Rscript
# Extract soil values from local 250m files

library(terra)
library(data.table)

# Load occurrences
occurrences <- fread("/home/olier/ellenberg/data/bioclim_extractions_cleaned/occurrences_with_bioclim.csv")

# Convert to SpatVector
points <- vect(occurrences,
               geom = c("decimalLongitude", "decimalLatitude"),
               crs = "EPSG:4326")

# Process each soil file
soil_files <- list.files(".", pattern = "global_250m.tif$", full.names = TRUE)

results <- occurrences[, .(gbifID, species, decimalLongitude, decimalLatitude)]

for (file in soil_files) {
  prop_name <- gsub(".*/(.*?)_.*", "\\1", file)
  cat(sprintf("Extracting %s...\n", prop_name))
  
  raster <- rast(file)
  values <- extract(raster, points, ID = FALSE)[, 2]
  
  # Apply scaling
  if (grepl("phh2o|soc|clay|sand|cec", prop_name)) values <- values / 10
  if (grepl("nitrogen|bdod", prop_name)) values <- values / 100
  
  results[[prop_name]] <- values
}

fwrite(results, "soil_250m_extracted.csv")
cat("Done! Saved to soil_250m_extracted.csv\n")
EOF

chmod +x "${OUTDIR}/extract_from_250m.R"
log_message "Created extraction script: ${OUTDIR}/extract_from_250m.R"