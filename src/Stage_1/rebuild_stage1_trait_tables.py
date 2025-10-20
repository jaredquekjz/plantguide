#!/usr/bin/env python3
"""
Rebuild Stage 1 trait aggregation tables and modelling-ready artefacts.

Outputs
-------
- data/stage1/traits_model_ready_{STAMP}.parquet
- model_data/inputs/traits_model_ready_{STAMP}.parquet
- model_data/inputs/trait_imputation_input_modelling_shortlist_{STAMP}.csv / .parquet
"""

from __future__ import annotations

import argparse
import datetime as dt
from typing import Iterable, Sequence, Optional
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path("/home/olier/ellenberg")
DATA_STAGE1 = ROOT / "data" / "stage1"
MODEL_INPUTS = ROOT / "model_data" / "inputs"

TRY_ENHANCED = DATA_STAGE1 / "tryenhanced_worldflora_enriched.parquet"
AUST_TRAITS = DATA_STAGE1 / "austraits" / "traits.parquet"
AUST_TAXA = DATA_STAGE1 / "austraits" / "austraits_taxa_worldflora_enriched.parquet"
MODELLING_SHORTLIST = DATA_STAGE1 / "stage1_modelling_shortlist.parquet"
MODELLING_SHORTLIST_GE30 = DATA_STAGE1 / "stage1_modelling_shortlist_with_gbif_ge30.parquet"
SHORTLIST_GE30 = DATA_STAGE1 / "stage1_shortlist_with_gbif_ge30.parquet"
WFO_TAXONOMY = MODEL_INPUTS / "wfo_taxonomy_subset.parquet"


def first_non_null(series: pd.Series) -> float | str | None:
    """Return the first non-null element or None."""
    if series is None:
        return None
    s = series.dropna()
    if s.empty:
        return None
    return s.iloc[0]


def load_try_aggregates() -> pd.DataFrame:
    """Aggregate TRY enhanced traits to species level."""
    if not TRY_ENHANCED.exists():
        raise FileNotFoundError(f"TRY enhanced parquet not found: {TRY_ENHANCED}")

    df = pd.read_parquet(TRY_ENHANCED)
    df = df[df["wfo_taxon_id"].notna()]
    df["wfo_taxon_id"] = df["wfo_taxon_id"].astype(str)

    numeric_cols = [
        "Leaf area (mm2)",
        "Leaf area (n.o.)",
        "Nmass (mg/g)",
        "LMA (g/m2)",
        "Plant height (m)",
        "Diaspore mass (mg)",
        "LDMC (g/g)",
    ]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    agg = df.groupby("wfo_taxon_id").agg(
        wfo_scientific_name=("wfo_scientific_name", first_non_null),
        leaf_area_mm2=("Leaf area (mm2)", "median"),
        leaf_area_n=("Leaf area (n.o.)", first_non_null),
        try_nmass=("Nmass (mg/g)", "median"),
        try_lma=("LMA (g/m2)", "median"),
        try_height=("Plant height (m)", "median"),
        try_seed_mass=("Diaspore mass (mg)", "median"),
        try_ldmc=("LDMC (g/g)", "median"),
    )

    agg["leaf_area_n"] = pd.to_numeric(agg["leaf_area_n"], errors="coerce")
    agg["try_logNmass"] = np.where(agg["try_nmass"] > 0, np.log(agg["try_nmass"]), np.nan)
    agg["try_logLA"] = np.where(agg["leaf_area_mm2"] > 0, np.log(agg["leaf_area_mm2"]), np.nan)
    agg["try_sla"] = np.where(agg["try_lma"] > 0, 1000.0 / agg["try_lma"], np.nan)

    return agg


def load_austraits_aggregates() -> pd.DataFrame:
    """Aggregate AusTraits numeric traits to species level and map to WFO IDs."""
    if not AUST_TRAITS.exists():
        raise FileNotFoundError(f"AusTraits trait file missing: {AUST_TRAITS}")
    if not AUST_TAXA.exists():
        raise FileNotFoundError(f"AusTraits taxonomy mapping missing: {AUST_TAXA}")

    traits = pd.read_parquet(AUST_TRAITS)
    taxa = pd.read_parquet(AUST_TAXA)[["taxon_name", "wfo_taxon_id", "wfo_scientific_name"]]

    df = traits.merge(taxa, on="taxon_name", how="left")
    df = df[df["wfo_taxon_id"].notna()]
    df["wfo_taxon_id"] = df["wfo_taxon_id"].astype(str)

    numeric_traits = {
        "leaf_dry_matter_content": "aust_ldmc",
        "leaf_lamina_mass_per_area": "aust_lma",
        "seed_dry_mass": "aust_seed_mass",
        "plant_height": "aust_height",
    }

    frames: list[pd.Series] = []
    for trait_name, col_name in numeric_traits.items():
        sub = df[df["trait_name"] == trait_name].copy()
        if sub.empty:
            continue
        sub["value"] = pd.to_numeric(sub["value"], errors="coerce")
        agg = sub.groupby("wfo_taxon_id")["value"].median()
        agg.name = col_name
        frames.append(agg)

    names = df.groupby("wfo_taxon_id")["wfo_scientific_name"].agg(first_non_null)
    names.name = "wfo_scientific_name_austraits"
    frames.append(names)

    if not frames:
        return pd.DataFrame(columns=["wfo_taxon_id"])

    aust = pd.concat(frames, axis=1).reset_index().rename(columns={"index": "wfo_taxon_id"})
    aust.set_index("wfo_taxon_id", inplace=True)
    return aust


def assign_canonical_sla(df: pd.DataFrame) -> pd.DataFrame:
    """Assign canonical SLA values with provenance preference."""
    result = df.copy()

    result["sla_mm2_mg"] = result.get("try_sla")
    result["sla_source"] = np.where(result["sla_mm2_mg"].notna(), "try_enhanced", None)

    if "aust_sla" in result.columns:
        aust_mask = result["sla_mm2_mg"].isna() & result["aust_sla"].notna()
        result.loc[aust_mask, "sla_mm2_mg"] = result.loc[aust_mask, "aust_sla"]
        result.loc[aust_mask, "sla_source"] = "austraits"

    lma_vals = np.where(result["lma_g_m2"] > 0, 1000.0 / result["lma_g_m2"], np.nan)
    lma_mask = result["sla_mm2_mg"].isna() & np.isfinite(lma_vals)
    result.loc[lma_mask, "sla_mm2_mg"] = lma_vals[lma_mask]
    result.loc[lma_mask, "sla_source"] = "derived_from_lma"

    result.loc[result["sla_mm2_mg"].isna(), "sla_source"] = pd.NA
    result["logSLA"] = np.where(result["sla_mm2_mg"] > 0, np.log(result["sla_mm2_mg"]), np.nan)
    return result


def combine_traits(try_df: pd.DataFrame, aust_df: pd.DataFrame) -> pd.DataFrame:
    """Merge TRY and AusTraits aggregates and compute derived columns."""
    merged = try_df.join(aust_df, how="outer")

    # Consolidate scientific names
    merged["wfo_scientific_name"] = merged["wfo_scientific_name"].combine_first(
        merged.pop("wfo_scientific_name_austraits")
    )

    # Fallback helpers
    merged["aust_sla"] = np.where(merged["aust_lma"] > 0, 1000.0 / merged["aust_lma"], np.nan)

    # Provenance columns start by reflecting the raw source tables; imputation will overwrite later.
    merged["leaf_area_source"] = np.where(merged["leaf_area_mm2"].notna(), "try_enhanced", None)
    merged["nmass_source"] = np.where(merged["try_nmass"].notna(), "try_enhanced", None)

    merged["ldmc_frac"] = merged["try_ldmc"].combine_first(merged["aust_ldmc"])
    merged["ldmc_source"] = np.where(
        merged["try_ldmc"].notna(),
        "try_enhanced",
        np.where(merged["aust_ldmc"].notna(), "austraits", None),
    )

    merged["lma_g_m2"] = merged["try_lma"].combine_first(merged["aust_lma"])
    merged["lma_source"] = np.where(
        merged["try_lma"].notna(),
        "try_enhanced",
        np.where(merged["aust_lma"].notna(), "austraits", None),
    )

    merged = assign_canonical_sla(merged)

    merged["seed_mass_mg"] = merged["try_seed_mass"].combine_first(merged["aust_seed_mass"])
    merged["seed_mass_source"] = np.where(
        merged["try_seed_mass"].notna(),
        "try_enhanced",
        np.where(merged["aust_seed_mass"].notna(), "austraits", None),
    )

    merged["plant_height_m"] = merged["try_height"].combine_first(merged["aust_height"])
    merged["height_source"] = np.where(
        merged["try_height"].notna(),
        "try_enhanced",
        np.where(merged["aust_height"].notna(), "austraits", None),
    )

    # Log columns
    merged["logLDMC"] = np.where(merged["ldmc_frac"] > 0, np.log(merged["ldmc_frac"]), np.nan)
    merged["logSM"] = np.where(merged["seed_mass_mg"] > 0, np.log(merged["seed_mass_mg"]), np.nan)
    merged["logH"] = np.where(merged["plant_height_m"] > 0, np.log(merged["plant_height_m"]), np.nan)
    merged["logLA"] = merged["try_logLA"]
    merged["logNmass"] = merged["try_logNmass"]

    merged.reset_index(inplace=True)
    master_path = DATA_STAGE1 / "master_taxa_union.parquet"
    if master_path.exists():
        master = pd.read_parquet(master_path)[["wfo_taxon_id", "wfo_scientific_name"]].copy()
        master["wfo_taxon_id"] = master["wfo_taxon_id"].astype(str)
        merged = master.merge(merged, on="wfo_taxon_id", how="left", suffixes=("_master", ""))
        merged["wfo_scientific_name"] = merged["wfo_scientific_name"].combine_first(
            merged.pop("wfo_scientific_name_master")
        )
    return merged


def load_bhpmf_output(path: Path) -> pd.DataFrame:
    """Load BHPMF output (CSV or Parquet)."""
    if not path.exists():
        raise FileNotFoundError(f"BHPMF output not found: {path}")

    if path.suffix.lower() == ".parquet":
        df = pd.read_parquet(path)
    else:
        df = pd.read_csv(path)

    if "wfo_taxon_id" not in df.columns:
        raise ValueError("BHPMF output must include a 'wfo_taxon_id' column.")

    df["wfo_taxon_id"] = df["wfo_taxon_id"].astype(str)
    return df


def apply_bhpmf(
    combined: pd.DataFrame,
    bhpmf_df: pd.DataFrame,
    ordered_cols: Sequence[str],
) -> pd.DataFrame:
    """Merge BHPMF predictions into the aggregated trait table with provenance."""
    merged = combined.copy()

    trait_map = {
        "Leaf area (mm2)": ("leaf_area_mm2", "leaf_area_source"),
        "Nmass (mg/g)": ("try_nmass", "nmass_source"),
        "LMA (g/m2)": ("lma_g_m2", "lma_source"),
        "Plant height (m)": ("plant_height_m", "height_source"),
        "Diaspore mass (mg)": ("seed_mass_mg", "seed_mass_source"),
        "LDMC": ("ldmc_frac", "ldmc_source"),
    }
    flag_map = {
        "Leaf area (mm2)": "Leaf area (mm2)_imputed_flag",
        "Nmass (mg/g)": "Nmass (mg/g)_imputed_flag",
        "LMA (g/m2)": "LMA (g/m2)_imputed_flag",
        "Plant height (m)": "Plant height (m)_imputed_flag",
        "Diaspore mass (mg)": "Diaspore mass (mg)_imputed_flag",
        "LDMC": "LDMC_imputed_flag",
    }

    subset_cols = ["wfo_taxon_id"]
    rename_map: dict[str, str] = {}
    for raw_col, (target_col, _) in trait_map.items():
        subset_cols.append(raw_col)
        rename_map[raw_col] = f"bhpmf_{target_col}"
        flag_col = flag_map[raw_col]
        subset_cols.append(flag_col)
        rename_map[flag_col] = f"bhpmf_{target_col}_flag"

    present_cols = [col for col in subset_cols if col in bhpmf_df.columns]
    missing_cols = set(subset_cols) - set(present_cols)
    if missing_cols:
        missing = ", ".join(sorted(missing_cols))
        raise ValueError(f"BHPMF output missing expected columns: {missing}")

    bhpmf_subset = bhpmf_df[present_cols].rename(columns=rename_map)
    merged = merged.merge(bhpmf_subset, on="wfo_taxon_id", how="left")

    invalid_rules = {
        "leaf_area_mm2": lambda s: s <= 0,
        "try_nmass": lambda s: s <= 0,
        "lma_g_m2": lambda s: s <= 0,
        "plant_height_m": lambda s: s <= 0,
        "seed_mass_mg": lambda s: s <= 0,
        "ldmc_frac": lambda s: (s <= 0) | (s >= 1),
    }

    for raw_col, (target_col, source_col) in trait_map.items():
        value_col = rename_map[raw_col]
        flag_col = rename_map[flag_map[raw_col]]

        if value_col not in merged.columns:
            continue

        value_mask = merged[value_col].notna()
        invalid_mask = merged[target_col].isna()
        rule = invalid_rules.get(target_col)
        if rule is not None:
            invalid_mask |= rule(merged[target_col])

        replace_mask = value_mask & invalid_mask
        merged.loc[replace_mask, target_col] = merged.loc[replace_mask, value_col]

        if source_col:
            impute_mask = (merged[flag_col] == 1) | replace_mask
            merged.loc[impute_mask, source_col] = "bhpmf_imputed"

    provenance_pairs = [
        ("leaf_area_mm2", "leaf_area_source"),
        ("try_nmass", "nmass_source"),
        ("ldmc_frac", "ldmc_source"),
        ("lma_g_m2", "lma_source"),
        ("seed_mass_mg", "seed_mass_source"),
        ("plant_height_m", "height_source"),
    ]
    for value_col, source_col in provenance_pairs:
        if source_col in merged.columns:
            merged.loc[merged[value_col].isna(), source_col] = pd.NA

    merged = assign_canonical_sla(merged)
    merged["logLDMC"] = np.where(merged["ldmc_frac"] > 0, np.log(merged["ldmc_frac"]), np.nan)
    merged["logSM"] = np.where(merged["seed_mass_mg"] > 0, np.log(merged["seed_mass_mg"]), np.nan)
    merged["logH"] = np.where(merged["plant_height_m"] > 0, np.log(merged["plant_height_m"]), np.nan)
    merged["logLA"] = np.where(merged["leaf_area_mm2"] > 0, np.log(merged["leaf_area_mm2"]), np.nan)
    merged["logNmass"] = np.where(merged["try_nmass"] > 0, np.log(merged["try_nmass"]), np.nan)

    drop_cols = [rename_map[col] for col in subset_cols if col in rename_map]
    merged = merged.drop(columns=drop_cols, errors="ignore")

    ordered = list(ordered_cols)
    ordered += [col for col in merged.columns if col not in ordered]
    merged = merged.reindex(columns=ordered)
    return merged


def build_modelling_subset(traits: pd.DataFrame, stamp: str) -> pd.DataFrame:
    """Create BHPMF modelling shortlist input."""
    if not MODELLING_SHORTLIST.exists():
        raise FileNotFoundError(f"Modelling shortlist missing: {MODELLING_SHORTLIST}")
    if not WFO_TAXONOMY.exists():
        raise FileNotFoundError(f"WFO taxonomy subset missing: {WFO_TAXONOMY}")

    shortlist = pd.read_parquet(MODELLING_SHORTLIST)[["wfo_taxon_id", "canonical_name"]].drop_duplicates()
    taxonomy = pd.read_parquet(WFO_TAXONOMY).rename(
        columns={"taxonID": "wfo_taxon_id", "family": "Family", "genus": "Genus"}
    )
    taxonomy["wfo_taxon_id"] = taxonomy["wfo_taxon_id"].astype(str)

    merged = shortlist.merge(traits, on="wfo_taxon_id", how="left")
    merged = merged.merge(taxonomy, on="wfo_taxon_id", how="left")

    merged.rename(columns={"wfo_scientific_name": "wfo_accepted_name"}, inplace=True)
    merged["wfo_accepted_name"] = merged["wfo_accepted_name"].combine_first(merged["canonical_name"])

    # Prepare BHPMF columns
    bhpmf = pd.DataFrame({
        "wfo_taxon_id": merged["wfo_taxon_id"],
        "wfo_accepted_name": merged["wfo_accepted_name"],
        "Genus": merged["Genus"],
        "Family": merged["Family"],
        "Leaf area (mm2)": merged["leaf_area_mm2"],
        "Nmass (mg/g)": merged["try_nmass"],
        "LMA (g/m2)": merged["lma_g_m2"],
        "Plant height (m)": merged["plant_height_m"],
        "Diaspore mass (mg)": merged["seed_mass_mg"],
        "LDMC": merged["ldmc_frac"],
        "SSD used (mg/mm3)": 0.0,
        "logLA": merged["logLA"],
        "logLDMC": merged["logLDMC"],
        "logSLA": merged["logSLA"],
        "logSM": merged["logSM"],
        "logH": merged["logH"],
        "logNmass": merged["logNmass"],
    })

    out_base = f"trait_imputation_input_modelling_shortlist_{stamp}"
    csv_path = MODEL_INPUTS / f"{out_base}.csv"
    parquet_path = MODEL_INPUTS / f"{out_base}.parquet"
    bhpmf.to_csv(csv_path, index=False)
    bhpmf.to_parquet(parquet_path, index=False)
    return bhpmf


def write_parquet(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, index=False)


def write_parquet_and_csv(df: pd.DataFrame, parquet_path: Path) -> None:
    write_parquet(df, parquet_path)
    csv_path = parquet_path.with_suffix(".csv")
    df.to_csv(csv_path, index=False)


def main(stamp: str, bhpmf_output: Optional[str]) -> None:
    try_df = load_try_aggregates()
    aust_df = load_austraits_aggregates()
    combined = combine_traits(try_df, aust_df)

    ordered_cols: Sequence[str] = [
        "wfo_taxon_id",
        "wfo_scientific_name",
        "leaf_area_mm2",
        "leaf_area_n",
        "leaf_area_source",
        "try_nmass",
        "try_logNmass",
        "nmass_source",
        "try_ldmc",
        "aust_ldmc",
        "ldmc_frac",
        "ldmc_source",
        "try_lma",
        "aust_lma",
        "lma_g_m2",
        "lma_source",
        "try_sla",
        "aust_sla",
        "sla_mm2_mg",
        "sla_source",
        "try_seed_mass",
        "aust_seed_mass",
        "seed_mass_mg",
        "seed_mass_source",
        "try_height",
        "aust_height",
        "plant_height_m",
        "height_source",
        "try_logLA",
        "logLDMC",
        "logSLA",
        "logSM",
        "logH",
        "logLA",
        "logNmass",
    ]
    combined = combined.reindex(columns=ordered_cols)

    out_base = f"traits_model_ready_{stamp}.parquet"
    stage1_path = DATA_STAGE1 / out_base
    model_path = MODEL_INPUTS / out_base

    write_parquet(combined, stage1_path)
    write_parquet(combined, model_path)

    build_modelling_subset(combined, stamp=stamp)

    if bhpmf_output:
        bhpmf_df = load_bhpmf_output(Path(bhpmf_output))
        combined_imputed = apply_bhpmf(combined, bhpmf_df, ordered_cols)

        imputed_base = f"traits_model_ready_{stamp}_imputed.parquet"
        write_parquet(combined_imputed, DATA_STAGE1 / imputed_base)
        write_parquet(combined_imputed, MODEL_INPUTS / imputed_base)

        if SHORTLIST_GE30.exists():
            shortlist_ids = pd.read_parquet(SHORTLIST_GE30)["wfo_taxon_id"].astype(str)
            shortlist_traits = combined_imputed[combined_imputed["wfo_taxon_id"].isin(shortlist_ids)]
            write_parquet_and_csv(
                shortlist_traits,
                MODEL_INPUTS / f"traits_model_ready_{stamp}_shortlist.parquet",
            )

        if MODELLING_SHORTLIST_GE30.exists():
            modelling_ids = pd.read_parquet(MODELLING_SHORTLIST_GE30)["wfo_taxon_id"].astype(str)
            modelling_traits = combined_imputed[combined_imputed["wfo_taxon_id"].isin(modelling_ids)]
            write_parquet_and_csv(
                modelling_traits,
                MODEL_INPUTS / f"traits_model_ready_{stamp}_ge30.parquet",
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Rebuild Stage 1 trait aggregation artefacts.")
    parser.add_argument(
        "--stamp",
        default=dt.date.today().strftime("%Y%m%d"),
        help="Label for output files (default: today's date, YYYYMMDD).",
    )
    parser.add_argument(
        "--bhpmf-output",
        default=None,
        help="Optional path to BHPMF output (CSV or Parquet) to merge into the final tables.",
    )
    args = parser.parse_args()
    main(args.stamp, args.bhpmf_output)
