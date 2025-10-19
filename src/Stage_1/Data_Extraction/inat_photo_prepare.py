#!/usr/bin/env python3
"""
Prepare Stage 1 manifests for iNaturalist photo downloads.

This script automates the following:
1. Download and extract the latest iNaturalist Open Dataset metadata bundle.
2. Derive original (pre-WorldFlora) taxon names for the Stage 1 shortlist.
3. Match those names to iNaturalist taxon identifiers.
4. Build a photo manifest with licenses and observer metadata.
5. Emit per-species aria2 input lists and per-species license manifests.

All heavy joins are executed with DuckDB to keep the workflow reproducible.
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
import tarfile
from pathlib import Path
from typing import Iterable, List, Optional

import duckdb
import requests


LOGGER = logging.getLogger("inat_photo_prepare")

INAT_METADATA_URL = (
    "https://inaturalist-open-data.s3.amazonaws.com/metadata/"
    "inaturalist-open-data-latest.tar.gz"
)

STAGE1_SOURCES = {
    "duke": "data/stage1/duke_worldflora_enriched.parquet",
    "eive": "data/stage1/eive_worldflora_enriched.parquet",
    "mabberly": "data/stage1/mabberly_worldflora_enriched.parquet",
    "try_enhanced": "data/stage1/tryenhanced_worldflora_enriched.parquet",
    "austraits": "data/stage1/austraits/austraits_taxa_worldflora_enriched.parquet",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build manifests and per-species download lists for iNaturalist photos."
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path("/home/olier/ellenberg"),
        help="Repository root (default: /home/olier/ellenberg).",
    )
    parser.add_argument(
        "--shortlist-parquet",
        type=Path,
        default=Path("data/stage1/stage1_shortlist_with_gbif.parquet"),
        help="Path to Stage 1 shortlist parquet.",
    )
    parser.add_argument(
        "--staging-dir",
        type=Path,
        default=Path("data/external/inat"),
        help="Directory to store metadata, manifests, and photos.",
    )
    parser.add_argument(
        "--metadata-url",
        default=INAT_METADATA_URL,
        help="iNaturalist metadata bundle URL.",
    )
    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Re-download metadata bundle even if it already exists.",
    )
    parser.add_argument(
        "--limit-species",
        type=int,
        default=None,
        help="Limit number of distinct WFO taxa processed (useful for dry runs).",
    )
    parser.add_argument(
        "--max-photos-per-species",
        type=int,
        default=None,
        help="Cap the number of photos captured per species (ordered by observed_on desc).",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity.",
    )
    return parser.parse_args()


def setup_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )


def ensure_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def download_metadata(url: str, dest: Path, force: bool = False) -> Path:
    if dest.exists() and not force:
        LOGGER.info("Metadata bundle already present at %s", dest)
        return dest

    ensure_directory(dest.parent)
    LOGGER.info("Downloading iNaturalist metadata bundle to %s", dest)

    with requests.get(url, stream=True, timeout=60) as resp:
        resp.raise_for_status()
        total = int(resp.headers.get("Content-Length", 0))
        chunk = 1024 * 1024
        written = 0
        with open(dest, "wb") as f:
            for block in resp.iter_content(chunk_size=chunk):
                if block:
                    f.write(block)
                    written += len(block)
                    if total:
                        pct = written / total * 100
                        LOGGER.debug("Download progress: %.1f%%", pct)

    LOGGER.info("Finished downloading %.2f MB", dest.stat().st_size / (1024 * 1024))
    return dest


def extract_metadata(archive: Path, target_dir: Path) -> None:
    ensure_directory(target_dir)
    marker = target_dir / ".extracted"
    if marker.exists() and marker.stat().st_mtime >= archive.stat().st_mtime:
        LOGGER.info("Metadata already extracted at %s", target_dir)
        return

    LOGGER.info("Extracting metadata bundle into %s", target_dir)
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(path=target_dir)
    marker.touch()


def run_duckdb(sql: str) -> None:
    LOGGER.debug("Executing DuckDB SQL:\n%s", sql)
    duckdb.execute(sql)


def create_original_lookup(output_path: Path, sources: dict[str, str]) -> None:
    if output_path.exists():
        LOGGER.info("Original-name lookup already exists at %s", output_path)
        return

    union_parts: List[str] = []
    for source, parquet_path in sources.items():
        union_parts.append(
            f"""
            SELECT '{source}' AS source,
                   wfo_taxon_id,
                   wfo_original_name AS original_name
            FROM read_parquet('{parquet_path}')
            WHERE wfo_original_name IS NOT NULL AND trim(wfo_original_name) <> ''
            """
        )

    sql = f"""
    COPY (
        SELECT DISTINCT source, wfo_taxon_id, original_name
        FROM (
            {' UNION ALL '.join(union_parts)}
        )
    ) TO '{output_path}'
      (FORMAT 'parquet', COMPRESSION ZSTD);
    """
    run_duckdb(sql)
    LOGGER.info("Created original-name lookup %s", output_path)


def create_shortlist_originals(
    shortlist_path: Path,
    lookup_parquet: Path,
    output_path: Path,
    limit_species: Optional[int] = None,
) -> None:
    if output_path.exists():
        LOGGER.info("Shortlist with original names already present at %s", output_path)
        return

    limit_clause = ""
    if limit_species is not None:
        limit_clause = f"""
        WHERE wfo_taxon_id IN (
            SELECT DISTINCT wfo_taxon_id
            FROM read_parquet('{shortlist_path}')
            ORDER BY wfo_taxon_id
            LIMIT {limit_species}
        )
        """

    sql = f"""
    COPY (
        SELECT
            sl.wfo_taxon_id,
            sl.canonical_name AS wfo_scientific_name,
            lk.source,
            lk.original_name
        FROM read_parquet('{shortlist_path}') sl
        JOIN read_parquet('{lookup_parquet}') lk
          ON lk.wfo_taxon_id = sl.wfo_taxon_id
        {limit_clause}
    ) TO '{output_path}'
      (FORMAT 'parquet', COMPRESSION ZSTD);
    """
    run_duckdb(sql)
    LOGGER.info("Prepared shortlist with original names -> %s", output_path)


def match_inat_taxa(
    shortlist_orig: Path,
    taxa_csv: Path,
    output_path: Path,
) -> None:
    if output_path.exists():
        LOGGER.info("Matched taxa file already exists at %s", output_path)
        return

    sql = f"""
    COPY (
        SELECT
            s.wfo_taxon_id,
            s.wfo_scientific_name,
            s.source,
            s.original_name,
            t.taxon_id,
            t.name AS inat_name,
            t.rank,
            t.active
        FROM read_parquet('{shortlist_orig}') s
        LEFT JOIN read_csv_auto('{taxa_csv}', delim='\t', header=TRUE) t
          ON lower(trim(s.original_name)) = lower(trim(t.name))
        WHERE t.rank = 'species' AND t.active = 'true'
    ) TO '{output_path}'
      (FORMAT 'parquet', COMPRESSION ZSTD);
    """
    run_duckdb(sql)
    LOGGER.info("Matched shortlist to iNaturalist taxa -> %s", output_path)


def build_photo_manifest(
    matched_taxa: Path,
    observations_csv: Path,
    photos_csv: Path,
    observers_csv: Path,
    output_path: Path,
    max_photos_per_species: Optional[int] = None,
) -> None:
    if output_path.exists():
        LOGGER.info("Photo manifest already present at %s", output_path)
        return

    limit_clause = ""
    if max_photos_per_species is not None:
        limit_clause = f"QUALIFY photo_rank <= {max_photos_per_species}"

    sql = f"""
    COPY (
        SELECT *
        FROM (
            SELECT
                mt.wfo_taxon_id,
                mt.wfo_scientific_name,
                mt.source,
                mt.original_name,
                mt.taxon_id,
                obs.observation_uuid,
                obs.quality_grade,
                obs.observed_on,
                obs.positional_accuracy,
                photos.photo_id,
                photos.extension,
                photos.license,
                obs.observer_id,
                photos.position,
                ROW_NUMBER() OVER (
                    PARTITION BY mt.wfo_taxon_id
                    ORDER BY obs.observed_on DESC NULLS LAST, photos.position ASC
                ) AS photo_rank
            FROM read_parquet('{matched_taxa}') mt
            JOIN read_csv_auto('{observations_csv}', delim='\\t', header=TRUE) obs
              ON obs.taxon_id = mt.taxon_id
            JOIN read_csv_auto('{photos_csv}', delim='\\t', header=TRUE) photos
              ON photos.observation_uuid = obs.observation_uuid
            WHERE obs.quality_grade IN ('research', 'needs_id')
        )
        {limit_clause}
    ) TO '{output_path}'
      (FORMAT 'parquet', COMPRESSION ZSTD);
    """
    run_duckdb(sql)
    LOGGER.info("Created photo manifest -> %s", output_path)

    # Enrich with observer metadata and photo urls (written separately to keep SQL readable)
    enriched_path = output_path.with_name(output_path.stem + "_enriched.parquet")
    sql_enriched = f"""
    COPY (
        SELECT
            pm.*,
            obsr.login,
            obsr.name AS observer_name,
            'https://inaturalist-open-data.s3.amazonaws.com/photos/'
              || pm.photo_id || '/large.' || pm.extension AS photo_url
        FROM read_parquet('{output_path}') pm
        LEFT JOIN read_csv_auto('{observers_csv}', delim='\\t', header=TRUE) obsr
          ON obsr.observer_id = pm.observer_id
    ) TO '{enriched_path}'
      (FORMAT 'parquet', COMPRESSION ZSTD);
    """
    run_duckdb(sql_enriched)
    LOGGER.info("Enriched manifest with observer metadata -> %s", enriched_path)


def emit_species_lists(manifest_parquet: Path, manifest_dir: Path, photo_root: Path) -> None:
    ensure_directory(manifest_dir)
    ensure_directory(photo_root)

    urls_export = manifest_dir / "species_urls.tsv"
    sql = f"""
    COPY (
        SELECT
            replace(lower(pm.wfo_scientific_name), ' ', '_') AS species_slug,
            pm.wfo_taxon_id,
            pm.wfo_scientific_name,
            pm.original_name,
            pm.photo_url,
            pm.photo_id || '_large.' || pm.extension AS photo_filename,
            pm.license,
            pm.login,
            pm.observer_name,
            pm.photo_rank
        FROM read_parquet('{manifest_parquet}') AS pm
        ORDER BY 1, pm.photo_rank
    ) TO '{urls_export}'
      (HEADER, DELIMITER '\\t');
    """
    run_duckdb(sql)
    LOGGER.info("Exported species URL staging table -> %s", urls_export)

    species_lists_dir = manifest_dir / "species_lists"
    ensure_directory(species_lists_dir)

    with urls_export.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        current_slug: Optional[str] = None
        url_file = None
        license_writer = None
        license_file = None

        seen_files = set()

        for row in reader:
            slug = row["species_slug"]
            species_dir = photo_root / slug
            ensure_directory(species_dir)

            if slug != current_slug:
                if url_file:
                    url_file.close()
                if license_file:
                    license_file.close()
                seen_files = set()

                url_path = species_lists_dir / f"{slug}.txt"
                url_file = url_path.open("w", encoding="utf-8")

                license_path = species_dir / "license_manifest.csv"
                license_file = license_path.open("w", encoding="utf-8", newline="")
                license_writer = csv.DictWriter(
                    license_file,
                    fieldnames=[
                        "wfo_taxon_id",
                        "wfo_scientific_name",
                        "original_name",
                        "photo_filename",
                        "photo_url",
                        "license",
                        "login",
                        "observer_name",
                    ],
                )
                license_writer.writeheader()

                current_slug = slug

            if url_file is None or license_writer is None:
                raise RuntimeError("Expected open file handles for species processing.")

            filename = row["photo_filename"]
            if filename in seen_files:
                continue
            seen_files.add(filename)

            url_file.write(f"{row['photo_url']}\n  out={row['photo_filename']}\n")
            license_writer.writerow(
                {
                    "wfo_taxon_id": row["wfo_taxon_id"],
                    "wfo_scientific_name": row["wfo_scientific_name"],
                    "original_name": row["original_name"],
                    "photo_filename": row["photo_filename"],
                    "photo_url": row["photo_url"],
                    "license": row["license"],
                    "login": row["login"],
                    "observer_name": row["observer_name"],
                }
            )

        if url_file:
            url_file.close()
        if license_file:
            license_file.close()

    LOGGER.info("Generated per-species aria2 lists under %s", species_lists_dir)
    urls_export.unlink(missing_ok=True)


def main() -> None:
    args = parse_args()
    setup_logging(args.log_level)

    project_root = args.project_root.resolve()
    shortlist_parquet = (project_root / args.shortlist_parquet).resolve()
    staging_dir = (project_root / args.staging_dir).resolve()
    manifest_dir = staging_dir / "manifests"
    latest_dir = staging_dir / "latest"
    photo_root = staging_dir / "photos_large"

    ensure_directory(manifest_dir)
    ensure_directory(photo_root)

    bundle_path = download_metadata(
        args.metadata_url, staging_dir / "inaturalist-open-data-latest.tar.gz", args.force_download
    )
    extract_metadata(bundle_path, latest_dir)

    create_original_lookup(manifest_dir / "stage1_original_name_lookup.parquet", STAGE1_SOURCES)
    create_shortlist_originals(
        shortlist_parquet,
        manifest_dir / "stage1_original_name_lookup.parquet",
        manifest_dir / "stage1_shortlist_original_names.parquet",
        limit_species=args.limit_species,
    )

    metadata_root = latest_dir
    if not (metadata_root / "taxa.csv").exists():
        subdirs = [p for p in metadata_root.iterdir() if p.is_dir()]
        if len(subdirs) == 1:
            metadata_root = subdirs[0]

    taxa_csv = metadata_root / "taxa.csv"
    observations_csv = metadata_root / "observations.csv"
    photos_csv = metadata_root / "photos.csv"
    observers_csv = metadata_root / "observers.csv"

    if not (taxa_csv.exists() and observations_csv.exists() and photos_csv.exists()):
        raise FileNotFoundError(
            "Expected metadata files taxa.csv, observations.csv, and photos.csv under "
            f"{latest_dir}. Check the extracted tarball."
        )

    match_inat_taxa(
        manifest_dir / "stage1_shortlist_original_names.parquet",
        taxa_csv,
        manifest_dir / "stage1_shortlist_inat_taxa.parquet",
    )

    build_photo_manifest(
        manifest_dir / "stage1_shortlist_inat_taxa.parquet",
        observations_csv,
        photos_csv,
        observers_csv,
        manifest_dir / "stage1_inat_photo_manifest.parquet",
        max_photos_per_species=args.max_photos_per_species,
    )

    emit_species_lists(
        manifest_dir / "stage1_inat_photo_manifest_enriched.parquet",
        manifest_dir,
        photo_root,
    )

    LOGGER.info("Preparation complete. Species lists and manifests ready for aria2 downloads.")


if __name__ == "__main__":
    main()
