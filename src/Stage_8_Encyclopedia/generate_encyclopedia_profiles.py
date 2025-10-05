#!/usr/bin/env python3
"""Generate encyclopedia-ready JSON profiles for frontend display.

Profile structure optimized for frontend engine:
- Actual EIVE values (expert-given) with fallback to predictions
- Reliability scores from Stage 7 validation
- GloBI interaction data
- GBIF occurrence coordinates for map display
- Compact JSON format for web delivery

Output: data/encyclopedia_profiles/{species-slug}.json
"""

from pathlib import Path
import pandas as pd
import numpy as np
import json
import logging
from typing import Optional, Dict, List

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]
COMPREHENSIVE = REPO_ROOT / "data/comprehensive_dataset_no_soil_with_gbif.csv"
DIMENSIONS = REPO_ROOT / "data/legacy_dimensions_matched.csv"
STAGE7_PROFILES = REPO_ROOT / "data/stage7_validation_profiles"
OUTPUT_DIR = REPO_ROOT / "data/encyclopedia_profiles"


class EncyclopediaProfileGenerator:
    """Generate frontend-ready encyclopedia profiles."""

    def __init__(self):
        """Load comprehensive dataset and dimensions."""
        logger.info("Loading comprehensive dataset...")
        self.df = pd.read_csv(COMPREHENSIVE)
        logger.info(f"  Loaded {len(self.df)} species")

        # Load dimension data if available
        if DIMENSIONS.exists():
            logger.info("Loading dimension data...")
            self.dimensions = pd.read_csv(DIMENSIONS)
            # Create lookup by species name
            self.dim_lookup = {row['encyclopedia_species']: row for _, row in self.dimensions.iterrows()}
            logger.info(f"  Loaded {len(self.dimensions)} species with dimensions ({len(self.dimensions)/len(self.df)*100:.1f}% coverage)\n")
        else:
            logger.info("  No dimension data found\n")
            self.dim_lookup = {}

    def extract_eive_values(self, row) -> Dict[str, Optional[float]]:
        """Extract actual EIVE values (already expert-given in dataset)."""
        return {
            'L': self._safe_float(row.get('EIVEres-L')),
            'M': self._safe_float(row.get('EIVEres-M')),
            'R': self._safe_float(row.get('EIVEres-R')),
            'N': self._safe_float(row.get('EIVEres-N')),
            'T': self._safe_float(row.get('EIVEres-T')),
        }

    def extract_eive_labels(self, row) -> Dict[str, Optional[str]]:
        """Extract qualitative EIVE labels."""
        return {
            'L': self._safe_str(row.get('L_label')),
            'M': self._safe_str(row.get('M_label')),
            'R': self._safe_str(row.get('R_label')),
            'N': self._safe_str(row.get('N_label')),
            'T': self._safe_str(row.get('T_label')),
        }

    def extract_reliability(self, row) -> Optional[Dict[str, Dict]]:
        """Extract Stage 7 reliability metrics."""
        # Check if reliability data exists
        if pd.isna(row.get('L_verdict')):
            return None

        reliability = {}
        for axis in ['L', 'M', 'R', 'N', 'T']:
            reliability[axis] = {
                'verdict': self._safe_str(row.get(f'{axis}_verdict')),
                'score': self._safe_float(row.get(f'{axis}_reliability_score')),
                'label': self._safe_str(row.get(f'{axis}_reliability_label')),
                'confidence': self._safe_float(row.get(f'{axis}_confidence')),
            }

        return reliability

    def extract_globi_interactions(self, row) -> Dict[str, Dict]:
        """Extract GloBI interaction data."""
        return {
            'pollination': {
                'records': self._safe_int(row.get('globi_pollination_records')),
                'partners': self._safe_int(row.get('globi_pollination_partners')),
                'top_partners': self._parse_top_partners(row.get('globi_pollination_top_partners')),
            },
            'herbivory': {
                'records': self._safe_int(row.get('globi_herbivory_records')),
                'partners': self._safe_int(row.get('globi_herbivory_partners')),
                'top_partners': self._parse_top_partners(row.get('globi_herbivory_top_partners')),
            },
            'pathogen': {
                'records': self._safe_int(row.get('globi_pathogen_records')),
                'partners': self._safe_int(row.get('globi_pathogen_partners')),
                'top_partners': self._parse_top_partners(row.get('globi_pathogen_top_partners')),
            },
        }

    def extract_gbif_coordinates(self, row) -> Optional[List[Dict]]:
        """Extract GBIF occurrence coordinates for map display."""
        gbif_path = row.get('gbif_file_path')
        if pd.isna(gbif_path) or not Path(gbif_path).exists():
            return None

        try:
            # Load GBIF occurrences
            gbif_df = pd.read_csv(gbif_path, compression='gzip', sep='\t', low_memory=False)

            # Extract coordinates with timestamps
            coords = gbif_df[['decimalLatitude', 'decimalLongitude', 'year', 'countryCode']].dropna(
                subset=['decimalLatitude', 'decimalLongitude']
            )

            # Subsample if too many (max 1000 for frontend performance)
            if len(coords) > 1000:
                coords = coords.sample(1000, random_state=42)

            # Convert to list of dicts
            coordinate_list = []
            for _, coord in coords.iterrows():
                coordinate_list.append({
                    'lat': float(coord['decimalLatitude']),
                    'lon': float(coord['decimalLongitude']),
                    'year': int(coord['year']) if pd.notna(coord['year']) else None,
                    'country': self._safe_str(coord.get('countryCode')),
                })

            return coordinate_list if len(coordinate_list) > 0 else None

        except Exception as e:
            logger.warning(f"  Could not load GBIF coordinates: {e}")
            return None

    def extract_taxonomy(self, row) -> Dict[str, str]:
        """Extract taxonomic information."""
        return {
            'family': self._safe_str(row.get('Family')),
            'genus': self._safe_str(row.get('Genus')),
            'species': self._safe_str(row.get('wfo_accepted_name')),
        }

    def extract_traits(self, row) -> Dict:
        """Extract key functional traits for display."""
        return {
            'growth_form': self._safe_str(row.get('Growth Form')),
            'woodiness': self._safe_str(row.get('Woodiness')),
            'height_m': self._safe_float(row.get('Plant height (m)')),
            'leaf_type': self._safe_str(row.get('Leaf type')),
            'phenology': self._safe_str(row.get('Leaf_phenology')),
            'mycorrhizal': self._safe_str(row.get('Myco_Group_Final')),
        }

    def extract_dimensions(self, species_name: str) -> Optional[Dict]:
        """Extract dimension data from legacy profiles if available."""
        if species_name not in self.dim_lookup:
            return None

        dim_row = self.dim_lookup[species_name]

        # Build dimensions structure matching legacy format
        dimensions = {}

        # Above ground dimensions
        above_ground = {}
        if pd.notna(dim_row.get('height_min_m')):
            above_ground['height_min_m'] = float(dim_row['height_min_m'])
        if pd.notna(dim_row.get('height_max_m')):
            above_ground['height_max_m'] = float(dim_row['height_max_m'])
        if pd.notna(dim_row.get('spread_min_m')):
            above_ground['spread_min_m'] = float(dim_row['spread_min_m'])
        if pd.notna(dim_row.get('spread_max_m')):
            above_ground['spread_max_m'] = float(dim_row['spread_max_m'])
        if pd.notna(dim_row.get('height_qualitative')):
            above_ground['qualitative_comments'] = str(dim_row['height_qualitative'])

        if above_ground:
            dimensions['above_ground'] = above_ground

        # Root system dimensions
        root_system = {}
        if pd.notna(dim_row.get('root_depth_min_m')):
            root_system['depth_min_m'] = float(dim_row['root_depth_min_m'])
        if pd.notna(dim_row.get('root_depth_max_m')):
            root_system['depth_max_m'] = float(dim_row['root_depth_max_m'])
        if pd.notna(dim_row.get('root_spread_min_m')):
            root_system['spread_min_m'] = float(dim_row['root_spread_min_m'])
        if pd.notna(dim_row.get('root_spread_max_m')):
            root_system['spread_max_m'] = float(dim_row['root_spread_max_m'])
        if pd.notna(dim_row.get('root_qualitative')):
            root_system['qualitative_comments'] = str(dim_row['root_qualitative'])

        if root_system:
            dimensions['root_system'] = root_system

        return dimensions if dimensions else None

    def extract_bioclim(self, row) -> Optional[Dict]:
        """Extract bioclim climate variables averaged from occurrence data."""
        # Check if bioclim data exists
        if pd.isna(row.get('bio1_mean')):
            return None

        return {
            'temperature': {
                'annual_mean_C': self._safe_float(row.get('bio1_mean')),
                'max_warmest_month_C': self._safe_float(row.get('bio5_mean')),
                'min_coldest_month_C': self._safe_float(row.get('bio6_mean')),
                'annual_range_C': self._safe_float(row.get('bio7_mean')),
                'seasonality': self._safe_float(row.get('bio4_mean')),
            },
            'precipitation': {
                'annual_mm': self._safe_float(row.get('bio12_mean')),
                'wettest_month_mm': self._safe_float(row.get('bio13_mean')),
                'driest_month_mm': self._safe_float(row.get('bio14_mean')),
                'seasonality': self._safe_float(row.get('bio15_mean')),
            },
            'aridity': {
                'index_mean': self._safe_float(row.get('AI_mean')),
            },
            'data_quality': {
                'n_occurrences': self._safe_int(row.get('n_occurrences_bioclim')),
                'sufficient_data': bool(row.get('has_sufficient_data_bioclim')),
            }
        }

    def extract_stage7_content(self, species_name: str) -> Optional[Dict]:
        """Extract full Stage 7 validation profile content if available."""
        slug = species_name.lower().replace(' ', '-')
        stage7_path = STAGE7_PROFILES / f"{slug}.json"

        if not stage7_path.exists():
            return None

        try:
            with open(stage7_path, 'r', encoding='utf-8') as f:
                profile = json.load(f)

            # Extract all Stage 7 sections for legacy compatibility
            return {
                'common_names': profile.get('common_names', {}),
                'description': profile.get('description', {}),
                'climate_requirements': profile.get('climate_requirements', {}),
                'environmental_requirements': profile.get('environmental_requirements', {}),
                'cultivation_and_propagation': profile.get('cultivation_and_propagation', {}),
                'ecological_interactions': profile.get('ecological_interactions', {}),
                'uses_harvest_and_storage': profile.get('uses_harvest_and_storage', {}),
                'distribution_and_conservation': profile.get('distribution_and_conservation', {}),
            }
        except Exception as e:
            logger.warning(f"  Could not load Stage 7 profile for {species_name}: {e}")
            return None

    def generate_profile(self, species_name: str) -> Dict:
        """Generate encyclopedia profile for a single species."""
        row = self.df[self.df['wfo_accepted_name'] == species_name]
        if row.empty:
            raise ValueError(f"Species '{species_name}' not found")

        row = row.iloc[0]

        # Build base profile with EIVE, traits, dimensions, interactions, occurrences, bioclim
        profile = {
            'species': species_name,
            'slug': species_name.lower().replace(' ', '-'),
            'taxonomy': self.extract_taxonomy(row),
            'eive': {
                'values': self.extract_eive_values(row),
                'labels': self.extract_eive_labels(row),
                'source': 'expert'  # These are actual values from the dataset
            },
            'reliability': self.extract_reliability(row),
            'traits': self.extract_traits(row),
            'dimensions': self.extract_dimensions(species_name),
            'bioclim': self.extract_bioclim(row),
            'interactions': self.extract_globi_interactions(row),
            'occurrences': {
                'count': self._safe_int(row.get('n_occurrences')),
                'coordinates': self.extract_gbif_coordinates(row),
            },
        }

        # Merge Stage 7 content if available (for legacy frontend compatibility)
        stage7_content = self.extract_stage7_content(species_name)
        if stage7_content:
            profile['stage7'] = stage7_content

        return profile

    def generate_batch(self, species_list: List[str], skip_coordinates: bool = False) -> int:
        """Generate profiles for multiple species."""
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        success = 0
        with_stage7 = 0
        for i, species in enumerate(species_list, 1):
            if i % 100 == 0:
                logger.info(f"  Processed {i}/{len(species_list)} species...")

            try:
                profile = self.generate_profile(species)

                # Track Stage 7 coverage
                if profile.get('stage7'):
                    with_stage7 += 1

                # Optionally skip coordinate extraction for speed
                if skip_coordinates:
                    profile['occurrences']['coordinates'] = None

                # Save to JSON
                slug = profile['slug']
                output_path = OUTPUT_DIR / f"{slug}.json"
                with open(output_path, 'w', encoding='utf-8') as f:
                    json.dump(profile, f, indent=2, ensure_ascii=False)

                success += 1

            except Exception as e:
                logger.warning(f"  Error generating profile for {species}: {e}")

        logger.info(f"\n✓ Profiles with Stage 7 content: {with_stage7}/{success} ({with_stage7/success*100:.1f}%)")
        return success

    # Helper methods for safe type conversion
    def _safe_float(self, value) -> Optional[float]:
        """Convert to float, return None if invalid."""
        if pd.isna(value):
            return None
        try:
            return round(float(value), 2)
        except (ValueError, TypeError):
            return None

    def _safe_int(self, value) -> Optional[int]:
        """Convert to int, return None if invalid."""
        if pd.isna(value):
            return None
        try:
            return int(value)
        except (ValueError, TypeError):
            return None

    def _safe_str(self, value) -> Optional[str]:
        """Convert to string, return None if invalid."""
        if pd.isna(value):
            return None
        return str(value)

    def _parse_top_partners(self, value) -> Optional[List[str]]:
        """Parse top partners string into list."""
        if pd.isna(value) or not value:
            return None
        # GloBI format: "Species A (123); Species B (45); ..."
        partners = [p.strip() for p in str(value).split(';') if p.strip()]
        return partners if len(partners) > 0 else None


def main():
    """Generate encyclopedia profiles for all 654 species."""
    import argparse

    parser = argparse.ArgumentParser(description="Generate encyclopedia JSON profiles")
    parser.add_argument('--species', help='Single species to generate (default: all)')
    parser.add_argument('--skip-coords', action='store_true', help='Skip coordinate extraction for speed')
    parser.add_argument('--limit', type=int, help='Limit number of species (for testing)')
    args = parser.parse_args()

    logger.info("=== Encyclopedia Profile Generator ===\n")

    generator = EncyclopediaProfileGenerator()

    if args.species:
        # Generate single species
        logger.info(f"Generating profile for: {args.species}")
        profile = generator.generate_profile(args.species)
        slug = profile['slug']
        output_path = OUTPUT_DIR / f"{slug}.json"
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(profile, f, indent=2, ensure_ascii=False)
        logger.info(f"  Saved to {output_path}")

    else:
        # Generate all species
        species_list = generator.df['wfo_accepted_name'].tolist()
        if args.limit:
            species_list = species_list[:args.limit]

        logger.info(f"Generating {len(species_list)} encyclopedia profiles...")
        if args.skip_coords:
            logger.info("  (skipping coordinate extraction for speed)\n")

        success = generator.generate_batch(species_list, skip_coordinates=args.skip_coords)

        logger.info(f"\n✓ Generated {success}/{len(species_list)} profiles")
        logger.info(f"  Output directory: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
