#!/usr/bin/env bash
# Preflight fetch: ensure all SourceFilename tiles referenced by SoilGrids VRTs
# exist locally before running extraction. Downloads only missing files.
#
# Usage:
#   scripts/preflight_fetch_soilgrids_tiles.sh \
#     --properties nitrogen[,soc,...] \
#     [--soilgrids-dir /home/olier/ellenberg/data/soilgrids_250m] \
#     [--base-url https://files.isric.org/soilgrids/latest/data] \
#     [--log artifacts/logs/preflight_*.log]
#
# Notes:
# - Parses VRTs like <prop>_<depth>_mean.vrt and fetches any referenced
#   ./<prop>_<depth>_mean/tileSG-XXX-YYY/<file>.tif that is missing locally.
# - Safe to run repeatedly; it will skip files that already exist (size>0).

set -u

PROPERTIES="nitrogen"
SOIL_DIR="/home/olier/ellenberg/data/soilgrids_250m"
BASE_URL="https://files.isric.org/soilgrids/latest/data"
LOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --properties|-p)
      PROPERTIES="$2"; shift 2 ;;
    --soilgrids-dir|-d)
      SOIL_DIR="$2"; shift 2 ;;
    --base-url|-u)
      BASE_URL="$2"; shift 2 ;;
    --log|-l)
      LOG="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 --properties p1[,p2,...] [--soilgrids-dir DIR] [--base-url URL] [--log PATH]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

TS=$(date +%Y%m%d_%H%M%S)
mkdir -p artifacts/logs || true
if [[ -z "$LOG" ]]; then
  LOG="artifacts/logs/preflight_fetch_${TS}.log"
fi
: > "$LOG"

DEPTHS=("0-5cm" "5-15cm" "15-30cm" "30-60cm" "60-100cm" "100-200cm")

echo "========================================" | tee -a "$LOG"
echo "SOILGRIDS PREFLIGHT FETCH" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
echo "properties = $PROPERTIES" | tee -a "$LOG"
echo "soil_dir   = $SOIL_DIR" | tee -a "$LOG"
echo "base_url   = $BASE_URL" | tee -a "$LOG"
echo "log        = $LOG" | tee -a "$LOG"

# Counters
total_refs=0
already_present=0
downloaded=0
upstream_missing=0
errors=0

IFS=',' read -r -a PROPS_ARR <<< "$PROPERTIES"

for prop in "${PROPS_ARR[@]}"; do
  prop=$(echo "$prop" | xargs)
  [[ -z "$prop" ]] && continue
  echo "\nProperty: $prop" | tee -a "$LOG"
  for depth in "${DEPTHS[@]}"; do
    vrt="${SOIL_DIR}/${prop}_${depth}_mean.vrt"
    if [[ ! -s "$vrt" ]]; then
      echo "  - skip (no VRT): $(basename "$vrt")" | tee -a "$LOG"
      continue
    fi
    echo "  - scan: $(basename "$vrt")" | tee -a "$LOG"
    # Extract referenced relative paths from VRT
    # Lines look like: <SourceFilename relativeToVRT="1">./<prop>_<depth>_mean/tileSG-.../.tif</SourceFilename>
    tmp_list=$(mktemp)
    (rg -n '<SourceFilename[^>]*>[^<]+\.tif</SourceFilename>' "$vrt" || true) \
      | sed -E 's@.*<SourceFilename[^>]*>\.?/?([^<]+\.tif)</SourceFilename>.*@\1@' \
      | sort -u > "$tmp_list" || true

    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      (( total_refs++ ))
      dst="${SOIL_DIR}/${rel}"
      if [[ -s "$dst" ]]; then
        (( already_present++ ))
        continue
      fi
      url="${BASE_URL}/${prop}/${rel}"
      mkdir -p "$(dirname "$dst")"
      code=$(curl -L -s -S -o "$dst" -w "%{http_code}" "$url" || true)
      if [[ "$code" == "200" && -s "$dst" ]]; then
        (( downloaded++ ))
        echo "    ✓ fetched: ${rel} ($(du -h "$dst" | cut -f1))" | tee -a "$LOG"
      else
        (( upstream_missing++ ))
        echo "    ✗ missing/failed ($code): ${rel}" | tee -a "$LOG"
        rm -f "$dst" || true
      fi
    done < "$tmp_list"
    rm -f "$tmp_list" || true
  done
done

echo "\nSummary:" | tee -a "$LOG"
echo "  referenced: $total_refs" | tee -a "$LOG"
echo "  present:    $already_present" | tee -a "$LOG"
echo "  downloaded: $downloaded" | tee -a "$LOG"
echo "  missing:    $upstream_missing" | tee -a "$LOG"
echo "Log saved: $LOG" | tee -a "$LOG"

exit 0
