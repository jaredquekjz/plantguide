#!/bin/bash

# =============================================================================
# Pre-download Reference Data for GBIF Pipeline
# =============================================================================
# Downloads all large reference datasets using aria2 for speed and progress
# This prevents slow downloads during pipeline execution

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WORLDCLIM_URL="https://geodata.ucdavis.edu/climate/worldclim/2_1/base/wc2.1_30s_bio.zip"
WORLDCLIM_DIR="/home/olier/ellenberg/data/worldclim"
WORLDCLIM_FILE="wc2.1_30s_bio.zip"

# Natural Earth URLs (multiple resolutions)
NE_BASE_URL="https://www.naturalearthdata.com/http//www.naturalearthdata.com/download"
NE_LAND_10M="${NE_BASE_URL}/10m/physical/ne_10m_land.zip"
NE_LAND_50M="${NE_BASE_URL}/50m/physical/ne_50m_land.zip"
NE_LAND_110M="${NE_BASE_URL}/110m/physical/ne_110m_land.zip"

# R's expected cache directory for Natural Earth data
R_USER_DIR="${HOME}/.local/share/R/naturalearth"
if [ ! -z "${R_USER_DATA_DIR:-}" ]; then
    R_USER_DIR="${R_USER_DATA_DIR}/naturalearth"
fi

# CoordinateCleaner's expected cache location (alternative)
CC_CACHE_DIR="${HOME}/.Rcache/CoordinateCleaner"

echo "=============================================="
echo "Reference Data Pre-download Script"
echo "=============================================="
echo ""

# Check if aria2 is installed
if ! command -v aria2c &> /dev/null; then
    echo -e "${YELLOW}⚠ aria2 not installed. Installing...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y aria2
    else
        echo -e "${RED}✗ Could not install aria2. Please install manually:${NC}"
        echo "  Ubuntu/Debian: sudo apt-get install aria2"
        echo "  MacOS: brew install aria2"
        exit 1
    fi
fi

echo -e "${GREEN}✓ aria2 is available${NC}"
echo ""

# Function to download with aria2
download_with_aria2() {
    local url=$1
    local output_dir=$2
    local output_file=$3
    local description=$4
    
    mkdir -p "$output_dir"
    
    if [ -f "${output_dir}/${output_file}" ]; then
        echo -e "${GREEN}✓ ${description} already exists${NC}"
        echo "  Location: ${output_dir}/${output_file}"
        
        # Check file size
        local size=$(du -h "${output_dir}/${output_file}" | cut -f1)
        echo "  Size: ${size}"
        
        # For zip files, optionally verify integrity
        if [[ $output_file == *.zip ]]; then
            if unzip -t "${output_dir}/${output_file}" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Archive integrity verified${NC}"
            else
                echo -e "  ${YELLOW}⚠ Archive may be corrupted, re-downloading...${NC}"
                rm -f "${output_dir}/${output_file}"
            fi
        fi
    fi
    
    if [ ! -f "${output_dir}/${output_file}" ]; then
        echo -e "${YELLOW}⟳ Downloading ${description}...${NC}"
        echo "  URL: ${url}"
        echo "  Destination: ${output_dir}/${output_file}"
        echo ""
        
        # Download with aria2
        # -x 16: Use up to 16 connections per server
        # -s 16: Split file into 16 segments
        # -k 1M: Min split size 1MB
        # -c: Continue partial downloads
        # --file-allocation=none: Faster for SSDs
        # --console-log-level=info: Show progress
        aria2c \
            -x 16 \
            -s 16 \
            -k 1M \
            -c \
            --file-allocation=none \
            --console-log-level=info \
            --summary-interval=10 \
            --download-result=full \
            --allow-overwrite=true \
            --auto-file-renaming=false \
            -d "${output_dir}" \
            -o "${output_file}" \
            "${url}"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully downloaded ${description}${NC}"
            
            # Verify zip integrity
            if [[ $output_file == *.zip ]]; then
                echo "  Verifying archive integrity..."
                if unzip -t "${output_dir}/${output_file}" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✓ Archive is valid${NC}"
                else
                    echo -e "  ${RED}✗ Archive verification failed${NC}"
                    exit 1
                fi
            fi
        else
            echo -e "${RED}✗ Failed to download ${description}${NC}"
            exit 1
        fi
    fi
    echo ""
}

# Function to extract if needed
extract_if_needed() {
    local zip_file=$1
    local extract_dir=$2
    local description=$3
    
    # Check if already extracted (look for .tif files for WorldClim)
    if [[ "$description" == "WorldClim" ]]; then
        local tif_count=$(find "$extract_dir" -name "*.tif" 2>/dev/null | wc -l)
        if [ "$tif_count" -ge 19 ]; then
            echo -e "${GREEN}✓ ${description} already extracted (${tif_count} files)${NC}"
            return 0
        fi
    fi
    
    if [ -f "$zip_file" ]; then
        echo -e "${YELLOW}⟳ Extracting ${description}...${NC}"
        mkdir -p "$extract_dir"
        unzip -q -o "$zip_file" -d "$extract_dir"
        echo -e "${GREEN}✓ ${description} extracted${NC}"
    fi
}

echo "=============================================="
echo "1. WorldClim Bioclimatic Variables"
echo "=============================================="

download_with_aria2 \
    "$WORLDCLIM_URL" \
    "$WORLDCLIM_DIR" \
    "$WORLDCLIM_FILE" \
    "WorldClim 2.1 Bioclimatic Variables (9.7GB)"

# Extract WorldClim if needed
extract_if_needed \
    "${WORLDCLIM_DIR}/${WORLDCLIM_FILE}" \
    "${WORLDCLIM_DIR}/bio" \
    "WorldClim"

echo "=============================================="
echo "2. Natural Earth Land Polygons"
echo "=============================================="

# Create cache directories
mkdir -p "$R_USER_DIR"
mkdir -p "$CC_CACHE_DIR"

# Download all three resolutions that CoordinateCleaner might use
echo "Downloading Natural Earth data at multiple resolutions..."
echo "(CoordinateCleaner may use any of these depending on settings)"
echo ""

# 50m resolution (default for CoordinateCleaner)
download_with_aria2 \
    "$NE_LAND_50M" \
    "$R_USER_DIR" \
    "ne_50m_land.zip" \
    "Natural Earth Land 50m (~8MB)"

# Also copy to potential cache locations
cp -f "${R_USER_DIR}/ne_50m_land.zip" "${CC_CACHE_DIR}/" 2>/dev/null || true

# 10m resolution (high detail)
download_with_aria2 \
    "$NE_LAND_10M" \
    "$R_USER_DIR" \
    "ne_10m_land.zip" \
    "Natural Earth Land 10m (~30MB)"

# 110m resolution (low detail, fast)
download_with_aria2 \
    "$NE_LAND_110M" \
    "$R_USER_DIR" \
    "ne_110m_land.zip" \
    "Natural Earth Land 110m (~2MB)"

echo "=============================================="
echo "3. Additional Reference Data"
echo "=============================================="

# Download CoordinateCleaner's institution database
INST_URL="https://github.com/ropensci/CoordinateCleaner/raw/master/inst/extdata/institutions.rda"
INST_DIR="${HOME}/.local/share/R/CoordinateCleaner"
mkdir -p "$INST_DIR"

if [ ! -f "${INST_DIR}/institutions.rda" ]; then
    echo -e "${YELLOW}⟳ Downloading institution database...${NC}"
    wget -q "$INST_URL" -O "${INST_DIR}/institutions.rda"
    echo -e "${GREEN}✓ Institution database downloaded${NC}"
else
    echo -e "${GREEN}✓ Institution database already exists${NC}"
fi

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="

# Check disk usage
echo "Disk usage:"
if [ -d "$WORLDCLIM_DIR" ]; then
    echo "  WorldClim: $(du -sh $WORLDCLIM_DIR | cut -f1)"
fi
if [ -d "$R_USER_DIR" ]; then
    echo "  Natural Earth: $(du -sh $R_USER_DIR | cut -f1)"
fi

echo ""
echo -e "${GREEN}✓ All reference data pre-downloaded successfully!${NC}"
echo ""
echo "The GBIF cleaning pipeline can now run without downloading delays."
echo ""
echo "Downloaded files:"
echo "  • WorldClim: ${WORLDCLIM_DIR}/${WORLDCLIM_FILE}"
echo "  • Natural Earth 50m: ${R_USER_DIR}/ne_50m_land.zip"
echo "  • Natural Earth 10m: ${R_USER_DIR}/ne_10m_land.zip"
echo "  • Natural Earth 110m: ${R_USER_DIR}/ne_110m_land.zip"
echo ""
echo "Next step: Run the cleaning pipeline"
echo "  make clean_extract_bioclim_v2"
echo ""