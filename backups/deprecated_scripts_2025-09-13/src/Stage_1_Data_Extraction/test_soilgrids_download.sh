#!/bin/bash
# Test download of ONE SoilGrids file at 1km resolution

echo "================================"
echo "Testing SoilGrids 1km Download"
echo "================================"
echo ""

# Test directory
TESTDIR="/tmp/soilgrids_test"
mkdir -p "$TESTDIR"

# Test with pH at 0-5cm (smallest file)
URL="https://files.isric.org/soilgrids/latest/data_aggregated/1000m/phh2o/phh2o_0-5cm_mean_1000m.tif"
OUTPUT="$TESTDIR/phh2o_0-5cm_1km_test.tif"

echo "Testing download of pH 0-5cm at 1km resolution"
echo "URL: $URL"
echo "Output: $OUTPUT"
echo ""

# Check file size first with HEAD request
echo "Checking file size..."
SIZE=$(curl -sI "$URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
if [ -n "$SIZE" ]; then
    SIZE_MB=$((SIZE / 1048576))
    echo "File size: ${SIZE_MB} MB"
else
    echo "Could not determine file size"
fi

echo ""
echo "Starting download (60 second timeout)..."
START_TIME=$(date +%s)

# Try download with wget (60 second timeout)
if timeout 60 wget --progress=dot:mega -O "$OUTPUT" "$URL" 2>&1 | tail -20; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    
    # Check downloaded file
    if [ -f "$OUTPUT" ]; then
        ACTUAL_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null)
        ACTUAL_MB=$((ACTUAL_SIZE / 1048576))
        
        echo ""
        echo "✓ Download successful!"
        echo "  Time: ${ELAPSED} seconds"
        echo "  Size: ${ACTUAL_MB} MB"
        echo "  Speed: $((ACTUAL_MB * 8 / ELAPSED)) Mbps"
        
        # Test if file is valid GeoTIFF
        echo ""
        echo "Validating GeoTIFF..."
        if gdalinfo "$OUTPUT" > /dev/null 2>&1; then
            echo "✓ Valid GeoTIFF file"
            
            # Show basic info
            echo ""
            echo "File info:"
            gdalinfo "$OUTPUT" 2>/dev/null | grep -E "Size is|Pixel Size|Upper Left|Lower Right" | head -4
        else
            echo "✗ Invalid GeoTIFF file"
        fi
        
        # Projection for full download
        echo ""
        echo "================================"
        echo "Projections for full dataset:"
        TOTAL_FILES=21  # 7 properties × 3 depths
        TOTAL_TIME=$((ELAPSED * TOTAL_FILES))
        echo "  21 files × ${ELAPSED}s = $((TOTAL_TIME / 60)) minutes"
        echo "  Total size: ~$((ACTUAL_MB * TOTAL_FILES / 1000)) GB"
        
        if [ $ELAPSED -gt 30 ]; then
            echo ""
            echo "⚠️  Slow download speed detected"
            echo "Consider running overnight or from a server with better bandwidth"
        fi
        
    else
        echo "✗ Download failed - file not created"
    fi
else
    echo ""
    echo "✗ Download failed or timed out after 60 seconds"
    echo ""
    echo "Possible issues:"
    echo "  1. Slow internet connection"
    echo "  2. ISRIC server is busy"
    echo "  3. URL has changed"
    echo ""
    echo "Alternative: Try direct browser download:"
    echo "$URL"
fi

# Cleanup
echo ""
echo "Cleaning up test file..."
rm -f "$OUTPUT"

echo ""
echo "================================"
echo "Test complete"
echo "================================"