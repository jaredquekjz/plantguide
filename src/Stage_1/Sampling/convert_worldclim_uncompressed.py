#!/usr/bin/env python3
"""Convert WorldClim rasters to uncompressed GeoTIFFs for DuckDB/GDAL compatibility."""
from pathlib import Path
import subprocess

SRC_ROOT = Path('/home/olier/ellenberg/data/worldclim')
DST_ROOT = Path('/home/olier/ellenberg/data/worldclim_uncompressed')

DST_ROOT.mkdir(parents=True, exist_ok=True)

rasters = sorted(SRC_ROOT.rglob('*.tif'))
print(f'Found {len(rasters)} raster files to check.')

converted = 0
for src in rasters:
    rel = src.relative_to(SRC_ROOT)
    dst = DST_ROOT / rel
    if dst.exists():
        continue
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        'gdal_translate',
        '-co', 'COMPRESS=NONE',
        str(src),
        str(dst)
    ]
    print(f'Converting {src} -> {dst}')
    subprocess.run(cmd, check=True)
    converted += 1

print(f'Conversion complete. Newly written files: {converted}')
