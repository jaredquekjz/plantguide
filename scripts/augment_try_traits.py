#!/usr/bin/env python3
"""Augment canonical trait tables with selected TRY raw trait records."""

import argparse
import csv
import sys
import unicodedata
import re
from collections import Counter, defaultdict
from pathlib import Path

csv.field_size_limit(sys.maxsize)

TRAIT_DEFS = {
    6:    {"column": "trait_root_depth_raw", "kind": "numeric"},
    37:   {"column": "trait_leaf_phenology_raw", "kind": "categorical"},
    82:   {"column": "trait_root_tissue_density_raw", "kind": "numeric"},
    83:   {"column": "trait_root_diameter_raw", "kind": "numeric"},
    1080: {"column": "trait_root_srl_raw", "kind": "numeric"},
    1257: {"column": "trait_flower_nectar_sugar_raw", "kind": "numeric"},
    3579: {"column": "trait_flower_nectar_tube_depth_raw", "kind": "numeric"},
    3821: {"column": "trait_flower_nectar_presence_raw", "kind": "categorical"},
    140:  {"column": "trait_shoot_branching_raw", "kind": "categorical"},
    207:  {"column": "trait_flower_color_raw", "kind": "categorical"},
    210:  {"column": "trait_flower_pollen_number_raw", "kind": "numeric"},
    335:  {"column": "trait_flowering_time_raw", "kind": "numeric"},
    363:  {"column": "trait_root_biomass_raw", "kind": "numeric"},
    507:  {"column": "trait_flowering_onset_raw", "kind": "numeric"},
    2006: {"column": "trait_fine_root_fraction_raw", "kind": "numeric"},
    2817: {"column": "trait_inflorescence_height_raw", "kind": "numeric"},
    2935: {"column": "trait_flower_symmetry_raw", "kind": "categorical"},
    343:  {"column": "trait_life_form_raw", "kind": "categorical"},
}

INVALID_STRINGS = {
    "", "na", "n/a", "nan", "none", "null", "unknown", "not available",
    "not known", "no data", "-", "--", "?"
}


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canonical", required=True, help="Canonical trait CSV to augment")
    parser.add_argument("--try_dir", required=True, help="Directory containing TRY *.txt exports")
    parser.add_argument(
        "--trait_ids",
        nargs="*",
        type=int,
        help="Optional list of TRY TraitIDs to include; defaults to built-in set"
    )
    parser.add_argument("--out_table", required=True, help="Path for augmented canonical CSV")
    parser.add_argument("--summary_csv", required=True, help="Path for coverage summary CSV")
    parser.add_argument("--out_absent", required=True, help="Path for species absent from raw TRY")
    parser.add_argument(
        "--out_no_trait",
        required=True,
        help="Path listing species found in TRY but lacking the selected trait IDs"
    )
    parser.add_argument(
        "--encoding",
        default="latin-1",
        help="Encoding used to read TRY text files (default: latin-1)"
    )
    parser.add_argument(
        "--classification",
        default="data/classification.csv",
        help="Path to WFO classification CSV for synonym resolution"
    )
    return parser.parse_args()


def normalise_string(value: str) -> str:
    return value.strip()


def is_invalid_string(value: str) -> bool:
    return value.lower().strip() in INVALID_STRINGS


def cleaned_reader(handle):
    for line in handle:
        yield line.replace('\0', '')


_NON_ALNUM = re.compile(r'[^a-z0-9\s\-×\.]')


def normalise_name(name: str) -> str:
    if not name:
        return ''
    name = name.strip().strip('"').replace('×', 'x')
    name = unicodedata.normalize('NFKD', name)
    name = ''.join(ch for ch in name if not unicodedata.category(ch).startswith('M'))
    name = name.lower()
    name = _NON_ALNUM.sub(' ', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return name


def main():
    args = parse_args()

    trait_ids = args.trait_ids if args.trait_ids else sorted(TRAIT_DEFS)
    unsupported = [tid for tid in trait_ids if tid not in TRAIT_DEFS]
    if unsupported:
        raise SystemExit(f"Trait IDs not supported: {unsupported}")

    canonical_path = Path(args.canonical)
    if not canonical_path.exists():
        raise SystemExit(f"Canonical dataset not found: {canonical_path}")

    try_dir = Path(args.try_dir)
    if not try_dir.exists():
        raise SystemExit(f"TRY directory not found: {try_dir}")

    # Load canonical species and set up lookups
    canonical_df = []
    canonical_names = []
    with canonical_path.open(newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            canonical_df.append(row)
            canonical_names.append(row['Species name standardized against TPL'])
    species_set = set(canonical_names)
    if len(species_set) != len(canonical_names):
        raise SystemExit("Duplicate species entries detected in canonical dataset")

    canonical_lookup = {}
    accepted_to_canonical = {}
    for row in canonical_df:
        canonical_name = row['Species name standardized against TPL']
        canonical_norm = normalise_name(canonical_name)
        if canonical_norm:
            canonical_lookup[canonical_norm] = canonical_name
        accepted_norm = normalise_name(row.get('wfo_accepted_name'))
        if accepted_norm:
            canonical_lookup.setdefault(accepted_norm, canonical_name)
            accepted_to_canonical[accepted_norm] = canonical_name

    # Build synonym map from WFO classification
    classification_path = Path(args.classification)
    name_to_accepted = {}
    if classification_path.exists():
        accepted_map = {}
        with classification_path.open('r', encoding='latin-1', errors='replace', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                if row.get('taxonomicStatus') != 'Accepted':
                    continue
                taxon_id = row.get('taxonID')
                accepted_norm = normalise_name(row.get('scientificName'))
                if taxon_id and accepted_norm:
                    accepted_map[taxon_id] = accepted_norm
                    name_to_accepted.setdefault(accepted_norm, accepted_norm)
        with classification_path.open('r', encoding='latin-1', errors='replace', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                if row.get('taxonomicStatus') != 'Synonym':
                    continue
                accepted_id = row.get('acceptedNameUsageID')
                if not accepted_id:
                    continue
                accepted_norm = accepted_map.get(accepted_id)
                if not accepted_norm:
                    continue
                synonym_norm = normalise_name(row.get('scientificName'))
                if synonym_norm:
                    name_to_accepted[synonym_norm] = accepted_norm
    else:
        name_to_accepted = {}

    def resolve_species(raw_name: str) -> str | None:
        norm = normalise_name(raw_name)
        if not norm:
            return None
        if norm in canonical_lookup:
            return canonical_lookup[norm]
        accepted_norm = name_to_accepted.get(norm)
        if accepted_norm and accepted_norm in accepted_to_canonical:
            return accepted_to_canonical[accepted_norm]
        return None

    # Prepare storage
    trait_values = {tid: defaultdict(list) for tid in trait_ids}
    trait_value_counts = {tid: defaultdict(Counter) for tid in trait_ids if TRAIT_DEFS[tid]['kind'] == 'categorical'}
    species_present_in_raw = set()
    species_with_trait = {tid: set() for tid in trait_ids}

    txt_files = sorted(try_dir.glob('*.txt'))
    if not txt_files:
        raise SystemExit(f"No TRY text files found in {try_dir}")

    for txt_path in txt_files:
        with txt_path.open('r', encoding=args.encoding, errors='replace', newline='') as raw_handle:
            reader = csv.reader(cleaned_reader(raw_handle), delimiter='\t')
            try:
                header = next(reader)
            except StopIteration:
                continue
            index = {name: idx for idx, name in enumerate(header)}
            try:
                idx_species = index['AccSpeciesName']
                idx_trait = index['TraitID']
            except KeyError as exc:
                raise SystemExit(f"Missing expected column {exc} in {txt_path}")
            idx_std_value = index.get('StdValue')
            idx_orig_value = index.get('OrigValueStr')

            for row in reader:
                if len(row) <= idx_species:
                    continue
                species_raw = row[idx_species]
                canonical_species = resolve_species(species_raw)
                if canonical_species is None and (idx_species_name := index.get('SpeciesName')) is not None and len(row) > idx_species_name:
                    canonical_species = resolve_species(row[idx_species_name])
                if canonical_species is None:
                    continue
                species_present_in_raw.add(canonical_species)

                if len(row) <= idx_trait:
                    continue
                trait_raw = row[idx_trait]
                if not trait_raw or not trait_raw.isdigit():
                    continue
                trait_id = int(trait_raw)
                if trait_id not in trait_values:
                    continue

                value = ""
                if idx_std_value is not None and len(row) > idx_std_value:
                    value = row[idx_std_value]
                if (not value or value.strip() == "") and idx_orig_value is not None and len(row) > idx_orig_value:
                    value = row[idx_orig_value]
                value = normalise_string(value)
                if not value:
                    continue

                trait_def = TRAIT_DEFS[trait_id]
                kind = trait_def['kind']

                if kind == 'numeric':
                    cleaned = value.replace(',', '')
                    try:
                        numeric_val = float(cleaned)
                    except ValueError:
                        continue
                    trait_values[trait_id][canonical_species].append(numeric_val)
                else:
                    if is_invalid_string(value):
                        continue
                    trait_values[trait_id][canonical_species].append(value)
                    trait_value_counts[trait_id][canonical_species][value.lower()] += 1

                species_with_trait[trait_id].add(canonical_species)

    # Augment canonical rows
    for row in canonical_df:
        species = row['Species name standardized against TPL']
        for tid in trait_ids:
            col = TRAIT_DEFS[tid]['column']
            obs_col = f"{col}_obs"
            values = trait_values[tid].get(species)
            if not values:
                row.setdefault(col, "")
                row.setdefault(obs_col, "0")
                row[col] = ""
                row[obs_col] = "0"
                continue
            if TRAIT_DEFS[tid]['kind'] == 'numeric':
                mean_val = sum(values) / len(values)
                row[col] = f"{mean_val:.6g}"
                row[obs_col] = str(len(values))
            else:
                counter = trait_value_counts[tid][species]
                if not counter:
                    row[col] = ""
                    row[obs_col] = "0"
                else:
                    most_common = counter.most_common()
                    top_lower = most_common[0][0]
                    chosen = None
                    for original in values:
                        if original.lower() == top_lower:
                            chosen = original
                            break
                    if chosen is None:
                        chosen = most_common[0][0]
                    row[col] = chosen
                    row[obs_col] = str(sum(counter.values()))

    output_path = Path(args.out_table)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(canonical_df[0].keys())
    with output_path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(canonical_df)

    summary_path = Path(args.summary_csv)
    with summary_path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['TraitID', 'Column', 'Kind', 'Species_with_data'])
        for tid in trait_ids:
            col = TRAIT_DEFS[tid]['column']
            count = sum(1 for values in trait_values[tid].values() if values)
            writer.writerow([tid, col, TRAIT_DEFS[tid]['kind'], count])

    absent_species = sorted(species_set - species_present_in_raw)
    Path(args.out_absent).write_text('\n'.join(absent_species))

    all_species_with_data = set().union(*species_with_trait.values()) if species_with_trait else set()
    species_without_target = sorted(species_set - all_species_with_data)
    Path(args.out_no_trait).write_text('\n'.join(species_without_target))

    print(f"Augmented dataset written to {output_path}")
    print(f"Summary written to {summary_path}")
    print(f"Species absent from TRY raw: {len(absent_species)}")
    print(f"Species lacking selected traits: {len(species_without_target)}")


if __name__ == "__main__":
    main()
