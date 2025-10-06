#!/usr/bin/env python3
"""Build gardener-friendly trait summary table for encyclopedia profiles."""

from __future__ import annotations

import argparse
import csv
import math
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional

import pandas as pd

PRIMARY_DEFAULT = Path('artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv')
RAW_DEFAULT = Path('artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw.csv')
OUTPUT_DEFAULT = Path('data/encyclopedia_gardening_traits.csv')

MONTH_NAMES = [
    None,
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
]

COLOR_MAP = {
    'weiß': 'White', 'weiss': 'White', 'white': 'White', 'blanc': 'White',
    'gelb': 'Yellow', 'yellow': 'Yellow', 'goldgelb': 'Yellow', 'gold': 'Yellow',
    'orange': 'Orange', 'braun': 'Brown', 'brown': 'Brown',
    'grün': 'Green', 'green': 'Green', 'gruen': 'Green',
    'rosa': 'Pink', 'pink': 'Pink', 'rose': 'Pink',
    'rot': 'Red', 'purpur': 'Purple', 'purpurrot': 'Purple', 'lila': 'Purple', 'violett': 'Purple',
    'blau': 'Blue', 'blue': 'Blue', 'azur': 'Blue',
    'schwarz': 'Black', 'black': 'Black',
    'grau': 'Grey', 'gray': 'Grey',
    'silber': 'Silver', 'silver': 'Silver'
}

LEAF_HABIT_MAP = {
    'evergreen': 'Evergreen',
    'always summer green': 'Evergreen',
    'always persistent green': 'Evergreen',
    'always overwintering green': 'Semi-evergreen',
    'deciduous': 'Deciduous',
    'aestival': 'Summer deciduous',
    'marcescent': 'Holds leaves through winter',
    'wintergreen': 'Wintergreen',
    'semi-deciduous': 'Semi-deciduous',
    'semievergreen': 'Semi-evergreen',
    'leafless': 'Leafless',
    'h': 'Evergreen',
    'd': 'Deciduous'
}

BRANCHING_MAP = {
    'sympodial': 'Clumping stems',
    'monopodial': 'Single leader',
    'yes': 'Freely branching',
    'no': 'Single stem',
    '1': 'Single stem',
    '2': 'Clumping stems'
}

MYCO_MAP = {
    'Pure_AM': 'Arbuscular (AM)',
    'Pure_EM': 'Ectomycorrhizal (EM)',
    'Pure_ERM': 'Ericoid mycorrhiza (ERM)',
    'Pure_NM': 'Non-mycorrhizal',
    'Facultative_AM_NM': 'Facultative (AM / Non-mycorrhizal)',
    'Mixed_AM_EM': 'Mixed AM / EM',
    'Mixed_Uncertain': 'Mixed or uncertain type',
    'Low_Confidence': 'Low confidence type'
}

PHOTOSYNTHESIS_MAP = {
    'C3': 'C3 (cool-season)',
    'C4': 'C4 (warm-season)',
    'CAM': 'CAM (succulent)'
}

GROWTH_FORM_LABELS = {
    'tree': 'Tree',
    'shrub': 'Shrub',
    'shrub/tree': 'Shrub or small tree',
    'herbaceous graminoid': 'Herbaceous (grass-like)',
    'herbaceous non-graminoid': 'Herbaceous (broadleaf)',
    'climber': 'Climber',
    'succulent': 'Succulent',
    'fern': 'Fern',
    'forb': 'Forb',
    'liana': 'Liana'
}

LEAF_TYPE_MAP = {
    'broadleaved': 'Broadleaf',
    'needleleaved': 'Needle-like',
    'scale-shaped': 'Scale-like',
    'photosynthetic stem': 'Photosynthetic stems',
    'leafless': 'Leafless'
}

ROOT_DEPTH_BANDS = [
    (0, 0.3, 'Very shallow (<0.3 m)'),
    (0.3, 0.6, 'Shallow (0.3–0.6 m)'),
    (0.6, 1.0, 'Moderate (0.6–1 m)'),
    (1.0, 2.0, 'Deep (1–2 m)'),
    (2.0, math.inf, 'Very deep (>2 m)')
]

HEIGHT_BANDS = [
    (0, 0.15, 'Ground-hugging (<0.15 m)'),
    (0.15, 0.5, 'Low mound (0.15–0.5 m)'),
    (0.5, 1.5, 'Compact shrub (0.5–1.5 m)'),
    (1.5, 4.0, 'Large shrub (1.5–4 m)'),
    (4.0, 8.0, 'Small tree (4–8 m)'),
    (8.0, math.inf, 'Tall tree (>8 m)')
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--primary', type=Path, default=PRIMARY_DEFAULT, help='Primary enhanced TRY dataset (with imputed values).')
    parser.add_argument('--raw', type=Path, default=RAW_DEFAULT, help='Raw TRY-augmented dataset for fallback values.')
    parser.add_argument('--output', type=Path, default=OUTPUT_DEFAULT, help='Output CSV path.')
    return parser.parse_args()


def load_dataset(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise SystemExit(f"Dataset not found: {path}")
    return pd.read_csv(path)


def normalise_leaf_habit(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    lower = value.strip().lower()
    if not lower:
        return None
    if lower in LEAF_HABIT_MAP:
        return LEAF_HABIT_MAP[lower]
    if 'evergreen' in lower:
        return 'Evergreen'
    if 'deciduous' in lower or lower in {'d', 'summergreen'}:
        return 'Deciduous'
    if 'sem' in lower or 'part' in lower:
        return 'Semi-evergreen'
    return value.strip().title()


def normalise_branching(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    lower = value.strip().lower()
    if lower in BRANCHING_MAP:
        return BRANCHING_MAP[lower]
    if 'sympod' in lower:
        return 'Clumping stems'
    if 'mono' in lower:
        return 'Single leader'
    if lower in {'clonal', 'stoloniferous', 'prostrate'}:
        return 'Spreading clumps'
    if lower in {'yes', 'y'}:
        return 'Freely branching'
    if lower in {'no', 'n'}:
        return 'Single stem'
    return value.strip().title()


def normalise_growth_form(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    lower = value.strip().lower()
    if lower in GROWTH_FORM_LABELS:
        return GROWTH_FORM_LABELS[lower]
    if 'tree' in lower and 'shrub' in lower:
        return 'Shrub or small tree'
    if 'tree' in lower:
        return 'Tree'
    if 'shrub' in lower:
        return 'Shrub'
    if 'herb' in lower:
        return 'Herbaceous'
    if 'grass' in lower or 'graminoid' in lower:
        return 'Grass-like'
    if 'succulent' in lower:
        return 'Succulent'
    if 'climb' in lower or 'vine' in lower:
        return 'Climber'
    return value.strip().title()


def normalise_leaf_type(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    lower = value.strip().lower()
    if lower in LEAF_TYPE_MAP:
        return LEAF_TYPE_MAP[lower]
    if 'needle' in lower:
        return 'Needle-like'
    if 'broad' in lower:
        return 'Broadleaf'
    return value.strip().title()


def detect_color_terms(raw: str) -> Optional[str]:
    tokens = [t.strip() for t in raw.replace('/', ',').replace(';', ',').split(',') if t.strip()]
    display_terms = []
    for token in tokens:
        lower = token.lower()
        mapped = None
        for key, label in COLOR_MAP.items():
            if key in lower:
                mapped = label
                break
        if mapped is None:
            # try basic english color words by splitting
            words = lower.replace('-', ' ').split()
            for word in words:
                if word in COLOR_MAP:
                    mapped = COLOR_MAP[word]
                    break
        if mapped is None:
            mapped = token.strip().title()
        if mapped not in display_terms:
            display_terms.append(mapped)
    if not display_terms:
        return None
    return '/'.join(display_terms)


def normalise_flower_color(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value:
        return None
    return detect_color_terms(value)


def interpret_flowering_time(value: Optional[float]) -> tuple[Optional[float], Optional[str]]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None, None
    if value == 0:
        return 0.0, 'Blooms year-round'
    # Month-coded (1-12)
    if 0 < value <= 12:
        month = int(round(value))
        month = max(1, min(12, month))
        return float(value), f'Blooms around {MONTH_NAMES[month]}'
    # Week-of-year (approx)
    if 12 < value <= 60:
        week = int(round(value))
        day_of_year = min(365, max(1, week * 7))
        ref_date = datetime(2001, 1, 1) + timedelta(days=day_of_year - 1)
        return float(value), f'Peaks in {ref_date.strftime("%B")}'
    # Day-of-year or other larger scale
    day = int(round(value))
    day = min(365, max(1, day))
    ref_date = datetime(2001, 1, 1) + timedelta(days=day - 1)
    return float(value), f'Peaks in {ref_date.strftime("%B")}'


def root_depth_band(value: Optional[float]) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    for low, high, label in ROOT_DEPTH_BANDS:
        if low <= value < high:
            return label
    return None


def normalise_myco(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value:
        return None
    return MYCO_MAP.get(value, value)


def normalise_photosynthesis(value: Optional[str]) -> Optional[str]:
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value:
        return None
    return PHOTOSYNTHESIS_MAP.get(value, value)


def height_band(value: Optional[float]) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    for low, high, label in HEIGHT_BANDS:
        if low <= value < high:
            return label
    return None


def combine_columns(primary: pd.DataFrame, fallback: pd.DataFrame, column: str, raw_column: Optional[str] = None) -> pd.Series:
    series = primary.get(column)
    if series is None:
        series = pd.Series(pd.NA, index=primary.index)
    if raw_column:
        raw_series = fallback.get(raw_column)
        if raw_series is not None:
            series = series.fillna(raw_series)
    return series


def main() -> None:
    args = parse_args()
    primary = load_dataset(args.primary)
    raw = load_dataset(args.raw)

    primary = primary.set_index('wfo_accepted_name')
    raw = raw.set_index('wfo_accepted_name')

    result = pd.DataFrame(index=primary.index)

    # Base columns
    result['growth_form_raw'] = combine_columns(primary, raw, 'Growth Form', 'Growth Form')
    result['growth_form_display'] = result['growth_form_raw'].apply(normalise_growth_form)

    result['woodiness'] = combine_columns(primary, raw, 'Woodiness', 'Woodiness').apply(lambda x: x.title() if isinstance(x, str) else x)

    result['leaf_type_raw'] = combine_columns(primary, raw, 'Leaf type', 'Leaf type')
    result['leaf_type_display'] = result['leaf_type_raw'].apply(normalise_leaf_type)

    leaf_habit_raw = combine_columns(primary, raw, 'trait_leaf_phenology_raw', 'trait_leaf_phenology_raw')
    leaf_habit_raw = leaf_habit_raw.fillna(combine_columns(primary, raw, 'Leaf_phenology', 'Leaf_phenology'))
    result['leaf_habit_raw'] = leaf_habit_raw
    result['leaf_habit_display'] = leaf_habit_raw.apply(normalise_leaf_habit)

    branching_raw = combine_columns(primary, raw, 'trait_shoot_branching_raw', 'trait_shoot_branching_raw')
    result['branching_raw'] = branching_raw
    result['branching_display'] = branching_raw.apply(normalise_branching)

    flower_color = combine_columns(primary, raw, 'Flower_color', 'trait_flower_color_raw')
    result['flower_color_raw'] = flower_color
    result['flower_color_display'] = flower_color.apply(normalise_flower_color)

    flowering_time = combine_columns(primary, raw, 'Flowering_time', 'trait_flowering_time_raw')
    display_info = flowering_time.apply(lambda v: interpret_flowering_time(v)[1] if pd.notna(v) else None)
    numeric_info = flowering_time.apply(lambda v: interpret_flowering_time(v)[0] if pd.notna(v) else None)
    result['flowering_time_value'] = numeric_info
    result['flowering_time_display'] = display_info

    root_depth = combine_columns(primary, raw, 'Root_depth', 'trait_root_depth_raw')
    result['root_depth_m'] = root_depth
    result['root_depth_band'] = root_depth.apply(root_depth_band)

    myco = combine_columns(primary, raw, 'Myco_Group_Final', 'Myco_Group_Final')
    result['mycorrhiza_raw'] = myco
    result['mycorrhiza_display'] = myco.apply(normalise_myco)

    photo = combine_columns(primary, raw, 'Photosynthesis_pathway', 'Photosynthesis_pathway')
    result['photosynthesis_raw'] = photo
    result['photosynthesis_display'] = photo.apply(normalise_photosynthesis)

    def to_float(value) -> Optional[float]:
        if value is None:
            return None
        try:
            number = float(value)
        except (TypeError, ValueError):
            return None
        if math.isnan(number):
            return None
        return number

    height_series = combine_columns(primary, raw, 'Plant height (m)', 'Plant height (m)')
    result['height_m'] = height_series.apply(to_float)
    result['height_band'] = result['height_m'].apply(height_band)

    # Crown diameter (canopy width)
    crown_diameter = combine_columns(primary, raw, 'trait_crown_diameter_raw', 'trait_crown_diameter_raw')
    result['crown_diameter_m'] = crown_diameter.apply(to_float)

    # Estimate crown diameter from height using allometric relationships when measured data unavailable
    # Based on research: Crown-to-height ratios vary by growth form and species
    def estimate_crown_diameter(row):
        """Estimate crown diameter from height using allometric relationships."""
        # Use measured value if available and reasonable
        # Filter out unrealistic values (likely from juvenile measurements)
        if pd.notna(row['crown_diameter_m']) and row['crown_diameter_m'] > 0.5:
            return row['crown_diameter_m'], 'observed'

        height = row.get('height_m')
        if pd.isna(height) or height <= 0:
            return None, None

        growth_form = str(row.get('growth_form_display', '')).lower()
        woodiness = str(row.get('woodiness', '')).lower()

        # Allometric crown-to-height ratios based on growth form
        # Conservative estimates based on forestry literature
        if 'tree' in growth_form or woodiness == 'woody':
            # Trees typically have crown:height ratio of 0.3-0.5
            if height > 20:  # Large trees
                ratio = 0.35
            elif height > 10:  # Medium trees
                ratio = 0.40
            else:  # Small trees
                ratio = 0.45
        elif 'shrub' in growth_form:
            # Shrubs often have wider crowns relative to height
            ratio = 0.6
        elif 'herb' in growth_form or 'forb' in growth_form:
            # Herbaceous plants often have crown width similar to height
            ratio = 0.8
        elif 'graminoid' in growth_form or 'grass' in growth_form:
            # Grasses have narrow crowns
            ratio = 0.3
        else:
            # Default conservative estimate
            ratio = 0.4

        return height * ratio, 'estimated'

    # Apply estimation to each row
    crown_estimates = result.apply(estimate_crown_diameter, axis=1)
    result['crown_diameter_m'] = crown_estimates.apply(lambda x: x[0] if x else None)
    result['crown_diameter_source'] = crown_estimates.apply(lambda x: x[1] if x else None)

    # Flower corolla type
    corolla_type = combine_columns(primary, raw, 'trait_flower_corolla_type_raw', 'trait_flower_corolla_type_raw')
    result['flower_corolla_type'] = corolla_type.apply(lambda x: x.strip().title() if isinstance(x, str) and x.strip() else None)

    # Flags for imputation when available
    if 'Root_depth_imputed_flag' in primary.columns:
        result['root_depth_source'] = primary['Root_depth_imputed_flag'].map({0: 'observed', 1: 'imputed'})
    if 'Flowering_time_imputed_flag' in primary.columns:
        result['flowering_time_source'] = primary['Flowering_time_imputed_flag'].map({0: 'observed', 1: 'imputed'})
    if 'Flower_color' in primary.columns:
        # Flower color imputation not tracked; leave blank
        result['flower_color_source'] = pd.NA

    result.reset_index(inplace=True)
    result.rename(columns={'wfo_accepted_name': 'wfo_accepted_name'}, inplace=True)

    output_path = args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(output_path, index=False, quoting=csv.QUOTE_MINIMAL)
    print(f"Saved gardener trait summary to {output_path} ({len(result)} species)")


if __name__ == '__main__':
    main()
