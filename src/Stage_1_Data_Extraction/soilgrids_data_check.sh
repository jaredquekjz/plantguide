#!/bin/bash
# Complete check of what SoilGrids offers at 250m

echo "========================================="
echo "SOILGRIDS 250m DATA AVAILABILITY CHECK"
echo "========================================="
echo ""

BASE_URL="https://files.isric.org/soilgrids/latest/data"

echo "1. CHECKING AVAILABLE PROPERTIES..."
echo "------------------------------------"

# List all available properties
curl -s "$BASE_URL/" | grep -o 'href="[^/"]*/\"' | sed 's/href="//;s/\/"//g' | sort | while read prop; do
  echo -n "  $prop: "
  
  # Check if it has VRT files
  vrt_check=$(curl -s "$BASE_URL/$prop/" | grep -c "\.vrt\"")
  if [ $vrt_check -gt 0 ]; then
    echo "✓ Available"
  else
    echo "✗ No VRT files"
  fi
done

echo ""
echo "2. CHECKING DEPTHS FOR KEY PROPERTIES..."
echo "-----------------------------------------"

# Key properties for EIVE and trees
PROPERTIES="phh2o soc clay sand cec nitrogen bdod"

for prop in $PROPERTIES; do
  echo ""
  echo "Property: $prop"
  curl -s "$BASE_URL/$prop/" | grep -o "${prop}_[^\"]*mean\.vrt" | sed 's/\.vrt//' | sed "s/${prop}_/  - /" | sed 's/_mean//'
done

echo ""
echo "3. CHECKING ADDITIONAL WATER PROPERTIES..."
echo "-------------------------------------------"

# Water properties important for trees
echo "Water content properties:"
curl -s "$BASE_URL/" | grep -o 'href="wv[^/"]*/\"' | sed 's/href="//;s/\/"//g' | while read prop; do
  echo "  $prop - $(curl -s "$BASE_URL/$prop/" | grep -c "\.vrt\"")" VRT files
done

echo ""
echo "4. DATA QUALITY INDICATORS..."
echo "------------------------------"

echo "For pH (example):"
curl -s "$BASE_URL/phh2o/" | grep -o "phh2o_0-5cm[^\"]*\.vrt" | head -5 | while read file; do
  echo "  - $file"
done

echo ""
echo "========================================="
echo "ARIA2 OPTIMIZATION POTENTIAL"
echo "========================================="
echo ""

# Check if aria2 is installed
if command -v aria2c &> /dev/null; then
  echo "✓ aria2c is installed: $(aria2c --version | head -1)"
else
  echo "✗ aria2c not installed (install with: sudo apt install aria2)"
fi

echo ""
echo "ARIA2 VS GDALWARP COMPARISON:"
echo "------------------------------"
echo ""
echo "GDALWARP (current method):"
echo "  - Downloads via GDAL's vsicurl"
echo "  - Reprojects on-the-fly"
echo "  - Single-threaded per file"
echo "  - Direct VRT → GeoTIFF conversion"
echo ""
echo "ARIA2 approach:"
echo "  - Multi-connection download (16x default)"
echo "  - Parallel chunk downloading"
echo "  - Resume capability"
echo "  - BUT: Can't directly handle VRT files"
echo ""
echo "HYBRID APPROACH (OPTIMAL):"
echo "  1. Use gdalwarp to identify tile URLs from VRT"
echo "  2. Download tiles with aria2 in parallel"
echo "  3. Build local VRT from downloaded tiles"
echo "  4. Use gdal_translate for final GeoTIFF"
echo ""

# Create aria2 example
cat << 'EOF' > aria2_download_example.sh
#!/bin/bash
# Example: Download SoilGrids tiles with aria2

# Step 1: Get tile URLs from VRT
vrt_url="https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"
wget -q -O temp.vrt "$vrt_url"

# Extract tile URLs from VRT
grep -o 'https://[^"]*\.tif' temp.vrt > tile_urls.txt

# Step 2: Download tiles with aria2 (super fast!)
aria2c \
  --input-file=tile_urls.txt \
  --dir=tiles/ \
  --max-connection-per-server=16 \
  --split=16 \
  --min-split-size=1M \
  --max-concurrent-downloads=10 \
  --continue=true \
  --auto-file-renaming=false

# Step 3: Build local VRT
gdalbuildvrt local.vrt tiles/*.tif

# Step 4: Convert to single GeoTIFF
gdal_translate -co COMPRESS=DEFLATE local.vrt output.tif
EOF

echo "Created: aria2_download_example.sh"
echo ""
echo "========================================="
echo "RECOMMENDATION FOR YOUR SETUP"
echo "========================================="
echo ""
echo "With 10 Gbps connection:"
echo ""
echo "1. FASTEST (but complex): Aria2 hybrid"
echo "   - Download tiles with aria2"
echo "   - ~10x faster than gdalwarp"
echo "   - Requires tile URL extraction"
echo ""
echo "2. SIMPLER (still fast): Parallel gdalwarp"
echo "   - Run multiple gdalwarp instances"
echo "   - Good for your bandwidth"
echo "   - Already implemented in script"
echo ""
echo "3. For 250m global (1.5TB):"
echo "   - Aria2: ~1-2 hours"
echo "   - Parallel gdalwarp: ~4-8 hours"
echo "   - Sequential: ~24 hours"
echo ""