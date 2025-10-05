#!/usr/bin/env python3
"""Build GBIF occurrence index and add file paths to comprehensive dataset.

Creates:
1. data/gbif_occurrence_index.csv - lookup table with GBIF metadata
2. Updates comprehensive dataset with gbif_file_path column
"""

from pathlib import Path
import pandas as pd
import gzip
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
GBIF_DIR = Path("/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete")
COMPREHENSIVE = REPO_ROOT / "data/comprehensive_dataset_no_soil.csv"
INDEX_OUTPUT = REPO_ROOT / "data/gbif_occurrence_index.csv"


def species_to_slug(species_name):
    """Convert species name to GBIF file slug."""
    return species_name.lower().replace(' ', '-')


def analyze_gbif_file(gbif_path):
    """Extract metadata from GBIF occurrence file."""
    try:
        df = pd.read_csv(gbif_path, compression='gzip', sep='\t', low_memory=False)

        # Basic counts
        n_records = len(df)

        # Date range
        years = df['year'].dropna()
        earliest = int(years.min()) if len(years) > 0 else None
        latest = int(years.max()) if len(years) > 0 else None

        # Spatial coverage
        countries = df['countryCode'].dropna().nunique()
        has_coords = df['decimalLatitude'].notna().sum() > 0

        # Elevation data
        has_elevation = df['elevation'].notna().sum() > 0

        # Occurrence types
        basis_counts = df['basisOfRecord'].value_counts().to_dict()

        return {
            'n_records': n_records,
            'earliest_year': earliest,
            'latest_year': latest,
            'country_count': countries,
            'has_coords': has_coords,
            'has_elevation': has_elevation,
            'n_preserved': basis_counts.get('PRESERVED_SPECIMEN', 0),
            'n_observation': basis_counts.get('HUMAN_OBSERVATION', 0) + basis_counts.get('OBSERVATION', 0),
            'n_living': basis_counts.get('LIVING_SPECIMEN', 0),
        }
    except Exception as e:
        logger.warning(f"  Error reading {gbif_path.name}: {e}")
        return None


def build_gbif_index(species_list):
    """Build GBIF occurrence index for species in comprehensive dataset."""
    logger.info("Building GBIF occurrence index...")

    index_data = []
    found = 0
    missing = 0

    for i, species in enumerate(species_list, 1):
        if i % 100 == 0:
            logger.info(f"  Processed {i}/{len(species_list)} species...")

        slug = species_to_slug(species)
        gbif_file = GBIF_DIR / f"{slug}.csv.gz"

        if not gbif_file.exists():
            missing += 1
            index_data.append({
                'wfo_accepted_name': species,
                'gbif_slug': slug,
                'gbif_file_path': None,
                'file_exists': False,
            })
            continue

        found += 1
        metadata = analyze_gbif_file(gbif_file)

        if metadata:
            index_data.append({
                'wfo_accepted_name': species,
                'gbif_slug': slug,
                'gbif_file_path': str(gbif_file),
                'file_exists': True,
                **metadata
            })
        else:
            index_data.append({
                'wfo_accepted_name': species,
                'gbif_slug': slug,
                'gbif_file_path': str(gbif_file),
                'file_exists': True,
            })

    logger.info(f"  Found GBIF files: {found}/{len(species_list)}")
    logger.info(f"  Missing GBIF files: {missing}/{len(species_list)}")

    return pd.DataFrame(index_data)


def add_gbif_path_to_comprehensive(df):
    """Add gbif_file_path column to comprehensive dataset."""
    logger.info("Adding GBIF file path to comprehensive dataset...")

    def get_gbif_path(species):
        slug = species_to_slug(species)
        path = GBIF_DIR / f"{slug}.csv.gz"
        return str(path) if path.exists() else None

    df['gbif_file_path'] = df['wfo_accepted_name'].apply(get_gbif_path)
    df['has_gbif_data'] = df['gbif_file_path'].notna()

    logger.info(f"  Species with GBIF data: {df['has_gbif_data'].sum()}/{len(df)}")

    return df


def main():
    logger.info("\n=== Building GBIF Linking Infrastructure ===\n")

    # Load comprehensive dataset
    logger.info(f"Loading comprehensive dataset from {COMPREHENSIVE.name}...")
    df = pd.read_csv(COMPREHENSIVE)
    species_list = df['wfo_accepted_name'].tolist()
    logger.info(f"  Loaded {len(species_list)} species\n")

    # Build GBIF index
    gbif_index = build_gbif_index(species_list)

    # Save index
    logger.info(f"\nSaving GBIF index to {INDEX_OUTPUT.name}...")
    gbif_index.to_csv(INDEX_OUTPUT, index=False)
    logger.info(f"  Saved {len(gbif_index)} rows × {len(gbif_index.columns)} columns")

    # Add path column to comprehensive dataset
    df_updated = add_gbif_path_to_comprehensive(df)

    # Save updated comprehensive dataset
    output_path = COMPREHENSIVE.parent / "comprehensive_dataset_no_soil_with_gbif.csv"
    logger.info(f"\nSaving updated comprehensive dataset to {output_path.name}...")
    df_updated.to_csv(output_path, index=False)
    logger.info(f"  Saved {len(df_updated)} rows × {len(df_updated.columns)} columns")

    logger.info("\n=== Summary ===")
    logger.info(f"GBIF index: {INDEX_OUTPUT}")
    logger.info(f"  - Species with GBIF files: {gbif_index['file_exists'].sum()}")
    logger.info(f"  - Average records per species: {gbif_index['n_records'].mean():.1f}" if 'n_records' in gbif_index.columns else "")
    logger.info(f"\nUpdated dataset: {output_path}")
    logger.info(f"  - Added columns: gbif_file_path, has_gbif_data")
    logger.info(f"  - Species with GBIF data: {df_updated['has_gbif_data'].sum()}/{len(df_updated)}")

    logger.info("\n✓ GBIF linking infrastructure complete!")


if __name__ == "__main__":
    main()
