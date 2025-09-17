#!/bin/bash
# Download missing nitrogen tiles for tileSG-005-010

echo "========================================="
echo "DOWNLOADING MISSING NITROGEN TILES"
echo "========================================="
echo ""
echo "Target: tileSG-005-010 for nitrogen 15-30cm and 30-60cm"
echo ""

BASE_URL="https://files.isric.org/soilgrids/latest/data/nitrogen"
SOILGRIDS_DIR="/home/olier/ellenberg/data/soilgrids_250m"

# Create directories if needed
mkdir -p "$SOILGRIDS_DIR/nitrogen_15-30cm_mean/tileSG-005-010"
mkdir -p "$SOILGRIDS_DIR/nitrogen_30-60cm_mean/tileSG-005-010"

# Try to download tiles for 30-60cm (the confirmed missing ones)
echo "Attempting to download nitrogen 30-60cm tiles for tileSG-005-010..."
echo ""

# Standard tile grid pattern (usually 4x4 tiles per tileSG)
for i in {1..4}; do
  for j in {1..4}; do
    tile_name="tileSG-005-010_${i}-${j}.tif"
    url="${BASE_URL}/nitrogen_30-60cm_mean/tileSG-005-010/${tile_name}"
    output_path="${SOILGRIDS_DIR}/nitrogen_30-60cm_mean/tileSG-005-010/${tile_name}"
    
    echo "Downloading: ${tile_name}"
    curl -f -s -o "${output_path}" "${url}"
    
    if [ $? -eq 0 ]; then
      echo "  ✓ Success: ${tile_name}"
    else
      echo "  ✗ Failed: ${tile_name} (may not exist on server)"
      rm -f "${output_path}"  # Remove empty file if download failed
    fi
  done
done

echo ""
echo "Checking nitrogen 15-30cm tiles for completeness..."
echo ""

# Check and download any missing 15-30cm tiles
for i in {1..4}; do
  for j in {1..4}; do
    tile_name="tileSG-005-010_${i}-${j}.tif"
    output_path="${SOILGRIDS_DIR}/nitrogen_15-30cm_mean/tileSG-005-010/${tile_name}"
    
    if [ ! -f "${output_path}" ]; then
      url="${BASE_URL}/nitrogen_15-30cm_mean/tileSG-005-010/${tile_name}"
      echo "Downloading missing: ${tile_name}"
      curl -f -s -o "${output_path}" "${url}"
      
      if [ $? -eq 0 ]; then
        echo "  ✓ Success: ${tile_name}"
      else
        echo "  ✗ Failed: ${tile_name} (may not exist on server)"
        rm -f "${output_path}"
      fi
    else
      echo "  Already exists: ${tile_name}"
    fi
  done
done

echo ""
echo "========================================="
echo "DOWNLOAD ATTEMPT COMPLETE"
echo "========================================="
echo ""

# Report status
echo "Checking downloaded tiles..."
echo ""
echo "15-30cm tiles present:"
ls -la "$SOILGRIDS_DIR/nitrogen_15-30cm_mean/tileSG-005-010/"*.tif 2>/dev/null | wc -l

echo ""
echo "30-60cm tiles present:"
ls -la "$SOILGRIDS_DIR/nitrogen_30-60cm_mean/tileSG-005-010/"*.tif 2>/dev/null | wc -l

echo ""
echo "If tiles are still missing, they may not exist on the ISRIC server."
echo "Consider using a fallback strategy:"
echo "1. Use neighboring tiles for interpolation"
echo "2. Mark these regions as NA in the extraction"
echo "3. Use the build_soilgrids_vrts_local.sh script with --ignore-missing flag"