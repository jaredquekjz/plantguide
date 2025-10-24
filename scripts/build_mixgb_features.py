#!/usr/bin/env python3
"""Assemble feature matrices for mixgb imputations.

This helper consolidates trait aggregates, categorical descriptors,
phylogenetic predictors, and environmental summaries into a single
dataset ready for mixgb. It mirrors the Stage 1 modelling feature
construction but supports arbitrary rosters via CLI arguments.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable

import duckdb
import pandas as pd


def read_csv(path: Path, columns: Iterable[str] | None = None) -> pd.DataFrame:
    # Handle both CSV and parquet files
    if str(path).endswith('.parquet'):
        df = pd.read_parquet(path)
    else:
        df = pd.read_csv(path)
    if columns is not None:
        missing = [col for col in columns if col not in df.columns]
        if missing:
            raise KeyError(f"Missing columns in {path}: {missing}")
        df = df[list(columns)]
    return df


def read_parquet_with_duckdb(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(path)
    escaped = str(path).replace("'", "''")
    return duckdb.query(f"SELECT * FROM read_parquet('{escaped}')").to_df()


def write_parquet(df: pd.DataFrame, path: Path) -> None:
    con = duckdb.connect()
    try:
        con.register("mixgb_df", df)
        con.execute("COPY mixgb_df TO ? (FORMAT 'parquet')", [str(path)])
    finally:
        con.unregister("mixgb_df")
        con.close()


def main(args: argparse.Namespace) -> None:
    roster_path = Path(args.roster_csv)
    traits_path = Path(args.traits_csv)
    categorical_path = Path(args.categorical_parquet)
    proxy_path = Path(args.phylo_proxy_parquet) if args.phylo_proxy_parquet else None
    env_path = Path(args.env_csv)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_prefix = args.output_prefix

    roster = read_csv(roster_path, columns=[args.roster_id_column])
    roster = roster.rename(columns={args.roster_id_column: "wfo_taxon_id"})
    roster["wfo_taxon_id"] = roster["wfo_taxon_id"].astype(str)
    expected = args.expected_species
    if expected is not None and len(roster) != expected:
        raise ValueError(
            f"Roster count mismatch: expected {expected}, found {len(roster)} in {roster_path}."
        )

    traits = read_csv(traits_path)
    if "wfo_taxon_id" not in traits.columns:
        raise KeyError("Traits file must include 'wfo_taxon_id'.")
    traits["wfo_taxon_id"] = traits["wfo_taxon_id"].astype(str)

    # Drop provenance columns - they serve no modeling purpose
    provenance_cols = ["leaf_area_source", "nmass_source", "ldmc_source", "lma_source",
                       "height_source", "seed_mass_source", "sla_source"]
    dropped_provenance = [col for col in provenance_cols if col in traits.columns]
    if dropped_provenance:
        traits = traits.drop(columns=dropped_provenance)
        print(f"[ok] Dropped {len(dropped_provenance)} provenance columns: {', '.join(dropped_provenance)}")

    # Drop redundant metadata columns
    redundant_cols = [
        # Alternate trait sources (duplicates of target traits)
        'try_ldmc', 'aust_ldmc', 'try_lma', 'aust_lma',
        'try_sla', 'aust_sla', 'sla_mm2_mg',
        'try_seed_mass', 'aust_seed_mass', 'try_height', 'aust_height',
        # Log transforms (XGBoost handles non-linearity)
        'try_logNmass', 'logNmass', 'try_logLA', 'logLA',
        'logLDMC', 'logSLA', 'logSM', 'logH',
        # Sample size metadata
        'leaf_area_n',
        # Text taxonomy (redundant with numeric codes)
        'genus', 'family'
    ]
    dropped_redundant = [col for col in redundant_cols if col in traits.columns]
    if dropped_redundant:
        traits = traits.drop(columns=dropped_redundant)
        print(f"[ok] Dropped {len(dropped_redundant)} redundant metadata columns")

    # Harmonise column names with modelling dataset conventions.
    if "try_nmass" in traits.columns and "nmass_mg_g" not in traits.columns:
        traits = traits.rename(columns={"try_nmass": "nmass_mg_g"})
    if "try_logNmass" in traits.columns and "logNmass" not in traits.columns:
        traits = traits.rename(columns={"try_logNmass": "logNmass"})

    categorical = read_parquet_with_duckdb(categorical_path)
    categorical = categorical.rename(columns={"wfo_id": "wfo_taxon_id"})
    categorical["wfo_taxon_id"] = categorical["wfo_taxon_id"].astype(str)

    # Filter to only requested categorical traits if specified
    if args.categorical_traits:
        requested = [t.strip() for t in args.categorical_traits.split(",")]
        keep_cat = ["wfo_taxon_id"] + [col for col in requested if col in categorical.columns]
        missing = [col for col in requested if col not in categorical.columns]
        if missing:
            print(f"[warn] Categorical traits not found: {missing}", file=sys.stderr)
        categorical = categorical[keep_cat]
        print(f"[ok] Filtered to {len(keep_cat)-1} categorical traits: {', '.join(keep_cat[1:])}")

    # Phylo proxy features (OPTIONAL - can be skipped entirely)
    proxy = None
    if not args.skip_phylo_proxy and proxy_path is not None:
        proxy = read_parquet_with_duckdb(proxy_path)
        proxy["wfo_taxon_id"] = proxy["wfo_taxon_id"].astype(str)

        # Drop text taxonomy columns (genus, family) - keep only numeric codes
        text_taxonomy = ['genus', 'family']
        dropped_text = [col for col in text_taxonomy if col in proxy.columns]
        if dropped_text:
            proxy = proxy.drop(columns=dropped_text)
            print(f"[ok] Dropped text taxonomy: {', '.join(dropped_text)} (keeping numeric codes)")

        print(f"[ok] Loaded phylo proxy features: {len(proxy)} species")
    elif args.skip_phylo_proxy:
        print("[ok] Skipping phylogenetic proxy features")

    env = read_csv(env_path)
    if "wfo_taxon_id" not in env.columns:
        raise KeyError("Environmental summary must include 'wfo_taxon_id'.")
    env["wfo_taxon_id"] = env["wfo_taxon_id"].astype(str)
    drop_env_cols = ["species", "wfo_accepted_name", "Genus", "Family"]
    env = env[[col for col in env.columns if col not in drop_env_cols]]

    # Load RAW EIVE values if provided (from eive_worldflora_enriched.parquet)
    # Note: This loads EIVEres-T/M/L/N/R columns (with hyphens) and renames to underscores
    eive_values = None
    if args.eive_raw_path:
        eive_path = Path(args.eive_raw_path)
        if eive_path.exists():
            if str(eive_path).endswith('.parquet'):
                eive_raw = read_parquet_with_duckdb(eive_path)
            else:
                eive_raw = pd.read_csv(eive_path)

            # Deduplicate by wfo_taxon_id
            eive_raw = eive_raw.drop_duplicates(subset='wfo_taxon_id', keep='first')
            eive_raw["wfo_taxon_id"] = eive_raw["wfo_taxon_id"].astype(str)

            # Select only EIVE columns with hyphens (raw values, not processed)
            eive_cols_hyphen = ['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']
            available_cols = ['wfo_taxon_id'] + [c for c in eive_cols_hyphen if c in eive_raw.columns]

            if len(available_cols) > 1:
                eive_values = eive_raw[available_cols].copy()
                # Rename hyphens to underscores for consistency
                rename_map = {c: c.replace('-', '_') for c in eive_cols_hyphen if c in eive_values.columns}
                eive_values = eive_values.rename(columns=rename_map)
                print(f"[ok] Loaded {len(rename_map)} RAW EIVE columns: {', '.join(rename_map.values())}")
            else:
                print(f"[warn] No EIVEres-* columns found in {eive_path}", file=sys.stderr)
        else:
            print(f"[warn] RAW EIVE file not found: {eive_path}", file=sys.stderr)

    df = roster.merge(traits, on="wfo_taxon_id", how="left")
    df = df.merge(categorical, on="wfo_taxon_id", how="left")
    if proxy is not None:
        df = df.merge(proxy, on="wfo_taxon_id", how="left")
    if eive_values is not None:
        df = df.merge(eive_values, on="wfo_taxon_id", how="left")
    df = df.merge(env, on="wfo_taxon_id", how="left")

    # Reattach canonical scientific name if present in traits; otherwise fallback to roster field.
    if "wfo_scientific_name" not in df.columns:
        df["wfo_scientific_name"] = df.pop(args.roster_name_column) if args.roster_name_column in df.columns else ""

    # Coverage checks (failure is preferable to silent gaps).
    env_cols = [col for col in df.columns if col.endswith("_q50")]
    if not env_cols:
        raise ValueError("Environmental data merge produced no *_q50 columns.")

    # Align column order with legacy mixgb dataset when possible for downstream reuse.
    reference_cols: list[str] = []
    if args.reference_csv:
        ref_path = Path(args.reference_csv)
        if ref_path.exists():
            reference_cols = pd.read_csv(ref_path, nrows=0).columns.tolist()
        else:
            print(f"[warn] Reference CSV {ref_path} not found; column order may differ.", file=sys.stderr)
    ordered_cols = [col for col in reference_cols if col in df.columns]
    remaining_cols = [col for col in df.columns if col not in ordered_cols]
    df = df[ordered_cols + remaining_cols]

    output_csv = output_dir / f"{output_prefix}.csv"
    output_parquet = output_dir / f"{output_prefix}.parquet"
    df.to_csv(output_csv, index=False)
    write_parquet(df, output_parquet)

    print(f"[ok] Assembled mixgb matrix with {len(df)} species and {df.shape[1]} columns.")
    print(f"[ok] Wrote CSV to {output_csv}")
    print(f"[ok] Wrote Parquet to {output_parquet}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build mixgb-ready feature matrices.")
    parser.add_argument("--roster-csv", required=True, help="Path to roster CSV with wfo_taxon_id column.")
    parser.add_argument("--roster-id-column", default="wfo_taxon_id", help="Column name in roster for species ID.")
    parser.add_argument("--roster-name-column", default="canonical_name", help="Optional roster column for display names.")
    parser.add_argument("--traits-csv", required=True, help="Path to trait aggregation CSV (Stage 1 output).")
    parser.add_argument("--categorical-parquet", required=True, help="Parquet file with TRY categorical descriptors.")
    parser.add_argument("--phylo-proxy-parquet", default=None, help="Parquet file with phylogenetic proxy features (optional if --skip-phylo-proxy is used).")
    parser.add_argument("--env-csv", required=True, help="Environmental summary CSV (median *_q50 columns).")
    parser.add_argument("--output-dir", required=True, help="Directory for the assembled dataset.")
    parser.add_argument("--output-prefix", required=True, help="Basename for output files (without extension).")
    parser.add_argument("--expected-species", type=int, default=None, help="Expected roster row count for safety checks.")
    parser.add_argument("--reference-csv", default="model_data/inputs/mixgb/mixgb_input_20251022.csv", help="Existing mixgb CSV to mirror column ordering.")
    parser.add_argument("--categorical-traits", default=None, help="Comma-separated list of categorical trait columns to include (e.g., try_woodiness,try_growth_form)")
    parser.add_argument("--eive-raw-path", default=None, help="Optional path to RAW EIVE source parquet/csv file (EIVEres-T/M/L/N/R columns with hyphens)")
    parser.add_argument("--skip-phylo-proxy", action="store_true", help="Skip loading phylogenetic proxy features entirely")
    main(parser.parse_args())
