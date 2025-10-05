#!/usr/bin/env python3
"""Generate qualitative EIVE descriptions for Stage 7 validation species."""

from __future__ import annotations

from pathlib import Path
from typing import Dict

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]

MAPPING_CSV = REPO_ROOT / "data" / "stage7_validation_mapping.csv"
EIVE_MAIN_CSV = REPO_ROOT / "data" / "EIVE" / "EIVE_Paper_1.0_SM_08_csv" / "mainTable.csv"
EIVE_WFO_CSV = REPO_ROOT / "data" / "EIVE" / "EIVE_TaxonConcept_WFO_EXACT.csv"
BIN_DIR = REPO_ROOT / "data" / "mappings"
OUTPUT_CSV = REPO_ROOT / "data" / "stage7_validation_eive_labels.csv"

AXIS_COLUMNS: Dict[str, str] = {
    "L": "EIVEres-L",
    "M": "EIVEres-M",
    "R": "EIVEres-R",
    "N": "EIVEres-N",
    "T": "EIVEres-T",
}


def load_bin_tables() -> Dict[str, pd.DataFrame]:
    tables: Dict[str, pd.DataFrame] = {}
    for axis in AXIS_COLUMNS:
        path = BIN_DIR / f"{axis}_bins.csv"
        if not path.exists():
            raise FileNotFoundError(f"Missing bin table for axis {axis}: {path}")
        table = pd.read_csv(path).sort_values("lower")
        if table.empty:
            raise ValueError(f"Bin table for axis {axis} is empty")
        tables[axis] = table
    return tables


def assign_labels(values: pd.Series, edges: np.ndarray, labels: pd.Series) -> pd.Series:
    categories = pd.cut(values, bins=edges, labels=labels, include_lowest=True, right=False)
    mask = values >= edges[-1]
    if mask.any():
        categories = categories.astype(object)
        categories[mask] = labels.iloc[-1]
    return categories.astype(str)


def main() -> None:
    mapping = pd.read_csv(MAPPING_CSV)

    # Bring stage2 species onto the EIVE taxon concept using WFO (deduplicated)
    wfo = pd.read_csv(EIVE_WFO_CSV).drop_duplicates("wfo_accepted_name")
    map_wfo = mapping.merge(
        wfo[["TaxonConcept", "wfo_accepted_name"]],
        left_on="stage2_species",
        right_on="wfo_accepted_name",
        how="left",
    )
    map_wfo["taxon_key"] = map_wfo["TaxonConcept"].fillna(map_wfo["stage2_species"])

    eive = pd.read_csv(EIVE_MAIN_CSV)
    merged = map_wfo.merge(eive, left_on="taxon_key", right_on="TaxonConcept", how="left")
    merged = merged.rename(
        columns={
            "TaxonConcept_x": "TaxonConcept_from_wfo",
            "TaxonConcept_y": "taxon_concept",
        }
    )

    if merged["taxon_concept"].isna().any():
        missing = merged.loc[merged["taxon_concept"].isna(), "stage2_species"].tolist()
        raise ValueError(f"Missing EIVE records for species: {missing}")

    bin_tables = load_bin_tables()

    label_columns = []
    for axis, value_col in AXIS_COLUMNS.items():
        bins = bin_tables[axis]
        edges = np.concatenate([bins["lower"].to_numpy(), [bins["upper"].iloc[-1]]])
        labels = bins["label"]
        if len(edges) != len(labels) + 1:
            raise ValueError(f"Axis {axis}: boundary mismatch ({len(edges)} edges, {len(labels)} labels)")
        merged[f"{axis}_label"] = assign_labels(merged[value_col], edges, labels)
        label_columns.append(f"{axis}_label")

    keep_cols = [
        "stage2_species",
        "legacy_slug",
        "legacy_path",
        "destination_path",
        "taxon_concept",
    ]
    keep_cols.extend(AXIS_COLUMNS.values())
    keep_cols.extend(label_columns)

    output = merged[keep_cols].copy()
    output.to_csv(OUTPUT_CSV, index=False)
    print(f"Wrote {OUTPUT_CSV.relative_to(REPO_ROOT)} with {len(output)} rows")


if __name__ == "__main__":
    main()
