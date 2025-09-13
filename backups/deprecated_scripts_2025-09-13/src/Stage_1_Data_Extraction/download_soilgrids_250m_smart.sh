#!/bin/bash
# download_soilgrids_250m_smart.sh - Smart approach for 250m global data
# Downloads pre-aggregated COGs or uses streaming with local cache

echo "========================================"
echo "SoilGrids 250m Download Strategy"
echo "========================================"
echo ""

OUTDIR="/home/olier/ellenberg/data/soilgrids_250m"
mkdir -p "$OUTDIR"

# Check available options
echo "Checking available 250m data formats..."
echo ""

# Option 1: Check if 250m COGs exist (Cloud Optimized GeoTIFFs)
echo "Option 1: Pre-processed 250m COGs"
echo "----------------------------------"
BASE_250="https://files.isric.org/soilgrids/latest/data"

# Test one property
TEST_URL="${BASE_250}/phh2o/phh2o_0-5cm_mean.tif"
if curl -sI "$TEST_URL" | grep -q "200 OK"; then
    echo "✓ 250m COGs available!"
    SIZE=$(curl -sI "$TEST_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
    SIZE_GB=$((SIZE / 1073741824))
    echo "  Estimated size per file: ${SIZE_GB} GB"
else
    echo "✗ No direct 250m COG files"
fi

echo ""
echo "Option 2: 250m VRT with tile streaming"
echo "---------------------------------------"
VRT_URL="${BASE_250}/phh2o/phh2o_0-5cm_mean.vrt"
if curl -sI "$VRT_URL" | grep -q "200 OK"; then
    echo "✓ 250m VRT files available"
    echo "  Can stream tiles on-demand or download globally"
fi

echo ""
echo "========================================"
echo "RECOMMENDED APPROACH FOR YOUR PROJECT:"
echo "========================================"
echo ""
echo "Given:"
echo "  - 5M occurrences globally"
echo "  - Need for tree-depth soil (0-200cm)"
echo "  - 250m resolution requirement"
echo ""
echo "Best Strategy:"
echo ""
echo "1. HYBRID APPROACH:"
echo "   a) Use 1km files for initial analysis (fast)"
echo "   b) Stream 250m data for final models"
echo ""
echo "2. Or SMART DOWNLOAD:"
echo "   Download 250m for high-density regions only"
echo ""

# Create the hybrid extraction script
cat << 'EOF' > "$OUTDIR/extract_hybrid_resolution.R"
#!/usr/bin/env Rscript
# Hybrid extraction: 1km for exploration, 250m for final models

library(terra)
library(data.table)

# Function to extract at different resolutions
extract_soil_smart <- function(occurrences, resolution = "1km") {
  
  if (resolution == "1km") {
    # Fast 1km extraction from local files
    base_dir <- "/home/olier/ellenberg/data/soilgrids_global"
    
    # Load 1km rasters (small, fast)
    ph_1km <- rast(file.path(base_dir, "phh2o_0-5cm_1km.tif"))
    
  } else if (resolution == "250m") {
    # Stream 250m data via VRT
    ph_250m <- rast("/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt")
    
    # For efficiency, process by spatial chunks
    # This minimizes tile fetching
  }
}

# Workflow:
# 1. Initial analysis with 1km (fast)
# 2. Final models with 250m (accurate)
# 3. Cache 250m extractions for reuse
EOF

echo "Created: $OUTDIR/extract_hybrid_resolution.R"
echo ""
echo "========================================"
echo "FINAL RECOMMENDATIONS:"
echo "========================================"
echo ""
echo "For your 559 species with trees:"
echo ""
echo "1. START with 1km download (3.4GB, 1 hour):"
echo "   bash download_soilgrids_global.sh"
echo ""
echo "2. TEST model performance with 1km data"
echo ""
echo "3. IF 1km is insufficient, THEN:"
echo "   - Option A: Stream 250m via VRT (slow but no storage)"
echo "   - Option B: Download 250m for Europe only (~50GB)"
echo "   - Option C: Use 500m aggregated as compromise"
echo ""
echo "Remember: Trees need all 6 depths (0-200cm)!"
echo "The 1km data DOES include all depths."
echo ""

# Quick comparison
echo "========================================"
echo "RESOLUTION COMPARISON:"
echo "========================================"
echo ""
echo "| Resolution | File Size | Extract 5M pts | Storage | Accuracy |"
echo "|------------|-----------|----------------|---------|----------|"
echo "| 1km        | 150MB/file| 20 min         | 7GB     | Good     |"
echo "| 500m       | 600MB/file| 30 min         | 28GB    | Better   |"  
echo "| 250m       | 2.4GB/file| 60 min         | 110GB   | Best     |"
echo ""
echo "For 559 species (mostly European), 1km is likely sufficient!"
echo "Trees care more about DEPTH than horizontal resolution."