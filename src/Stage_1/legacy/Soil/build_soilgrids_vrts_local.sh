#!/usr/bin/env bash
set -euo pipefail

SOIL_DIR="${1:-/home/olier/ellenberg/data/soilgrids_250m}"
PROPS=(phh2o soc clay sand cec nitrogen bdod)
DEPTHS=("0-5cm" "5-15cm" "15-30cm" "30-60cm" "60-100cm" "100-200cm")

if ! command -v gdalbuildvrt >/dev/null 2>&1; then
  echo "gdalbuildvrt not found in PATH" >&2
  exit 1
fi

echo "Building missing VRTs in $SOIL_DIR" 
for prop in "${PROPS[@]}"; do
  for depth in "${DEPTHS[@]}"; do
    subdir="$SOIL_DIR/${prop}_${depth}_mean"
    vrt="$SOIL_DIR/${prop}_${depth}_mean.vrt"
    if [ -f "$vrt" ]; then
      echo "[SKIP] $vrt exists"
      continue
    fi
    if [ ! -d "$subdir" ]; then
      echo "[WARN] Dir missing: $subdir (skipping)"
      continue
    fi
    echo "[BUILD] $vrt"
    # Create a temporary file list to avoid huge argv
    tmp=$(mktemp)
    # Collect all tif tiles under subdir
    find "$subdir" -type f -name '*.tif' | sort > "$tmp"
    n=$(wc -l < "$tmp")
    if [ "$n" -eq 0 ]; then
      echo "  No tif tiles found in $subdir; skipping." >&2
      rm -f "$tmp"
      continue
    fi
    # Build VRT (mosaic)
    gdalbuildvrt -input_file_list "$tmp" "$vrt"
    rm -f "$tmp"
  done
done

echo "Done."
