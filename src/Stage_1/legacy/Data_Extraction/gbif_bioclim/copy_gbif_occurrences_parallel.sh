#!/bin/bash

# Parallel version of GBIF occurrence file copy script
# Uses GNU parallel or xargs for faster processing

set -euo pipefail

# Configuration
SOURCE_DIR="/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete"
TARGET_DIR="/home/olier/ellenberg/data/gbif_occurrences_model_species"
MODEL_DATA="/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv"
LOG_FILE="/home/olier/ellenberg/logs/gbif_copy_parallel_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_JOBS=8  # Number of parallel copy operations

# Create directories if they don't exist
mkdir -p "$TARGET_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

echo "========================================" | tee "$LOG_FILE"
echo "GBIF Occurrence File Copy (Parallel)" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Parallel jobs: $PARALLEL_JOBS" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Create temporary files
SPECIES_LIST=$(mktemp /tmp/species_list.XXXXXX)
FILES_TO_COPY=$(mktemp /tmp/files_to_copy.XXXXXX)
NOT_FOUND_LIST=$(mktemp /tmp/not_found.XXXXXX)

# Extract species names and convert to GBIF format
echo "Extracting species list from model data..." | tee -a "$LOG_FILE"
tail -n +2 "$MODEL_DATA" | cut -d',' -f1 | \
    tr '[:upper:]' '[:lower:]' | tr ' ' '-' > "$SPECIES_LIST"

TOTAL=$(wc -l < "$SPECIES_LIST")
echo "Total species to match: $TOTAL" | tee -a "$LOG_FILE"

# Check which files exist (this is fast even with 386k files)
echo "Checking for existing GBIF files..." | tee -a "$LOG_FILE"
while IFS= read -r gbif_name; do
    source_file="${SOURCE_DIR}/${gbif_name}.csv.gz"
    if [ -f "$source_file" ]; then
        echo "$source_file"
    else
        echo "$gbif_name" >> "$NOT_FOUND_LIST"
    fi
done < "$SPECIES_LIST" > "$FILES_TO_COPY"

FOUND=$(wc -l < "$FILES_TO_COPY")
NOT_FOUND=$(wc -l < "$NOT_FOUND_LIST")

echo "Files found: $FOUND" | tee -a "$LOG_FILE"
echo "Files not found: $NOT_FOUND" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to copy a single file with progress reporting
copy_file() {
    local source_file="$1"
    local target_dir="$2"
    local basename=$(basename "$source_file")
    
    if cp "$source_file" "$target_dir/"; then
        echo "[✓] Copied: $basename"
        return 0
    else
        echo "[✗] Failed to copy: $basename" >&2
        return 1
    fi
}

export -f copy_file
export TARGET_DIR

# Copy files in parallel
echo "Copying $FOUND files in parallel..." | tee -a "$LOG_FILE"

if command -v parallel &> /dev/null; then
    # Use GNU parallel if available
    echo "Using GNU parallel..." | tee -a "$LOG_FILE"
    cat "$FILES_TO_COPY" | \
        parallel -j "$PARALLEL_JOBS" --progress \
        "cp {} $TARGET_DIR/ && echo '[✓] {}' || echo '[✗] Failed: {}'" \
        2>&1 | tee -a "$LOG_FILE"
else
    # Fall back to xargs
    echo "Using xargs (GNU parallel not found)..." | tee -a "$LOG_FILE"
    cat "$FILES_TO_COPY" | \
        xargs -P "$PARALLEL_JOBS" -I {} sh -c \
        'cp "{}" "'"$TARGET_DIR"'/" && echo "[✓] $(basename "{}")" || echo "[✗] Failed: $(basename "{}")"' \
        2>&1 | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "SUMMARY" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# Verify copied files
COPIED_COUNT=$(ls -1 "$TARGET_DIR"/*.csv.gz 2>/dev/null | wc -l || echo 0)

echo "Total species in model: $TOTAL" | tee -a "$LOG_FILE"
echo "GBIF files found: $FOUND" | tee -a "$LOG_FILE"
echo "GBIF files not found: $NOT_FOUND" | tee -a "$LOG_FILE"
echo "Files successfully copied: $COPIED_COUNT" | tee -a "$LOG_FILE"
echo "Match rate: $(echo "scale=2; $FOUND * 100 / $TOTAL" | bc)%" | tee -a "$LOG_FILE"

# Disk usage
echo "" | tee -a "$LOG_FILE"
echo "Disk usage:" | tee -a "$LOG_FILE"
du -sh "$TARGET_DIR" | tee -a "$LOG_FILE"

# Save missing species list
if [ $NOT_FOUND -gt 0 ]; then
    NOT_FOUND_OUTPUT="/home/olier/ellenberg/logs/gbif_species_not_found.txt"
    
    # Add species names back (not just the GBIF format)
    echo "Species not found in GBIF data:" > "$NOT_FOUND_OUTPUT"
    echo "================================" >> "$NOT_FOUND_OUTPUT"
    echo "" >> "$NOT_FOUND_OUTPUT"
    
    # Join with original species names for clarity
    paste -d'\t' <(tail -n +2 "$MODEL_DATA" | cut -d',' -f1 | head -n "$TOTAL") \
                  <(cat "$SPECIES_LIST") | \
        while IFS=$'\t' read -r original gbif_format; do
            if grep -q "^${gbif_format}$" "$NOT_FOUND_LIST"; then
                echo "$original (searched as: ${gbif_format}.csv.gz)"
            fi
        done >> "$NOT_FOUND_OUTPUT"
    
    echo "" | tee -a "$LOG_FILE"
    echo "Missing species list saved to: $NOT_FOUND_OUTPUT" | tee -a "$LOG_FILE"
    echo "First 5 missing species:" | tee -a "$LOG_FILE"
    head -5 "$NOT_FOUND_OUTPUT" | tail -n +4 | tee -a "$LOG_FILE"
fi

# Clean up temporary files
rm -f "$SPECIES_LIST" "$FILES_TO_COPY" "$NOT_FOUND_LIST"

echo "" | tee -a "$LOG_FILE"
echo "Completed: $(date)" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"

# Quick validation - show a sample of copied files
echo "" | tee -a "$LOG_FILE"
echo "Sample of copied files:" | tee -a "$LOG_FILE"
ls -lh "$TARGET_DIR" | head -5 | tee -a "$LOG_FILE"