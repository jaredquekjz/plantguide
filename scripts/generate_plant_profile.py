#!/usr/bin/env python3
"""Generate comprehensive plant profile reports combining all data sources.

Combines:
- Comprehensive dataset (traits, bioclim, GloBI, EIVE, Stage 7)
- GBIF occurrence data (on-demand loading)
- Spatial visualizations
- Validation reliability metrics

Usage:
    python scripts/generate_plant_profile.py "Abies alba"
    python scripts/generate_plant_profile.py "Abies alba" --format markdown
    python scripts/generate_plant_profile.py "Abies alba" --format json --output profiles/
"""

import argparse
import json
from pathlib import Path
import pandas as pd
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPREHENSIVE = REPO_ROOT / "data/comprehensive_dataset_no_soil_with_gbif.csv"
GBIF_INDEX = REPO_ROOT / "data/gbif_occurrence_index.csv"
SOIL_SUMMARY = REPO_ROOT / "data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv"


class PlantProfileGenerator:
    def __init__(self):
        """Initialize with comprehensive dataset, GBIF index, and soil data."""
        logger.info("Loading datasets...")
        self.comprehensive = pd.read_csv(COMPREHENSIVE)
        self.gbif_index = pd.read_csv(GBIF_INDEX)
        self.soil_data = pd.read_csv(SOIL_SUMMARY) if SOIL_SUMMARY.exists() else None
        logger.info(f"  Loaded {len(self.comprehensive)} species")
        if self.soil_data is not None:
            logger.info(f"  Loaded soil data for {len(self.soil_data)} species")

    def get_species_data(self, species_name):
        """Get all data for a single species."""
        row = self.comprehensive[self.comprehensive['wfo_accepted_name'] == species_name]
        if row.empty:
            raise ValueError(f"Species '{species_name}' not found in dataset")
        return row.iloc[0]

    def load_gbif_occurrences(self, species_name):
        """Load GBIF occurrence data for species."""
        gbif_row = self.gbif_index[self.gbif_index['wfo_accepted_name'] == species_name]
        if gbif_row.empty or pd.isna(gbif_row.iloc[0]['gbif_file_path']):
            return None

        gbif_path = Path(gbif_row.iloc[0]['gbif_file_path'])
        if not gbif_path.exists():
            return None

        try:
            return pd.read_csv(gbif_path, compression='gzip', sep='\t', low_memory=False)
        except Exception as e:
            logger.warning(f"  Could not load GBIF data: {e}")
            return None

    def format_eive_section(self, data):
        """Format EIVE predictions in upload-compatible structure."""
        return {
            'values': {
                'L': data.get('EIVEres-L'),
                'M': data.get('EIVEres-M'),
                'R': data.get('EIVEres-R'),
                'N': data.get('EIVEres-N'),
                'T': data.get('EIVEres-T'),
            },
            'labels': {
                'L': data.get('L_label'),
                'M': data.get('M_label'),
                'R': data.get('R_label'),
                'N': data.get('N_label'),
                'T': data.get('T_label'),
            },
            'source': 'model'  # Generated from XGBoost predictions
        }

    def format_reliability_section(self, data):
        """Format reliability/validation metrics if available."""
        if pd.isna(data.get('L_verdict')):
            return None

        reliability = {}
        for axis in ['L', 'M', 'R', 'N', 'T']:
            reliability[axis] = {
                'verdict': data.get(f'{axis}_verdict'),
                'reliability_score': data.get(f'{axis}_reliability_score'),
                'reliability_label': data.get(f'{axis}_reliability_label'),
                'confidence': data.get(f'{axis}_confidence'),
                'verdict_numeric': data.get(f'{axis}_verdict_numeric'),
                'support_count': data.get(f'{axis}_support_count'),
                'contradict_count': data.get(f'{axis}_contradict_count'),
                'strength': data.get(f'{axis}_strength'),
                'has_conflict': data.get(f'{axis}_has_conflict'),
            }
        return reliability

    def format_taxonomy_section(self, data):
        """Format taxonomy information."""
        return {
            'family': data.get('Family'),
            'genus': data.get('Genus'),
            'species': data.get('wfo_accepted_name'),
        }

    def format_traits_section(self, data):
        """Format plant functional traits."""
        return {
            'taxonomy': {
                'genus': data.get('Genus'),
                'family': data.get('Family'),
            },
            'morphology': {
                'woodiness': data.get('Woodiness'),
                'growth_form': data.get('Growth Form'),
                'plant_height_m': data.get('Plant height (m)'),
                'leaf_area_mm2': data.get('Leaf area (mm2)'),
                'ssd_mg_mm3': data.get('SSD used (mg/mm3)'),
            },
            'leaf_traits': {
                'leaf_type': data.get('Leaf type'),
                'lma_g_m2': data.get('LMA (g/m2)'),
                'nmass_mg_g': data.get('Nmass (mg/g)'),
                'ldmc': data.get('LDMC'),
                'phenology': data.get('Leaf_phenology'),
                'photosynthesis': data.get('Photosynthesis_pathway'),
            },
            'mycorrhizal': data.get('Myco_Group_Final'),
        }

    def format_climate_section(self, data):
        """Format bioclim variables."""
        def scaled(value, factor=1.0):
            if pd.isna(value):
                return None
            return float(value) * factor

        annual_mean = scaled(data.get('bio1_mean'))
        warmest_high = scaled(data.get('bio5_mean'), 0.1)
        coldest_low = scaled(data.get('bio6_mean'), 0.1)
        annual_range = None
        if warmest_high is not None and coldest_low is not None:
            annual_range = warmest_high - coldest_low

        return {
            'temperature': {
                'annual_mean_C': annual_mean,
                'warmest_month_high_C': warmest_high,
                'coldest_month_low_C': coldest_low,
                'annual_range_C': annual_range,
                'seasonality_sd_C': scaled(data.get('bio4_mean'), 0.01),
            },
            'precipitation': {
                'annual_mm': scaled(data.get('bio12_mean'), 100.0),
                'wettest_month_mm': scaled(data.get('bio13_mean'), 10.0),
                'driest_month_mm': scaled(data.get('bio14_mean'), 0.1),
                'seasonality_cv': scaled(data.get('bio15_mean')),
            },
            'aridity': {
                'index_mean': scaled(data.get('AI_mean')),
            },
            'occurrence_summary': {
                'n_occurrences': int(data.get('n_occurrences')) if pd.notna(data.get('n_occurrences')) else None,
                'n_unique_coords': int(data.get('n_unique_coords')) if pd.notna(data.get('n_unique_coords')) else None,
            }
        }

    def format_soil_section(self, species_name):
        """Format SoilGrids-derived soil data with friendly summaries."""
        if self.soil_data is None:
            return None

        soil_row = self.soil_data[self.soil_data['species'] == species_name]
        if soil_row.empty:
            return None

        data = soil_row.iloc[0]

        topsoil_depths = ['0_5cm', '5_15cm', '15_30cm']
        subsoil_depths = ['30_60cm', '60_100cm']
        deep_depths = ['100_200cm']

        def summarise(prefix, depths):
            values = []
            for depth in depths:
                value = data.get(f'{prefix}_{depth}_mean')
                if pd.notna(value):
                    values.append(value)
            if not values:
                return None
            return float(pd.Series(values).mean())

        def build_metric(config):
            topsoil_value = summarise(config['prefix'], topsoil_depths)
            subsoil_value = summarise(config['prefix'], subsoil_depths)
            deep_value = summarise(config['prefix'], deep_depths)

            if topsoil_value is None and subsoil_value is None and deep_value is None:
                return None

            metric = {
                'key': config['key'],
                'label': config['label'],
                'units': config.get('units'),
                'description': config.get('description'),
            }

            if topsoil_value is not None:
                metric['topsoil'] = {'mean': topsoil_value}
            if subsoil_value is not None:
                metric['subsoil'] = {'mean': subsoil_value}
            if deep_value is not None:
                metric['deep'] = {'mean': deep_value}

            return metric

        metric_definitions = [
            {
                'key': 'organic_matter',
                'prefix': 'soc',
                'label': 'Organic matter',
                'units': 'g/kg',
                'description': 'Stored plant material that keeps soil springy and full of life.'
            },
            {
                'key': 'clay_content',
                'prefix': 'clay',
                'label': 'Fine particles (clay)',
                'units': '%',
                'description': 'Clay helps soils hold onto water and nutrients.'
            },
            {
                'key': 'sand_content',
                'prefix': 'sand',
                'label': 'Coarse particles (sand)',
                'units': '%',
                'description': 'Sand keeps soils light and free-draining.'
            },
            {
                'key': 'nutrient_capacity',
                'prefix': 'cec',
                'label': 'Nutrient capacity',
                'units': 'cmol(+)/kg',
                'description': 'Higher values mean the soil can store more nutrients for roots.'
            },
            {
                'key': 'nitrogen',
                'prefix': 'nitrogen',
                'label': 'Total nitrogen',
                'units': 'g/kg',
                'description': 'Plant-available nitrogen that drives leafy growth.'
            },
            {
                'key': 'bulk_density',
                'prefix': 'bdod',
                'label': 'Soil density',
                'units': 'g/cm³',
                'description': 'How tightly packed the soil is—a guide to compaction and aeration.'
            }
        ]

        soil_metrics = []
        for metric_config in metric_definitions:
            metric = build_metric(metric_config)
            if metric is not None:
                soil_metrics.append(metric)

        # Return pH data at multiple depth layers with statistics
        return {
            'pH': {
                'surface_0_5cm': {
                    'mean': data.get('phh2o_0_5cm_mean'),
                    'p10': data.get('phh2o_0_5cm_p10'),
                    'median': data.get('phh2o_0_5cm_p50'),
                    'p90': data.get('phh2o_0_5cm_p90'),
                    'sd': data.get('phh2o_0_5cm_sd'),
                },
                'shallow_5_15cm': {
                    'mean': data.get('phh2o_5_15cm_mean'),
                    'p10': data.get('phh2o_5_15cm_p10'),
                    'median': data.get('phh2o_5_15cm_p50'),
                    'p90': data.get('phh2o_5_15cm_p90'),
                    'sd': data.get('phh2o_5_15cm_sd'),
                },
                'medium_15_30cm': {
                    'mean': data.get('phh2o_15_30cm_mean'),
                    'p10': data.get('phh2o_15_30cm_p10'),
                    'median': data.get('phh2o_15_30cm_p50'),
                    'p90': data.get('phh2o_15_30cm_p90'),
                    'sd': data.get('phh2o_15_30cm_sd'),
                },
                'deep_30_60cm': {
                    'mean': data.get('phh2o_30_60cm_mean'),
                    'p10': data.get('phh2o_30_60cm_p10'),
                    'median': data.get('phh2o_30_60cm_p50'),
                    'p90': data.get('phh2o_30_60cm_p90'),
                    'sd': data.get('phh2o_30_60cm_sd'),
                },
                'very_deep_60_100cm': {
                    'mean': data.get('phh2o_60_100cm_mean'),
                    'p10': data.get('phh2o_60_100cm_p10'),
                    'median': data.get('phh2o_60_100cm_p50'),
                    'p90': data.get('phh2o_60_100cm_p90'),
                    'sd': data.get('phh2o_60_100cm_sd'),
                },
                'subsoil_100_200cm': {
                    'mean': data.get('phh2o_100_200cm_mean'),
                    'p10': data.get('phh2o_100_200cm_p10'),
                    'median': data.get('phh2o_100_200cm_p50'),
                    'p90': data.get('phh2o_100_200cm_p90'),
                    'sd': data.get('phh2o_100_200cm_sd'),
                },
            },
            'metrics': soil_metrics,
            'data_quality': {
                'n_occurrences': data.get('n_occurrences'),
                'n_unique_coords': data.get('n_unique_coords'),
                'has_sufficient_data': data.get('has_sufficient_data'),
            }
        }

    def format_globi_section(self, data):
        """Format GloBI interaction data."""
        return {
            'total_records': data.get('globi_total_records'),
            'unique_partners': data.get('globi_unique_partners'),
            'pollination': {
                'records': data.get('globi_pollination_records'),
                'partners': data.get('globi_pollination_partners'),
                'top_partners': data.get('globi_pollination_top_partners'),
            },
            'herbivory': {
                'records': data.get('globi_herbivory_records'),
                'partners': data.get('globi_herbivory_partners'),
                'top_partners': data.get('globi_herbivory_top_partners'),
            },
            'pathogen': {
                'records': data.get('globi_pathogen_records'),
                'partners': data.get('globi_pathogen_partners'),
                'top_partners': data.get('globi_pathogen_top_partners'),
            },
        }

    def format_gbif_summary(self, gbif_df):
        """Summarize GBIF occurrence data in occurrences format."""
        if gbif_df is None or gbif_df.empty:
            return None

        # Extract coordinates
        coords = gbif_df[['decimalLatitude', 'decimalLongitude']].dropna()
        coordinates = []
        for _, row in coords.iterrows():
            coordinates.append({
                'lat': row['decimalLatitude'],
                'lon': row['decimalLongitude']
            })

        return {
            'count': len(gbif_df),
            'coordinates': coordinates
        }

    def format_dimensions_section(self, data):
        """Format plant dimensions (placeholder for now)."""
        height_m = data.get('Plant height (m)')
        return {
            'above_ground': {
                'height_min_m': height_m * 0.7 if pd.notna(height_m) else None,
                'height_max_m': height_m * 1.3 if pd.notna(height_m) else None,
                'spread_min_m': None,
                'spread_max_m': None,
                'qualitative_comments': None
            },
            'root_system': {
                'depth_category': None,
                'lateral_spread': None,
                'qualitative_comments': None
            }
        }

    def species_to_slug(self, species_name):
        """Convert species name to URL-safe slug."""
        return species_name.lower().replace(' ', '-')

    def generate_profile(self, species_name, include_gbif=True):
        """Generate complete plant profile in upload-compatible format."""
        logger.info(f"\nGenerating profile for: {species_name}")

        # Get main data
        data = self.get_species_data(species_name)

        # Generate slug
        slug = self.species_to_slug(species_name)

        profile = {
            'slug': slug,
            'species': species_name,
            'taxonomy': self.format_taxonomy_section(data),
            'eive': self.format_eive_section(data),
            'reliability': self.format_reliability_section(data),
            'traits': self.format_traits_section(data),
            'dimensions': self.format_dimensions_section(data),
            'bioclim': self.format_climate_section(data),
            'interactions': self.format_globi_section(data),
            'soil': self.format_soil_section(species_name),
        }

        # Add GBIF occurrences if requested
        if include_gbif:
            logger.info("  Loading GBIF occurrence data...")
            gbif_df = self.load_gbif_occurrences(species_name)
            profile['occurrences'] = self.format_gbif_summary(gbif_df)

        return profile

    def export_markdown(self, profile, output_path=None):
        """Export profile as markdown report."""
        species = profile['species']
        md = [f"# Plant Profile: *{species}*\n"]
        md.append(f"**Generated:** {profile['generated']}\n")

        # EIVE section
        md.append("## Ecological Indicator Values (EIVE)\n")
        for axis, data in profile['eive']['predictions'].items():
            value = data['value']
            label = data['label']
            md.append(f"- **{axis}:** {value:.2f} — {label}" if pd.notna(value) and pd.notna(label) else f"- **{axis}:** N/A")

        if 'validation' in profile['eive']:
            md.append("\n### Validation Reliability\n")
            for axis, val in profile['eive']['validation'].items():
                verdict = val['verdict']
                score = val['reliability_score']
                label = val['reliability_label']
                md.append(f"- **{axis}:** {verdict} (reliability={score:.2f}, {label})")

        # Traits section
        md.append("\n## Plant Functional Traits\n")
        tax = profile['traits']['taxonomy']
        md.append(f"**Taxonomy:** {tax['family']} / {tax['genus']}\n")
        morph = profile['traits']['morphology']
        md.append(f"- **Growth form:** {morph['growth_form']} ({morph['woodiness']})")
        md.append(f"- **Height:** {morph['plant_height_m']:.2f} m" if pd.notna(morph['plant_height_m']) else "- **Height:** N/A")

        # Climate section
        md.append("\n## Climate\n")
        temp = profile['climate']['temperature']
        md.append(f"- **Annual temp:** {temp['annual_mean_C']:.1f}°C" if pd.notna(temp['annual_mean_C']) else "- **Annual temp:** N/A")
        precip = profile['climate']['precipitation']
        md.append(f"- **Annual precip:** {precip['annual_mm']:.0f} mm" if pd.notna(precip['annual_mm']) else "- **Annual precip:** N/A")

        # GloBI section
        md.append("\n## Ecological Interactions (GloBI)\n")
        interactions = profile['interactions']
        md.append(f"- **Total interaction records:** {int(interactions['total_records']) if pd.notna(interactions['total_records']) else 0}")
        md.append(f"- **Pollination partners:** {int(interactions['pollination']['partners']) if pd.notna(interactions['pollination']['partners']) else 0}")

        # GBIF section
        if profile.get('gbif'):
            md.append("\n## GBIF Occurrences\n")
            gbif = profile['gbif']
            md.append(f"- **Records:** {gbif['temporal']['n_records']}")
            md.append(f"- **Date range:** {gbif['temporal']['earliest_year']}–{gbif['temporal']['latest_year']}")
            md.append(f"- **Coordinates:** {gbif['spatial']['n_coords']}")

        markdown_text = "\n".join(md)

        if output_path:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(markdown_text)
            logger.info(f"  Saved markdown to {output_path}")

        return markdown_text

    def export_json(self, profile, output_path=None):
        """Export profile as JSON."""
        # Convert NaN to None for JSON serialization
        profile_clean = json.loads(json.dumps(profile, default=str))

        if output_path:
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(profile_clean, f, indent=2)
            logger.info(f"  Saved JSON to {output_path}")

        return profile_clean


def main():
    parser = argparse.ArgumentParser(description="Generate comprehensive plant profile")
    parser.add_argument("species", help="Species name (e.g., 'Abies alba')")
    parser.add_argument("--format", choices=['markdown', 'json', 'both'], default='markdown', help="Output format")
    parser.add_argument("--output", help="Output directory (default: print to stdout)")
    parser.add_argument("--no-gbif", action='store_true', help="Skip GBIF occurrence data")
    args = parser.parse_args()

    # Generate profile
    generator = PlantProfileGenerator()
    profile = generator.generate_profile(args.species, include_gbif=not args.no_gbif)

    # Export
    output_dir = Path(args.output) if args.output else None
    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)

    slug = args.species.lower().replace(' ', '-')

    if args.format in ['markdown', 'both']:
        md_path = output_dir / f"{slug}.md" if output_dir else None
        markdown = generator.export_markdown(profile, md_path)
        if not output_dir:
            print(markdown)

    if args.format in ['json', 'both']:
        json_path = output_dir / f"{slug}.json" if output_dir else None
        json_data = generator.export_json(profile, json_path)
        if not output_dir:
            print(json.dumps(json_data, indent=2))

    logger.info("\n✓ Profile generation complete!")


if __name__ == "__main__":
    main()
