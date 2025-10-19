#!/usr/bin/env python3
"""Verify that mean GeoTIFFs match the averaged NetCDF rasters."""
from pathlib import Path

import numpy as np
import rasterio
import xarray as xr

WORKDIR = Path('/home/olier/ellenberg')
NC_DIR = WORKDIR / 'data/agroclime'
TIF_DIR = WORKDIR / 'data/agroclime_mean'

TESTS = [
    ('TXx_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1.nc', 'TXx_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1_TXx_mean.tif', 'TXx'),
    ('TG_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1.nc', 'TG_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1_TG_mean.tif', 'TG'),
    ('CDD_C3S-glob-agric_gfdl-esm2m_hist_season_19510101-19801231_v1.1.nc', 'CDD_C3S-glob-agric_gfdl-esm2m_hist_season_19510101-19801231_v1.1_CDD_mean.tif', 'CDD'),
]


def compare_pair(nc_path: Path, tif_path: Path, var: str, atol=1e-5):
    print(f'Checking {nc_path.name} vs {tif_path.name} ({var})')
    ds = xr.open_dataset(nc_path)
    da = ds[var]
    dims_to_reduce = [d for d in da.dims if d not in ('lat', 'latitude', 'lon', 'longitude')]
    if dims_to_reduce:
        da = da.mean(dim=dims_to_reduce, skipna=True)
    if 'latitude' in da.dims:
        da = da.rename({'latitude': 'lat'})
    if 'longitude' in da.dims:
        da = da.rename({'longitude': 'lon'})
    da = da.sortby('lat', ascending=False)
    arr_nc = da.values.astype('float32')
    arr_nc = np.ma.masked_invalid(arr_nc)
    with rasterio.open(tif_path) as src:
        arr_tif = src.read(1).astype('float32')
        if src.nodata is not None and not np.isnan(src.nodata):
            arr_tif = np.ma.masked_equal(arr_tif, src.nodata)
        else:
            arr_tif = np.ma.masked_invalid(arr_tif)
    diff = np.ma.abs(arr_nc - arr_tif)
    max_diff = diff.max()
    mean_diff = diff.mean()
    print(f'  shape {arr_nc.shape}, max diff {max_diff:.3e}, mean diff {mean_diff:.3e}')
    assert max_diff <= atol, f"max diff {max_diff} exceeds tolerance {atol}"


def main():
    for nc_name, tif_name, var in TESTS:
        compare_pair(NC_DIR / nc_name, TIF_DIR / tif_name, var)


if __name__ == '__main__':
    main()
