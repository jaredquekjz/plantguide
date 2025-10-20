#!/usr/bin/env python3
"""
Lightweight sanity check for WorldClim rasters.

The script samples a handful of global coordinates from each uncompressed
WorldClim TIFF and verifies that the returned value is not the nodata flag
(-3.39999995214436e+38). This catches silent corruption (e.g., truncated
uncompressed tiles) before we rerun the sampling workflow.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


WORLDCLIM_DIR = Path("/home/olier/ellenberg/data/worldclim_uncompressed/bio")
NODATA = "-3.39999995214436e+38"

# Representative global coordinates (lon, lat)
COORDS = [
    (-123.1, 49.3),   # Vancouver
    (2.35, 48.86),    # Paris
    (139.7, 35.7),    # Tokyo
    (151.2, -33.9),   # Sydney
    (-58.4, -34.6),   # Buenos Aires
]


def check_raster(path: Path) -> None:
    """Run gdallocationinfo for a raster across the COORDS."""
    failing = 0
    for lon, lat in COORDS:
        cmd = [
            "gdallocationinfo",
            path.as_posix(),
            "-wgs84",
            str(lon),
            str(lat),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"gdallocationinfo failed for {path.name}: {result.stderr.strip()}")
        if f"Value: {NODATA}" in result.stdout:
            failing += 1
    if failing == len(COORDS):
        raise RuntimeError(f"{path.name} returned nodata for all test coordinates.")


def main() -> int:
    if not WORLDCLIM_DIR.exists():
        print(f"WorldClim directory not found: {WORLDCLIM_DIR}", file=sys.stderr)
        return 1

    tif_files = sorted(WORLDCLIM_DIR.glob("wc2.1_30s_bio_*.tif"))
    if len(tif_files) != 19:
        print(
            f"Expected 19 BIO rasters, found {len(tif_files)} in {WORLDCLIM_DIR}",
            file=sys.stderr,
        )
        return 1

    try:
        for tif in tif_files:
            check_raster(tif)
            print(f"{tif.name}: OK")
    except Exception as exc:  # pylint: disable=broad-except
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1

    print("[OK] WorldClim raster sanity check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
