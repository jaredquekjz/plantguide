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
import csv
import json
import logging
from collections import defaultdict
from typing import Optional, Dict, Iterable, List

import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]
COMPREHENSIVE_PRIMARY = REPO_ROOT / "data/comprehensive_plant_dataset.csv"
COMPREHENSIVE_FALLBACK = REPO_ROOT / "data/comprehensive_dataset_no_soil_with_gbif.csv"
DIMENSIONS = REPO_ROOT / "data/legacy_dimensions_matched.csv"
CLASSIFICATION = REPO_ROOT / "data/classification.csv"
GARDENING_TRAITS = REPO_ROOT / "data/encyclopedia_gardening_traits.csv"
SOIL_SUMMARY = REPO_ROOT / "data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv"
STAGE7_PROFILES = REPO_ROOT / "data/stage7_validation_profiles"
OUTPUT_DIR = REPO_ROOT / "data/encyclopedia_profiles"
CSR_STAGE2 = REPO_ROOT / "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv"
SERVICES_STAGE2 = REPO_ROOT / "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr_services.csv"
STAGE7_GARDENING = REPO_ROOT / "results/stage7_gardening_advice"
GROUNDING_SOURCES_DIR = REPO_ROOT / "data/stage8_grounding_sources"
STAGE7_ALIGNMENT_SUMMARY = REPO_ROOT / "results/stage7_alignment_baskets_summary.csv"


class EncyclopediaProfileGenerator:
    """Generate frontend-ready encyclopedia profiles."""

    def __init__(self):
        """Load comprehensive dataset and dimensions."""
        logger.info("Loading comprehensive dataset...")
        dataset_path = COMPREHENSIVE_PRIMARY if COMPREHENSIVE_PRIMARY.exists() else COMPREHENSIVE_FALLBACK
        if dataset_path == COMPREHENSIVE_FALLBACK and not COMPREHENSIVE_PRIMARY.exists():
            logger.info(f"  Canonical dataset missing at {COMPREHENSIVE_PRIMARY}; using fallback {COMPREHENSIVE_FALLBACK.name}")
        self.df = pd.read_csv(dataset_path)
        logger.info(f"  Loaded {len(self.df)} species from {dataset_path.name}")

        # Track species we can provide synonyms for (used when parsing classification data)
        self._target_species = set(self.df['wfo_accepted_name'].tolist())
        self._synonyms_loaded = False
        self._synonyms_by_species: Dict[str, List[str]] = {}

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

        # Load gardener trait summaries if available
        self.gardening_traits: Dict[str, Dict] = {}
        if GARDENING_TRAITS.exists():
            logger.info("Loading gardener trait summary dataset...")
            trait_df = pd.read_csv(GARDENING_TRAITS)
            for _, row in trait_df.iterrows():
                species_key = row.get('wfo_accepted_name')
                if isinstance(species_key, str) and species_key.strip():
                    self.gardening_traits[species_key.strip()] = row.to_dict()
            logger.info(f"  Gardener traits available for {len(self.gardening_traits)} species\n")
        else:
            logger.info("  Gardener trait summary not found; skipping\n")

        # Load soil data if available
        if SOIL_SUMMARY.exists():
            logger.info("Loading comprehensive soil data...")
            self.soil_data = pd.read_csv(SOIL_SUMMARY)
            logger.info(f"  Loaded soil data for {len(self.soil_data)} species\n")
        else:
            logger.info("  Soil data not found; skipping\n")
            self.soil_data = None

        # Load CSR (StrateFy) percentages if available
        self.csr_lookup: Dict[str, Dict[str, float]] = {}
        if CSR_STAGE2.exists():
            logger.info("Loading CSR (StrateFy) from Stage 2 dataset...")
            csr_df = pd.read_csv(CSR_STAGE2, usecols=["wfo_accepted_name", "C", "S", "R"])  # 654 rows expected
            for _, r in csr_df.iterrows():
                sp = str(r["wfo_accepted_name"]).strip()
                if sp:
                    try:
                        self.csr_lookup[sp] = {
                            "C": round(float(r["C"]), 2) if pd.notna(r["C"]) else None,
                            "S": round(float(r["S"]), 2) if pd.notna(r["S"]) else None,
                            "R": round(float(r["R"]), 2) if pd.notna(r["R"]) else None,
                        }
                    except Exception:
                        continue
            logger.info(f"  CSR available for {len(self.csr_lookup)}/{len(self.df)} species\n")
        else:
            logger.info("  CSR dataset not found; profiles will omit CSR block\n")

        # Load rule-based ecosystem service ratings if available
        self.services_lookup = {}
        if SERVICES_STAGE2.exists():
            logger.info("Loading ecosystem service ratings from CSR (rule-based)...")
            svc_df = pd.read_csv(
                SERVICES_STAGE2,
                usecols=[
                    "wfo_accepted_name",
                    "npp_rating","npp_confidence",
                    "decomposition_rating","decomposition_confidence",
                    "nutrient_cycling_rating","nutrient_cycling_confidence",
                    "nutrient_retention_rating","nutrient_retention_confidence",
                    "nutrient_loss_rating","nutrient_loss_confidence",
                    "carbon_biomass_rating","carbon_biomass_confidence",
                    "carbon_recalcitrant_rating","carbon_recalcitrant_confidence",
                    "carbon_total_rating","carbon_total_confidence",
                    "erosion_protection_rating","erosion_protection_confidence",
                ]
            )
            for _, r in svc_df.iterrows():
                sp = str(r["wfo_accepted_name"]).strip()
                if not sp:
                    continue
                self.services_lookup[sp] = {
                    'npp': {'rating': r.get('npp_rating'), 'confidence': r.get('npp_confidence')},
                    'decomposition': {'rating': r.get('decomposition_rating'), 'confidence': r.get('decomposition_confidence')},
                    'nutrient_cycling': {'rating': r.get('nutrient_cycling_rating'), 'confidence': r.get('nutrient_cycling_confidence')},
                    'nutrient_retention': {'rating': r.get('nutrient_retention_rating'), 'confidence': r.get('nutrient_retention_confidence')},
                    'nutrient_loss': {'rating': r.get('nutrient_loss_rating'), 'confidence': r.get('nutrient_loss_confidence')},
                    'carbon_biomass': {'rating': r.get('carbon_biomass_rating'), 'confidence': r.get('carbon_biomass_confidence')},
                    'carbon_recalcitrant': {'rating': r.get('carbon_recalcitrant_rating'), 'confidence': r.get('carbon_recalcitrant_confidence')},
                    'carbon_total': {'rating': r.get('carbon_total_rating'), 'confidence': r.get('carbon_total_confidence')},
                    'erosion_protection': {'rating': r.get('erosion_protection_rating'), 'confidence': r.get('erosion_protection_confidence')},
                }
            logger.info(f"  Ecosystem service ratings available for {len(self.services_lookup)}/{len(self.df)} species\n")
        else:
            logger.info("  Ecosystem service ratings dataset not found; profiles will omit eco_services block\n")

        # Load Stage 7 gardening advice outputs if present
        self.gardening_advice_by_slug: Dict[str, Dict] = {}
        if STAGE7_GARDENING.exists():
            logger.info("Loading Stage 7 gardening advice JSON...")
            loaded = 0
            for path in sorted(STAGE7_GARDENING.glob("*.json")):
                try:
                    with open(path, "r", encoding="utf-8") as handle:
                        payload = json.load(handle)
                except Exception as exc:
                    logger.warning(f"  Could not parse gardening advice {path.name}: {exc}")
                    continue

                slug = str(payload.get("slug") or path.stem).strip()
                if not slug:
                    continue

                advice = {
                    key.removesuffix("_advice"): value
                    for key, value in payload.items()
                    if key.endswith("_advice") and isinstance(value, dict)
                }
                if advice:
                    self.gardening_advice_by_slug[slug] = advice
                    loaded += 1
            logger.info(f"  Gardening advice available for {loaded} species\n")
        else:
            logger.info("  Stage 7 gardening advice directory not found; skipping\n")


        # Load compact grounding-source lookup generated from legacy profiles
        self.grounding_sources_by_slug: Dict[str, Dict[str, List[Dict[str, str]]]] = {}
        if GROUNDING_SOURCES_DIR.exists():
            logger.info("Loading grounding sources (legacy Stage 3 provenance)...")
            loaded = 0
            for path in sorted(GROUNDING_SOURCES_DIR.glob("*.json")):
                try:
                    with open(path, "r", encoding="utf-8") as handle:
                        payload = json.load(handle)
                except Exception as exc:
                    logger.warning("  Could not parse grounding file %s: %s", path.name, exc)
                    continue

                slug = str(payload.get("plant_slug") or path.stem).strip()
                if not slug:
                    continue

                sources = {
                    key: value
                    for key, value in payload.items()
                    if key.startswith("grounding_sources_") and isinstance(value, list)
                }
                if sources:
                    self.grounding_sources_by_slug[slug] = sources
                    loaded += 1
            logger.info(f"  Grounding sources available for {loaded} species\n")
        else:
            logger.info("  Grounding sources directory not found; skipping\n")

        # Load Stage 7 reliability basket summaries (per-axis explanations)
        self.reliability_basket_by_slug: Dict[str, Dict[str, str]] = {}
        self.reliability_reason_by_slug: Dict[str, Dict[str, str]] = {}
        self.reliability_evidence_by_slug: Dict[str, Dict[str, str]] = {}
        self.reliability_summary_by_slug: Dict[str, Dict[str, str]] = {}

        if STAGE7_ALIGNMENT_SUMMARY.exists():
            logger.info("Loading Stage 7 reliability basket summaries...")
            try:
                alignment_df = pd.read_csv(STAGE7_ALIGNMENT_SUMMARY)
            except Exception as exc:
                logger.warning("  Could not read %s: %s", STAGE7_ALIGNMENT_SUMMARY.name, exc)
            else:
                valid_axes = {"L", "M", "R", "N", "T"}
                for _, row in alignment_df.iterrows():
                    slug_raw = row.get("slug")
                    axis_raw = row.get("axis")

                    if pd.isna(slug_raw) or pd.isna(axis_raw):
                        continue

                    slug = str(slug_raw).strip().lower()
                    axis = str(axis_raw).strip().upper()

                    if not slug or axis not in valid_axes:
                        continue

                    def clean(value):
                        if pd.isna(value):
                            return None
                        text = str(value).strip()
                        return text if text else None

                    basket = clean(row.get("basket"))
                    reason = clean(row.get("reason"))
                    evidence = clean(row.get("evidence"))
                    summary = clean(row.get("summary"))

                    if basket:
                        self.reliability_basket_by_slug.setdefault(slug, {})[axis] = basket
                    if reason:
                        self.reliability_reason_by_slug.setdefault(slug, {})[axis] = reason
                    if evidence:
                        self.reliability_evidence_by_slug.setdefault(slug, {})[axis] = evidence
                    if summary:
                        self.reliability_summary_by_slug.setdefault(slug, {})[axis] = summary

                logger.info("  Reliability summaries available for %d species\n", len(self.reliability_basket_by_slug))
        else:
            logger.info("  Stage 7 alignment summary not found; reliability explanations will use fallbacks\n")

    @staticmethod
    def _clean_scientific_value(value: Optional[str]) -> Optional[str]:
        """Normalize quoted scientific strings from TSV sources."""
        if value is None:
            return None
        cleaned = str(value).strip()
        if cleaned.startswith('"') and cleaned.endswith('"') and len(cleaned) >= 2:
            cleaned = cleaned[1:-1]
        return cleaned if cleaned else None

    def _load_synonyms_lookup(self) -> None:
        """Parse World Flora Online classification data to map accepted species to synonyms."""
        if self._synonyms_loaded:
            return

        if not CLASSIFICATION.exists():
            logger.info("  classification.csv not found – skipping synonym enrichment\n")
            self._synonyms_loaded = True
            return

        logger.info("Loading World Flora Online classification data for synonyms...")

        accepted_taxon_for_species: Dict[str, str] = {}
        synonyms_by_taxon: Dict[str, set] = defaultdict(set)

        with open(CLASSIFICATION, 'r', encoding='utf-8', errors='replace') as handle:
            reader = csv.DictReader(handle, delimiter='\t')
            for row in reader:
                scientific_name = self._clean_scientific_value(row.get('scientificName'))
                taxon_status_raw = (row.get('taxonomicStatus') or '').strip()
                taxon_status = taxon_status_raw.lower()
                taxon_id = (row.get('taxonID') or '').strip()
                accepted_id = (row.get('acceptedNameUsageID') or '').strip()

                if scientific_name and scientific_name in self._target_species and taxon_status in {"accepted", "valid"}:
                    accepted_taxon_for_species[scientific_name] = taxon_id

                if accepted_id and 'synonym' in taxon_status:
                    synonym_name = scientific_name
                    if not synonym_name:
                        continue
                    authorship = self._clean_scientific_value(row.get('scientificNameAuthorship'))
                    synonym = f"{synonym_name} {authorship}".strip() if authorship else synonym_name
                    synonyms_by_taxon[accepted_id].add(synonym)

        for species_name, taxon_id in accepted_taxon_for_species.items():
            if not taxon_id:
                continue
            synonyms = sorted(synonyms_by_taxon.get(taxon_id, set()))
            if synonyms:
                self._synonyms_by_species[species_name] = synonyms

        loaded_count = len(self._synonyms_by_species)
        logger.info(f"  Loaded synonyms for {loaded_count} species\n")
        self._synonyms_loaded = True

    def extract_synonyms(self, species_name: str) -> Optional[List[str]]:
        """Return list of botanical synonyms for a species if available."""
        if not self._synonyms_loaded:
            self._load_synonyms_lookup()
        synonyms = self._synonyms_by_species.get(species_name)
        return synonyms if synonyms else None

    def extract_eive_values(self, row) -> Dict[str, Optional[float]]:
        """Extract actual EIVE values (already expert-given in dataset)."""
        return {
            'L': self._safe_float(row.get('EIVEres-L')),
            'M': self._safe_float(row.get('EIVEres-M')),
            'R': self._safe_float(row.get('EIVEres-R')),
            'N': self._safe_float(row.get('EIVEres-N')),
            'T': self._safe_float(row.get('EIVEres-T')),
        }

    def extract_gardening_traits(self, species_name: str) -> Optional[Dict[str, Dict]]:
        """Return gardener-friendly trait summary if available."""
        if not self.gardening_traits:
            return None

        trait_row = self.gardening_traits.get(species_name)
        if not trait_row:
            return None

        def clean_value(key: str) -> Optional[str]:
            value = trait_row.get(key)
            if value is None:
                return None
            if isinstance(value, float) and pd.isna(value):
                return None
            if isinstance(value, str) and not value.strip():
                return None
            return value

        def clean_number(key: str) -> Optional[float]:
            value = trait_row.get(key)
            if value is None:
                return None
            try:
                if isinstance(value, float) and pd.isna(value):
                    return None
                return float(value)
            except (TypeError, ValueError):
                return None

        traits: Dict[str, Dict] = {}

        growth_form = clean_value('growth_form_display') or clean_value('growth_form_raw')
        if growth_form:
            traits['growth_form'] = {
                'label': growth_form,
                'raw': clean_value('growth_form_raw')
            }

        woodiness = clean_value('woodiness')
        if woodiness:
            traits['woodiness'] = {'label': woodiness}

        leaf_type = clean_value('leaf_type_display') or clean_value('leaf_type_raw')
        if leaf_type:
            traits['leaf_type'] = {
                'label': leaf_type,
                'raw': clean_value('leaf_type_raw')
            }

        leaf_habit = clean_value('leaf_habit_display') or clean_value('leaf_habit_raw')
        if leaf_habit:
            traits['leaf_habit'] = {
                'label': leaf_habit,
                'raw': clean_value('leaf_habit_raw')
            }

        branching = clean_value('branching_display') or clean_value('branching_raw')
        if branching:
            traits['branching'] = {
                'label': branching,
                'raw': clean_value('branching_raw')
            }

        flower_color = clean_value('flower_color_display') or clean_value('flower_color_raw')
        if flower_color:
            traits['flower_color'] = {
                'label': flower_color,
                'raw': clean_value('flower_color_raw')
            }

        flowering_label = clean_value('flowering_time_display')
        flowering_value = clean_number('flowering_time_value')
        flowering_source = clean_value('flowering_time_source')
        if flowering_label or flowering_value is not None:
            traits['flowering_time'] = {
                'label': flowering_label,
                'value': flowering_value,
                'source': flowering_source
            }

        root_depth_m = clean_number('root_depth_m')
        root_band = clean_value('root_depth_band')
        root_source = clean_value('root_depth_source')
        if root_depth_m is not None or root_band:
            traits['root_depth'] = {
                'meters': root_depth_m,
                'band': root_band,
                'source': root_source
            }

        mycorrhiza = clean_value('mycorrhiza_display') or clean_value('mycorrhiza_raw')
        if mycorrhiza:
            traits['mycorrhiza'] = {
                'label': mycorrhiza,
                'raw': clean_value('mycorrhiza_raw')
            }

        photosynthesis = clean_value('photosynthesis_display') or clean_value('photosynthesis_raw')
        if photosynthesis:
            traits['photosynthesis'] = {
                'label': photosynthesis,
                'raw': clean_value('photosynthesis_raw')
            }

        height_m = clean_number('height_m')
        height_band = clean_value('height_band')
        if height_m is not None or height_band:
            traits['height'] = {
                'meters': height_m,
                'band': height_band
            }

        # Crown diameter (canopy width)
        crown_diameter_m = clean_number('crown_diameter_m')
        if crown_diameter_m is not None:
            traits['crown_diameter'] = {
                'meters': crown_diameter_m,
                'label': f"{crown_diameter_m:.1f}m canopy width" if crown_diameter_m else None
            }

        # Flower corolla type
        flower_corolla_type = clean_value('flower_corolla_type')
        if flower_corolla_type:
            traits['flower_corolla_type'] = {
                'label': flower_corolla_type
            }

        return traits if traits else None

    def extract_soil(self, species_name: str) -> Optional[Dict]:
        """Extract SoilGrids-derived soil data with friendly summaries."""
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

        # Helper to convert pandas/numpy types to native Python types
        def to_native(value):
            if pd.isna(value):
                return None
            if hasattr(value, 'item'):  # numpy type
                return value.item()
            return value

        # Return pH data at multiple depth layers with statistics
        return {
            'pH': {
                'surface_0_5cm': {
                    'mean': to_native(data.get('phh2o_0_5cm_mean')),
                    'p10': to_native(data.get('phh2o_0_5cm_p10')),
                    'median': to_native(data.get('phh2o_0_5cm_p50')),
                    'p90': to_native(data.get('phh2o_0_5cm_p90')),
                    'sd': to_native(data.get('phh2o_0_5cm_sd')),
                },
                'shallow_5_15cm': {
                    'mean': to_native(data.get('phh2o_5_15cm_mean')),
                    'p10': to_native(data.get('phh2o_5_15cm_p10')),
                    'median': to_native(data.get('phh2o_5_15cm_p50')),
                    'p90': to_native(data.get('phh2o_5_15cm_p90')),
                    'sd': to_native(data.get('phh2o_5_15cm_sd')),
                },
                'medium_15_30cm': {
                    'mean': to_native(data.get('phh2o_15_30cm_mean')),
                    'p10': to_native(data.get('phh2o_15_30cm_p10')),
                    'median': to_native(data.get('phh2o_15_30cm_p50')),
                    'p90': to_native(data.get('phh2o_15_30cm_p90')),
                    'sd': to_native(data.get('phh2o_15_30cm_sd')),
                },
                'deep_30_60cm': {
                    'mean': to_native(data.get('phh2o_30_60cm_mean')),
                    'p10': to_native(data.get('phh2o_30_60cm_p10')),
                    'median': to_native(data.get('phh2o_30_60cm_p50')),
                    'p90': to_native(data.get('phh2o_30_60cm_p90')),
                    'sd': to_native(data.get('phh2o_30_60cm_sd')),
                },
                'very_deep_60_100cm': {
                    'mean': to_native(data.get('phh2o_60_100cm_mean')),
                    'p10': to_native(data.get('phh2o_60_100cm_p10')),
                    'median': to_native(data.get('phh2o_60_100cm_p50')),
                    'p90': to_native(data.get('phh2o_60_100cm_p90')),
                    'sd': to_native(data.get('phh2o_60_100cm_sd')),
                },
                'subsoil_100_200cm': {
                    'mean': to_native(data.get('phh2o_100_200cm_mean')),
                    'p10': to_native(data.get('phh2o_100_200cm_p10')),
                    'median': to_native(data.get('phh2o_100_200cm_p50')),
                    'p90': to_native(data.get('phh2o_100_200cm_p90')),
                    'sd': to_native(data.get('phh2o_100_200cm_sd')),
                },
            },
            'metrics': soil_metrics,
            'data_quality': {
                'n_occurrences': to_native(data.get('n_occurrences')),
                'n_unique_coords': to_native(data.get('n_unique_coords')),
                'has_sufficient_data': to_native(data.get('has_sufficient_data')),
            }
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

        def scaled(value, factor=1.0, rounding=2):
            base = self._safe_float(value)
            if base is None:
                return None
            scaled_value = base * factor
            return round(scaled_value, rounding) if rounding is not None else scaled_value

        annual_mean = self._safe_float(row.get('bio1_mean'))
        warmest_high = scaled(row.get('bio5_mean'), 0.1)
        coldest_low = scaled(row.get('bio6_mean'), 0.1)
        annual_range = self._safe_float(row.get('bio7_mean'))
        temp_seasonality = scaled(row.get('bio4_mean'), 0.01)

        annual_rain = scaled(row.get('bio12_mean'), 100.0, rounding=0)
        wettest_month = scaled(row.get('bio13_mean'), 10.0, rounding=0)
        driest_month = scaled(row.get('bio14_mean'), 0.1, rounding=0)
        precip_seasonality = self._safe_float(row.get('bio15_mean'))

        sufficient_raw = row.get('has_sufficient_data_bioclim')
        if pd.isna(sufficient_raw):
            sufficient_flag = None
        else:
            sufficient_flag = bool(sufficient_raw)

        return {
            'temperature': {
                'annual_mean_C': annual_mean,
                'warmest_month_high_C': warmest_high,
                'coldest_month_low_C': coldest_low,
                'annual_range_C': annual_range,
                'seasonality_sd_C': temp_seasonality,
            },
            'precipitation': {
                'annual_mm': annual_rain,
                'wettest_month_mm': wettest_month,
                'driest_month_mm': driest_month,
                'seasonality_cv': precip_seasonality,
            },
            'aridity': {
                'index_mean': self._safe_float(row.get('AI_mean')),
            },
            'occurrence_summary': {
                'n_occurrences': self._safe_int(row.get('n_occurrences_bioclim')),
                'sufficient_data': sufficient_flag,
            }
        }

    def extract_koppen_distribution(self, row) -> Optional[Dict]:
        """Extract precomputed Köppen zone distribution."""
        counts_map = self._parse_json_dict(row.get('koppen_zone_counts_json'))
        if not counts_map:
            return None

        percents_map = self._parse_json_dict(row.get('koppen_zone_percents_json')) or {}
        ranked_list = self._parse_json_list(row.get('koppen_ranked_zones_json'))

        def normalize_counts(data: Dict[str, object]) -> Dict[str, int]:
            parsed: Dict[str, int] = {}
            for zone, value in data.items():
                try:
                    parsed[str(zone)] = int(value)
                except (ValueError, TypeError):
                    continue
            return parsed

        def normalize_percents(data: Dict[str, object], zones: Iterable[str]) -> Dict[str, float]:
            parsed: Dict[str, float] = {}
            for zone in zones:
                value = data.get(zone)
                try:
                    parsed[str(zone)] = round(float(value), 2)
                except (ValueError, TypeError, AttributeError):
                    parsed[str(zone)] = None  # type: ignore[assignment]
            # Remove None values while preserving order
            return {k: v for k, v in parsed.items() if v is not None}

        counts = normalize_counts(counts_map)
        if not counts:
            return None

        percents = normalize_percents(percents_map, counts.keys())
        if not ranked_list:
            ranked_list = sorted(counts.keys(), key=lambda z: counts[z], reverse=True)

        return {
            'total_occurrences': self._safe_int(row.get('koppen_total_occurrences')),
            'unique_coordinates': self._safe_int(row.get('koppen_unique_coordinates')),
            'top_zone': {
                'code': self._safe_str(row.get('koppen_top_zone')),
                'percent': self._safe_float(row.get('koppen_top_zone_percent')),
                'description': self._safe_str(row.get('koppen_top_zone_description')),
            },
            'counts': counts,
            'percents': percents,
            'ranked_zones': ranked_list,
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

    def extract_gardening_advice(self, slug: str) -> Optional[Dict]:
        """Return Stage 7 gardening advice for a species slug if available."""
        advice = self.gardening_advice_by_slug.get(slug)
        if advice:
            return advice
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
            'koppen_distribution': self.extract_koppen_distribution(row),
            'soil': self.extract_soil(species_name),
            'interactions': self.extract_globi_interactions(row),
            'occurrences': {
                'count': self._safe_int(row.get('n_occurrences')),
                'coordinates': self.extract_gbif_coordinates(row),
            },
        }

        gardening_traits = self.extract_gardening_traits(species_name)
        if gardening_traits:
            profile['gardening_traits'] = gardening_traits

        synonyms = self.extract_synonyms(species_name)
        if synonyms:
            profile['synonyms'] = synonyms

        slug_key = profile['slug'].lower()

        basket_map = self.reliability_basket_by_slug.get(slug_key)
        if basket_map:
            profile['reliability_basket'] = dict(basket_map)

        reason_map = self.reliability_reason_by_slug.get(slug_key)
        if reason_map:
            profile['reliability_reason'] = dict(reason_map)

        evidence_map = self.reliability_evidence_by_slug.get(slug_key)
        if evidence_map:
            profile['reliability_evidence'] = dict(evidence_map)

        summary_map = self.reliability_summary_by_slug.get(slug_key)
        if summary_map:
            profile['stage7_reliability_summary'] = dict(summary_map)

        # CSR block (if available)
        csr_vals = self.csr_lookup.get(species_name)
        if csr_vals:
            profile['csr'] = csr_vals

        # Ecosystem services block (rule-based ratings)
        svc = self.services_lookup.get(species_name)
        if svc:
            profile['eco_services'] = svc

        # Merge Stage 7 content if available (for legacy frontend compatibility)
        stage7_content = self.extract_stage7_content(species_name)
        if stage7_content:
            profile['stage7'] = stage7_content

        # Attach Stage 7 gardening advice (Gemini prompts)
        gardening_advice = self.extract_gardening_advice(profile['slug'])
        if gardening_advice:
            profile['stage7_gardening_advice'] = gardening_advice

        # Attach grounding sources (legacy Stage 3 provenance)
        sources = self.grounding_sources_by_slug.get(profile['slug'])
        if sources:
            profile.update(sources)

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

    def _parse_json_dict(self, value) -> Optional[Dict[str, object]]:
        """Parse JSON-encoded dict if provided as string."""
        if pd.isna(value) or not value:
            return None
        if isinstance(value, dict):
            return value
        try:
            parsed = json.loads(value)
        except (TypeError, json.JSONDecodeError):
            return None
        return parsed if isinstance(parsed, dict) else None

    def _parse_json_list(self, value) -> Optional[List[str]]:
        """Parse JSON-encoded list if provided as string."""
        if pd.isna(value) or value in ("", None):
            return None
        if isinstance(value, list):
            return value
        try:
            parsed = json.loads(value)
        except (TypeError, json.JSONDecodeError):
            return None
        if isinstance(parsed, list):
            return [str(item) for item in parsed]
        return None


def main():
    """Generate encyclopedia profiles for all 654 species."""
    import argparse

    parser = argparse.ArgumentParser(description="Generate encyclopedia JSON profiles")
    parser.add_argument('--species', help='Single species to generate (default: all)')
    parser.add_argument('--species-list', nargs='*', help='Multiple species to generate (optional)')
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

    elif args.species_list:
        species_list = args.species_list
        logger.info(f"Generating {len(species_list)} encyclopedia profiles (list)...")
        if args.skip_coords:
            logger.info("  (skipping coordinate extraction for speed)\n")
        success = generator.generate_batch(species_list, skip_coordinates=args.skip_coords)
        logger.info(f"\n✓ Generated {success}/{len(species_list)} profiles")
        logger.info(f"  Output directory: {OUTPUT_DIR}")
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
