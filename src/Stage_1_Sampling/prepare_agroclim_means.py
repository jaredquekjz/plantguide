#!/usr/bin/env python3
"""Generate climatological means for Agroclim NetCDF products and export as GeoTIFFs."""
from pathlib import Path

import numpy as np
import rioxarray  # noqa: F401
import xarray as xr

WORKDIR = Path('/home/olier/ellenberg')
INPUT_DIR = WORKDIR / 'data/agroclime'
OUTPUT_DIR = WORKDIR / 'data/agroclime_mean'
LOG_PATH = WORKDIR / 'dump/agroclime_mean.log'

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
LOG_PATH.write_text('')


def log(message: str) -> None:
    text = message.rstrip() + '\n'
    print(text, end='', flush=True)
    with LOG_PATH.open('a', encoding='utf-8') as fh:
        fh.write(text)


def to_float32(da: xr.DataArray) -> xr.DataArray:
    return da.astype('float32') if da.dtype != np.float32 else da


def prepare_dataset(path: Path) -> None:
    log(f'Processing {path.name} ...')
    with xr.open_dataset(path) as ds:
        data_vars = [name for name in ds.data_vars if any(dim in ds[name].dims for dim in ('lat', 'latitude'))]
        if not data_vars:
            log(f'  No spatial data variables found in {path.name}; skipping.')
            return
        for var in data_vars:
            da = ds[var]
            dims_to_reduce = [d for d in da.dims if d not in ('lat', 'latitude', 'lon', 'longitude')]
            if dims_to_reduce:
                da = da.mean(dim=dims_to_reduce, skipna=True)
            if 'lat' in da.dims:
                lat_name = 'lat'
            elif 'latitude' in da.dims:
                da = da.rename({'latitude': 'lat'})
                lat_name = 'lat'
            else:
                raise ValueError(f'Latitude dimension not found in {path.name}')

            if 'lon' in da.dims:
                lon_name = 'lon'
            elif 'longitude' in da.dims:
                da = da.rename({'longitude': 'lon'})
                lon_name = 'lon'
            else:
                raise ValueError(f'Longitude dimension not found in {path.name}')

            if 'lat' not in da.coords:
                da = da.assign_coords(lat=('lat', ds['lat'].values))
            if 'lon' not in da.coords:
                da = da.assign_coords(lon=('lon', ds['lon'].values))

            da = da.sortby('lat', ascending=False)
            da = to_float32(da)
            da.rio.set_spatial_dims('lon', 'lat', inplace=True)
            da.rio.write_crs('EPSG:4326', inplace=True)

            output_name = f"{path.stem}_{var}_mean.tif"
            output_path = OUTPUT_DIR / output_name
            da.rio.to_raster(output_path, compress='DEFLATE')
            log(f'  Wrote {output_path.name}')


def main():
    files = sorted(INPUT_DIR.glob('*.nc'))
    if not files:
        log('No NetCDF files found in data/agroclime/.')
        return
    for path in files:
        try:
            prepare_dataset(path)
        except Exception as exc:
            log(f'  Error processing {path.name}: {exc}')


if __name__ == '__main__':
    main()
