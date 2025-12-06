#!/usr/bin/env python3
"""
Compress iNat photos for R2 upload.
- Resize to 640px max dimension (optimized for web display)
- Convert to WebP quality 70 (good balance of size/quality)
- Take top 3 ranked photos per species
- Preserve attribution in single JSON

Usage: python3 compress_photos.py
"""
import os
import csv
import json
import subprocess
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
import multiprocessing

SOURCE_DIR = Path('/home/olier/ellenberg/data/external/inat/photos_large')
OUTPUT_DIR = Path('/home/olier/ellenberg/data/external/inat/photos_web')
MAX_PHOTOS = 10
MAX_DIMENSION = 640
WEBP_QUALITY = 70
WORKERS = min(32, multiprocessing.cpu_count())  # Use all 32 cores

def process_species(species_folder):
    """Process one species folder."""
    manifest_path = species_folder / 'license_manifest.csv'
    if not manifest_path.exists():
        return None

    species_name = species_folder.name
    output_folder = OUTPUT_DIR / species_name
    output_folder.mkdir(parents=True, exist_ok=True)

    # Read manifest, get top N photos
    photos = []
    with open(manifest_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            photos.append(row)

    # Sort by rank, take top N
    photos = sorted(photos, key=lambda x: int(x.get('rank', 999)))[:MAX_PHOTOS]

    attributions = []
    for i, photo in enumerate(photos, 1):
        src_path = species_folder / photo['photo_filename']
        dst_path = output_folder / f'{i}.webp'

        if not src_path.exists():
            continue

        # Convert with cwebp (quiet mode)
        subprocess.run([
            'cwebp', '-q', str(WEBP_QUALITY),
            '-resize', str(MAX_DIMENSION), '0',
            '-quiet',
            str(src_path), '-o', str(dst_path)
        ], capture_output=True)

        attributions.append({
            'index': i,
            'license': photo.get('license', 'unknown'),
            'observer': photo.get('observer_name', 'unknown'),
            'original_id': photo.get('photo_id', ''),
        })

    return {
        'species': species_name,
        'wfo_taxon_id': photos[0].get('wfo_taxon_id', '') if photos else '',
        'photos': attributions
    }

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    species_folders = [d for d in SOURCE_DIR.iterdir() if d.is_dir()]
    total = len(species_folders)

    print(f'Processing {total} species folders with {WORKERS} workers...')
    print(f'Output: {OUTPUT_DIR}')
    print()

    all_attributions = []
    completed = 0

    with ProcessPoolExecutor(max_workers=WORKERS) as executor:
        futures = {executor.submit(process_species, f): f for f in species_folders}

        for future in as_completed(futures):
            result = future.result()
            if result:
                all_attributions.append(result)
            completed += 1
            if completed % 200 == 0:
                print(f'  {completed:,}/{total:,} ({100*completed/total:.1f}%)')

    # Save master attribution file
    attr_path = OUTPUT_DIR / 'attributions.json'
    with open(attr_path, 'w') as f:
        json.dump(all_attributions, f)

    # Calculate output size
    total_size = sum(f.stat().st_size for f in OUTPUT_DIR.rglob('*.webp'))

    print()
    print(f'Done!')
    print(f'  Species processed: {len(all_attributions):,}')
    print(f'  Total size: {total_size / 1024 / 1024 / 1024:.2f} GB')
    print(f'  Attributions: {attr_path}')

if __name__ == '__main__':
    main()
