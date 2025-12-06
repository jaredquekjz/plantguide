#!/usr/bin/env bash
#
# Upload compressed photos to Cloudflare R2
#
# Prerequisites:
#   - rclone configured with r2 remote
#   - R2 bucket 'plantguide-photos' exists
#
# Usage:
#   ./upload_to_r2.sh [--dry-run]
#

set -e

SOURCE_DIR="/home/olier/ellenberg/data/external/inat/photos_web"
R2_BUCKET="r2:olierphotos"
TRANSFERS=32
CHECKERS=16

# Parse arguments
DRY_RUN=""
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
    echo "DRY RUN MODE - no files will be uploaded"
    echo ""
fi

# Check source exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    echo "Run compress_photos.py first"
    exit 1
fi

# Check rclone is configured
if ! rclone listremotes | grep -q "^r2:"; then
    echo "Error: rclone remote 'r2' not configured"
    echo ""
    echo "Configure with:"
    echo "  rclone config"
    echo "  - Name: r2"
    echo "  - Type: s3"
    echo "  - Provider: Cloudflare"
    echo "  - Access Key ID: (from Cloudflare dashboard)"
    echo "  - Secret Access Key: (from Cloudflare dashboard)"
    echo "  - Endpoint: https://0c0a71476a8f84aab10719b7350e13a4.r2.cloudflarestorage.com"
    exit 1
fi

# Count files
FILE_COUNT=$(find "$SOURCE_DIR" -name "*.webp" | wc -l)
TOTAL_SIZE=$(du -sh "$SOURCE_DIR" | cut -f1)

echo "================================================================================"
echo "UPLOAD PHOTOS TO CLOUDFLARE R2"
echo "================================================================================"
echo ""
echo "Source: $SOURCE_DIR"
echo "Destination: $R2_BUCKET"
echo "Files: $FILE_COUNT WebP images + attributions.json"
echo "Total size: $TOTAL_SIZE"
echo "Transfers: $TRANSFERS parallel"
echo ""

# Sync to R2
rclone sync "$SOURCE_DIR" "$R2_BUCKET" \
    --progress \
    --transfers $TRANSFERS \
    --checkers $CHECKERS \
    --fast-list \
    $DRY_RUN

echo ""
echo "================================================================================"
if [[ -z "$DRY_RUN" ]]; then
    echo "Upload complete!"
    echo ""
    echo "Photos available at:"
    echo "  https://photos.plantguide.au/{species}/1.webp"
    echo "  (after configuring public access in Cloudflare dashboard)"
else
    echo "Dry run complete - no files uploaded"
fi
echo "================================================================================"
