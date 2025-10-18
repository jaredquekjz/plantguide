#!/usr/bin/env python3
"""Sample Agroclim rasters (long-term means) for Stage 1 species using rasterio + DuckDB."""
import argparse
import math
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import rasterio

WORKDIR = Path('/home/olier/ellenberg')
OCC_PATH = WORKDIR / 'data/stage1/stage1_shortlist_with_gbif.parquet'
GBIF_OCC_PATH = WORKDIR / 'data/gbif/occurrence_plantae_wfo.parquet'
RASTER_DIR = WORKDIR / 'data/agroclime_mean'
OUTPUT_OCC = WORKDIR / 'data/stage1/agroclime_occ_samples.parquet'
OUTPUT_SUM = WORKDIR / 'data/stage1/agroclime_species_summary.parquet'
LOG_PATH = WORKDIR / 'dump/agroclime_samples.log'

DEFAULT_CHUNK_SIZE = 150_000


def parse_args():
    parser = argparse.ArgumentParser(description="Sample Agroclim rasters for shortlist species.")
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=DEFAULT_CHUNK_SIZE,
        help="Number of occurrences per chunk (default: %(default)s).",
    )
    return parser.parse_args()


def log(message: str) -> None:
    text = message.rstrip() + '\n'
    print(text, end='', flush=True)
    with LOG_PATH.open('a', encoding='utf-8') as fh:
        fh.write(text)


def list_rasters(root: Path):
    rasters = sorted(root.glob('*.tif'))
    if not rasters:
        raise RuntimeError('No Agroclim rasters found in data/agroclime_mean/.')
    raster_map = {}
    for path in rasters:
        key = path.stem  # includes variable + metadata
        raster_map[key] = path
    return raster_map


def open_rasters(raster_map):
    datasets = {}
    for key, path in raster_map.items():
        ds = rasterio.open(path)
        datasets[key] = ds
    return datasets


def close_rasters(datasets):
    for ds in datasets.values():
        ds.close()


def prepare_species(con: duckdb.DuckDBPyConnection) -> int:
    species_df = con.execute(
        """
        SELECT wfo_taxon_id
        FROM read_parquet(?)
        WHERE gbif_occurrence_count >= 30
        """,
        [str(OCC_PATH)],
    ).df()
    if species_df.empty:
        return 0
    con.register('species_list', species_df)
    con.execute("CREATE OR REPLACE TEMP TABLE species_target AS SELECT wfo_taxon_id FROM species_list")
    return len(species_df)


def prepare_occurrences(con: duckdb.DuckDBPyConnection) -> int:
    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE target_occ AS
        SELECT
            o.wfo_taxon_id,
            o.gbifID,
            o.decimalLongitude AS lon,
            o.decimalLatitude AS lat
        FROM read_parquet(?) o
        JOIN species_target s USING (wfo_taxon_id)
        WHERE o.decimalLongitude IS NOT NULL
          AND o.decimalLatitude IS NOT NULL
        """,
        [str(GBIF_OCC_PATH)],
    )
    return con.execute("SELECT COUNT(*) FROM target_occ").fetchone()[0]


def sample_chunk(con, datasets, offset, chunk_size):
    chunk = con.execute(
        """
        SELECT wfo_taxon_id, gbifID, lon, lat
        FROM target_occ
        ORDER BY wfo_taxon_id, gbifID
        LIMIT ? OFFSET ?
        """,
        [chunk_size, offset],
    ).df()
    if chunk.empty:
        return None
    coords = list(zip(chunk['lon'].to_numpy(), chunk['lat'].to_numpy()))
    result = {
        'wfo_taxon_id': chunk['wfo_taxon_id'].to_numpy(),
        'gbifID': chunk['gbifID'].to_numpy(),
        'lon': chunk['lon'].to_numpy(),
        'lat': chunk['lat'].to_numpy(),
    }
    for key, ds in datasets.items():
        samples = list(ds.sample(coords))
        values = np.array(samples, dtype='float32').reshape(-1)
        nodata = ds.nodata
        if nodata is not None and not np.isnan(nodata):
            values = np.where(np.isclose(values, nodata), np.nan, values)
        result[key] = values
    return pd.DataFrame(result)


def write_occ_parquet(df: pd.DataFrame, writer_holder):
    table = pa.Table.from_pandas(df, preserve_index=False)
    if writer_holder[0] is None:
        writer_holder[0] = pq.ParquetWriter(OUTPUT_OCC, table.schema, compression='zstd')
    writer_holder[0].write_table(table)


def aggregate_species(con: duckdb.DuckDBPyConnection):
    con.execute("CREATE OR REPLACE TABLE agro_occ_samples AS SELECT * FROM read_parquet(?)", [str(OUTPUT_OCC)])
    cols = [c[1] for c in con.execute("PRAGMA table_info('agro_occ_samples')").fetchall()]
    value_cols = [c for c in cols if c not in ('wfo_taxon_id', 'gbifID', 'lon', 'lat')]
    select_parts = ["wfo_taxon_id"]
    def quote_identifier(col: str) -> str:
        return '"' + col.replace('"', '""') + '"'

    def make_alias(col: str, suffix: str) -> str:
        sanitized = ''.join(ch if (ch.isalnum() or ch == '_') else '_' for ch in col)
        if not sanitized or sanitized[0].isdigit():
            sanitized = '_' + sanitized
        return f"{sanitized}_{suffix}"
    for col in value_cols:
        quoted = quote_identifier(col)
        select_parts.extend([
            f"AVG({quoted}) AS {make_alias(col, 'avg')}",
            f"STDDEV({quoted}) AS {make_alias(col, 'stddev')}",
            f"MIN({quoted}) AS {make_alias(col, 'min')}",
            f"MAX({quoted}) AS {make_alias(col, 'max')}",
        ])
    agg_sql = "SELECT " + ", ".join(select_parts) + " FROM agro_occ_samples GROUP BY wfo_taxon_id"
    con.execute("COPY (" + agg_sql + ") TO ? (FORMAT PARQUET, COMPRESSION ZSTD)", [str(OUTPUT_SUM)])


def main():
    args = parse_args()
    chunk_size = args.chunk_size
    if chunk_size <= 0:
        raise ValueError('chunk_size must be > 0')

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOG_PATH.write_text('')

    if OUTPUT_OCC.exists():
        OUTPUT_OCC.unlink()
    if OUTPUT_SUM.exists():
        OUTPUT_SUM.unlink()

    log('Indexing Agroclim rasters...')
    raster_map = list_rasters(RASTER_DIR)
    log(f'Found {len(raster_map)} rasters. Opening datasets...')
    datasets = open_rasters(raster_map)
    log('Agroclim rasters ready.')

    con = duckdb.connect()
    log('Collecting shortlist species with >=30 GBIF occurrences...')
    species_count = prepare_species(con)
    if species_count == 0:
        log('No species found; exiting.')
        close_rasters(datasets)
        return
    log(f'Target species count: {species_count}')

    log('Filtering GBIF occurrences...')
    total_occ = prepare_occurrences(con)
    if total_occ == 0:
        log('No occurrences found; exiting.')
        close_rasters(datasets)
        return
    log(f'Filtered occurrence rows: {total_occ}')

    writer_holder = [None]
    num_chunks = math.ceil(total_occ / chunk_size)
    log(f'Sampling agroclim values in {num_chunks} chunks (chunk size = {chunk_size})...')
    for idx in range(num_chunks):
        offset = idx * chunk_size
        df = sample_chunk(con, datasets, offset, chunk_size)
        if df is None or df.empty:
            break
        write_occ_parquet(df, writer_holder)
        processed = min((idx + 1) * chunk_size, total_occ)
        pct = processed / total_occ * 100
        log(f'Chunk {idx + 1}/{num_chunks} processed ({processed}/{total_occ}, {pct:.2f}%)')
    if writer_holder[0] is not None:
        writer_holder[0].close()

    close_rasters(datasets)

    log('Aggregating per species...')
    aggregate_species(con)
    log('Done.')
    log(f'Occurrence samples: {OUTPUT_OCC}')
    log(f'Species summaries: {OUTPUT_SUM}')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        log(f'Error: {exc}')
        raise
