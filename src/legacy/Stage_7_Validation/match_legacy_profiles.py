#!/usr/bin/env python3
"""Match Stage 2 species with legacy Gemini plant profiles and copy the overlaps."""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import sys
import unicodedata
from collections import OrderedDict, defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple

DEFAULT_STAGE2_DIRS = [
    "results/aic_selection_T_pc",
    "results/aic_selection_M_pc",
    "results/aic_selection_L_tensor_pruned",
    "results/aic_selection_N_structured",
    "results/aic_selection_R_structured",
]

DEFAULT_LEGACY_DIRS = [
    "/home/olier/plantsdatabase/archive/data_backup/plant_profiles",
    "/home/olier/plantsdatabase/archive/plant_profiles",
]

_NON_ALNUM = re.compile(r"[^a-z0-9\s\-×.]")
_WHITESPACE = re.compile(r"\s+")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--legacy-dirs",
        nargs="+",
        help="Override the default list of legacy profile directories (space-separated list)",
    )
    parser.add_argument(
        "--legacy-dir",
        dest="legacy_dirs_append",
        action="append",
        help="Additional legacy directory to search (can be repeated).",
    )
    parser.add_argument(
        "--stage2-dirs",
        nargs="*",
        default=DEFAULT_STAGE2_DIRS,
        help="Stage 2 result directories to scan for species lists",
    )
    parser.add_argument(
        "--classification",
        default="data/classification.csv",
        help="Tab-delimited WFO classification file for synonym resolution",
    )
    parser.add_argument(
        "--out-dir",
        default="data/stage7_validation_profiles",
        help="Destination directory for matched legacy JSON files",
    )
    parser.add_argument(
        "--mapping-csv",
        default="data/stage7_validation_mapping.csv",
        help="CSV mapping of Stage 2 species to legacy slugs",
    )
    parser.add_argument(
        "--unmatched-csv",
        default="data/stage7_validation_unmatched.csv",
        help="CSV listing Stage 2 species with no legacy profile match",
    )
    parser.add_argument(
        "--report-json",
        default="data/stage7_validation_report.json",
        help="Summary report JSON path",
    )
    return parser.parse_args()


def strip_markup(value: str | None) -> str:
    if not value:
        return ""
    value = re.sub(r"<[^>]+>", " ", value)
    value = value.replace("*", " ")
    return value.strip()


def normalise_name(name: str) -> str:
    name = strip_markup(name)
    if not name:
        return ""
    name = name.replace("×", "x")
    name = unicodedata.normalize("NFKD", name)
    name = "".join(ch for ch in name if not unicodedata.category(ch).startswith("M"))
    name = name.lower()
    name = _NON_ALNUM.sub(" ", name)
    name = _WHITESPACE.sub(" ", name).strip()
    return name


def slugify(scientific_name: str) -> str:
    base = normalise_name(scientific_name)
    if not base:
        return ""
    return base.replace(" ", "-")


def load_classification_map(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}

    name_to_accepted: Dict[str, str] = {}
    taxon_to_accepted: Dict[str, str] = {}

    with path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            if row.get("taxonomicStatus") != "Accepted":
                continue
            taxon_id = row.get("taxonID")
            accepted_norm = normalise_name(row.get("scientificName", ""))
            if not accepted_norm:
                continue
            name_to_accepted.setdefault(accepted_norm, accepted_norm)
            if taxon_id:
                taxon_to_accepted[taxon_id] = accepted_norm

    with path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            if row.get("taxonomicStatus") != "Synonym":
                continue
            accepted_id = row.get("acceptedNameUsageID")
            accepted_norm = taxon_to_accepted.get(accepted_id)
            if not accepted_norm:
                continue
            synonym_norm = normalise_name(row.get("scientificName", ""))
            if not synonym_norm:
                continue
            current = name_to_accepted.get(synonym_norm)
            if current in {accepted_norm, synonym_norm}:
                name_to_accepted[synonym_norm] = accepted_norm
            elif current is None:
                name_to_accepted[synonym_norm] = accepted_norm
            # If current maps to a different accepted name keep the existing value

    return name_to_accepted


def collect_stage2_species(stage2_dirs: Iterable[str]) -> Tuple[List[str], Dict[str, Path]]:
    species_sources: "OrderedDict[str, Path]" = OrderedDict()

    for directory in stage2_dirs:
        dir_path = Path(directory)
        if not dir_path.exists():
            continue
        csv_paths = sorted(dir_path.glob("gam_*_cv_predictions_loso.csv"))
        for csv_path in csv_paths:
            with csv_path.open("r", encoding="utf-8", newline="") as handle:
                reader = csv.DictReader(handle)
                for row in reader:
                    species = row.get("species")
                    if not species:
                        continue
                    if species not in species_sources:
                        species_sources[species] = csv_path
    return list(species_sources.keys()), species_sources


def load_legacy_profiles(
    legacy_dirs: Iterable[str],
    name_to_accepted: Dict[str, str],
) -> Tuple[Dict[str, Dict], Dict[str, Set[str]], Dict[str, Set[str]], List[str], List[str], List[str]]:
    record_map: Dict[str, Dict] = {}
    name_lookup: Dict[str, Set[str]] = defaultdict(set)
    accepted_lookup: Dict[str, Set[str]] = defaultdict(set)
    errors: List[str] = []
    searched_dirs: List[str] = []
    missing_dirs: List[str] = []

    for legacy_dir in legacy_dirs:
        dir_path = Path(legacy_dir)
        if not dir_path.exists():
            missing_dirs.append(str(dir_path))
            continue
        searched_dirs.append(str(dir_path))

        for json_path in sorted(dir_path.glob("*.json")):
            try:
                with json_path.open("r", encoding="utf-8") as handle:
                    payload = json.load(handle)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"Failed to parse {json_path}: {exc}")
                continue

            slug = payload.get("plant_slug") or json_path.stem
            slug = slug.strip() if isinstance(slug, str) else json_path.stem
            if slug in record_map:
                continue

            taxonomy = payload.get("taxonomy") or {}
            names: Set[str] = set()
            if isinstance(taxonomy, dict):
                tax_species = taxonomy.get("species")
                if isinstance(tax_species, str) and tax_species:
                    names.add(strip_markup(tax_species))
                tax_scientific = taxonomy.get("scientific_name")
                if isinstance(tax_scientific, str) and tax_scientific:
                    names.add(strip_markup(tax_scientific))
                genus = taxonomy.get("genus")
                epithet = taxonomy.get("specificEpithet")
                if isinstance(genus, str) and isinstance(epithet, str):
                    genus_clean = strip_markup(genus)
                    epithet_clean = strip_markup(epithet)
                    if genus_clean and epithet_clean:
                        names.add(f"{genus_clean} {epithet_clean}")

            slug_name = slug.replace("-", " ")
            names.add(slug_name)

            record_map[slug] = {
                "slug": slug,
                "path": json_path,
                "names": names,
            }

            for raw_name in names:
                norm = normalise_name(raw_name)
                if not norm:
                    continue
                name_lookup[norm].add(slug)
                accepted_norm = name_to_accepted.get(norm, norm)
                accepted_lookup[accepted_norm].add(slug)

    return record_map, name_lookup, accepted_lookup, errors, searched_dirs, missing_dirs


def choose_match(
    species: str,
    candidates: List[Tuple[str, str]],
) -> Tuple[str | None, str | None]:
    if not candidates:
        return None, None

    preferred_slug = slugify(species)
    seen = set()
    deduped: List[Tuple[str, str]] = []
    for slug, reason in candidates:
        if slug not in seen:
            deduped.append((slug, reason))
            seen.add(slug)

    for slug, reason in deduped:
        if preferred_slug and slug == preferred_slug:
            return slug, reason
    return deduped[0]


def match_species(
    species_list: Iterable[str],
    record_map: Dict[str, Dict],
    name_lookup: Dict[str, Set[str]],
    accepted_lookup: Dict[str, Set[str]],
    name_to_accepted: Dict[str, str],
) -> Tuple[List[Dict[str, str]], List[str]]:
    matches: List[Dict[str, str]] = []
    unmatched: List[str] = []

    for species in species_list:
        norm = normalise_name(species)
        accepted_norm = name_to_accepted.get(norm, norm)

        candidates: List[Tuple[str, str]] = []
        for slug in name_lookup.get(norm, set()):
            candidates.append((slug, "direct"))
        if accepted_norm != norm:
            for slug in name_lookup.get(accepted_norm, set()):
                candidates.append((slug, "accepted_name"))
        for slug in accepted_lookup.get(accepted_norm, set()):
            candidates.append((slug, "accepted_lookup"))

        if not candidates:
            unmatched.append(species)
            continue

        chosen_slug, reason = choose_match(species, candidates)
        if not chosen_slug:
            unmatched.append(species)
            continue

        record = record_map.get(chosen_slug)
        if not record:
            unmatched.append(species)
            continue

        matches.append(
            {
                "stage2_species": species,
                "legacy_slug": chosen_slug,
                "legacy_path": str(record["path"]),
                "accepted_name": accepted_norm if accepted_norm != norm else "",
                "match_reason": reason or "direct",
            }
        )

    return matches, unmatched


def write_mapping_csv(path: Path, matches: Iterable[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        fieldnames = [
            "stage2_species",
            "legacy_slug",
            "legacy_path",
            "destination_path",
            "accepted_name",
            "match_reason",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in matches:
            writer.writerow(row)


def write_unmatched_csv(path: Path, unmatched: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["stage2_species"])
        for name in unmatched:
            writer.writerow([name])


def write_report_json(path: Path, report: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)


def main() -> None:
    args = parse_args()

    if args.legacy_dirs:
        legacy_dirs = [str(Path(p)) for p in args.legacy_dirs]
    else:
        legacy_dirs = DEFAULT_LEGACY_DIRS.copy()

    if args.legacy_dirs_append:
        legacy_dirs.extend(str(Path(p)) for p in args.legacy_dirs_append)

    if not legacy_dirs:
        raise SystemExit("No legacy directories provided")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    classification_path = Path(args.classification)
    name_to_accepted = load_classification_map(classification_path)

    (
        record_map,
        name_lookup,
        accepted_lookup,
        load_errors,
        searched_dirs,
        missing_dirs,
    ) = load_legacy_profiles(legacy_dirs, name_to_accepted)

    if not record_map:
        raise SystemExit(
            "No legacy profiles were loaded. Check the supplied --legacy-dirs option."
        )

    stage2_species, species_sources = collect_stage2_species(args.stage2_dirs)
    if not stage2_species:
        raise SystemExit("No Stage 2 species were found in the supplied directories")

    matches, unmatched = match_species(
        stage2_species, record_map, name_lookup, accepted_lookup, name_to_accepted
    )

    copied_slugs: Set[str] = set()
    for row in matches:
        slug = row["legacy_slug"]
        record = record_map[slug]
        dest_path = out_dir / f"{slug}.json"
        row["destination_path"] = str(dest_path)
        if slug in copied_slugs:
            continue
        shutil.copy2(record["path"], dest_path)
        copied_slugs.add(slug)

    mapping_csv = Path(args.mapping_csv)
    write_mapping_csv(mapping_csv, matches)

    unmatched_csv = Path(args.unmatched_csv)
    write_unmatched_csv(unmatched_csv, unmatched)

    report = {
        "legacy_dirs": searched_dirs,
        "missing_legacy_dirs": missing_dirs,
        "stage2_dirs": [str(Path(p)) for p in args.stage2_dirs],
        "classification": str(classification_path),
        "out_dir": str(out_dir),
        "total_stage2_species": len(stage2_species),
        "matched_species": len(matches),
        "copied_profiles": len(copied_slugs),
        "unmatched_species": len(unmatched),
        "load_errors": load_errors,
    }
    write_report_json(Path(args.report_json), report)

    print(
        f"Matched {len(matches)} of {len(stage2_species)} Stage 2 species; "
        f"copied {len(copied_slugs)} legacy profiles."
    )
    if unmatched:
        print(f"Unmatched species written to {unmatched_csv}")
    if missing_dirs:
        print(
            "Some legacy directories were missing: " + ", ".join(missing_dirs),
            file=sys.stderr,
        )
    if load_errors:
        print(f"Encountered {len(load_errors)} legacy JSON parse errors", file=sys.stderr)


if __name__ == "__main__":
    main()
