#!/usr/bin/env python3
"""Build comprehensive dataset combining traits, bioclim, GloBI, EIVE, and Stage 7 reliability.

Merges:
1. Traits + GloBI features (654 species) - base dataset
2. Bioclim climate variables (species-level aggregates)
3. Stage 7 validation labels (qualitative EIVE descriptions)
4. Stage 7 alignment reliability metrics (10 species processed so far)

Excludes: Soil variables (per user request)

Output: data/comprehensive_dataset_no_soil.csv
"""

from pathlib import Path
import pandas as pd
import json
import logging

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]

# Input paths
TRAITS_GLOBI = REPO_ROOT / "artifacts/globi_mapping/stage3_traits_with_globi_features.csv"
BIOCLIM = REPO_ROOT / "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv"
STAGE7_LABELS = REPO_ROOT / "data/stage7_validation_eive_labels.csv"
ALIGNMENT_DIR = REPO_ROOT / "results/stage7_alignment"

# Output path
OUTPUT = REPO_ROOT / "data/comprehensive_dataset_no_soil.csv"


def load_base_dataset():
    """Load traits + GloBI features as base (654 species)."""
    logger.info("Loading traits + GloBI dataset...")
    df = pd.read_csv(TRAITS_GLOBI)
    logger.info(f"  Loaded {len(df)} species with {len(df.columns)} columns")
    return df


def load_bioclim():
    """Load bioclim variables (1009 species, will left join)."""
    logger.info("Loading bioclim climate variables...")
    df = pd.read_csv(BIOCLIM)
    logger.info(f"  Loaded {len(df)} species with {len(df.columns)} columns")
    # Rename 'species' to match join key
    df = df.rename(columns={"species": "wfo_accepted_name"})
    return df


def load_stage7_labels():
    """Load Stage 7 validation labels with qualitative EIVE bins (405 species)."""
    logger.info("Loading Stage 7 validation labels...")
    df = pd.read_csv(STAGE7_LABELS)
    logger.info(f"  Loaded {len(df)} species with qualitative EIVE labels")
    # Rename to match join key
    df = df.rename(columns={"stage2_species": "wfo_accepted_name"})
    # Select only the columns we want to add (qualitative labels + legacy mapping)
    keep_cols = [
        "wfo_accepted_name",
        "legacy_slug",
        "legacy_path",
        "destination_path",
        "L_label",
        "M_label",
        "R_label",
        "N_label",
        "T_label"
    ]
    return df[keep_cols]


def parse_alignment_verdict(json_path):
    """Parse a single alignment verdict JSON and extract per-axis reliability metrics."""
    with open(json_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Strip markdown code fences if present (LLM may return ```json...```)
    if content.startswith("```json"):
        content = content[7:].strip()
    if content.startswith("```"):
        content = content[3:].strip()
    if content.endswith("```"):
        content = content[:-3].strip()

    data = json.loads(content)

    metrics = {}
    for axis_data in data.get("axes", []):
        axis = axis_data["axis"]
        metrics[f"{axis}_verdict"] = axis_data.get("verdict")
        metrics[f"{axis}_reliability_score"] = axis_data.get("reliability_score")
        metrics[f"{axis}_confidence"] = axis_data.get("confidence")
        metrics[f"{axis}_reliability_label"] = axis_data.get("reliability_label")
        metrics[f"{axis}_verdict_numeric"] = axis_data.get("verdict_numeric")
        metrics[f"{axis}_support_count"] = axis_data.get("support_count")
        metrics[f"{axis}_contradict_count"] = axis_data.get("contradict_count")
        metrics[f"{axis}_strength"] = axis_data.get("strength")
        metrics[f"{axis}_has_conflict"] = axis_data.get("has_conflict")

    return metrics


def load_stage7_alignment():
    """Load Stage 7 alignment reliability metrics from JSON files."""
    logger.info("Loading Stage 7 alignment reliability metrics...")

    if not ALIGNMENT_DIR.exists():
        logger.warning(f"  Alignment directory not found: {ALIGNMENT_DIR}")
        return pd.DataFrame()

    alignment_data = []
    for json_file in sorted(ALIGNMENT_DIR.glob("*.json")):
        slug = json_file.stem
        metrics = parse_alignment_verdict(json_file)
        metrics["legacy_slug"] = slug
        alignment_data.append(metrics)

    if not alignment_data:
        logger.warning("  No alignment verdicts found")
        return pd.DataFrame()

    df = pd.DataFrame(alignment_data)
    logger.info(f"  Loaded {len(df)} species with reliability metrics")
    return df


def merge_datasets():
    """Merge all datasets into comprehensive output."""
    logger.info("\n=== Building Comprehensive Dataset ===\n")

    # 1. Start with base dataset (traits + GloBI + EIVE)
    df = load_base_dataset()
    initial_cols = len(df.columns)
    initial_rows = len(df)

    # 2. Merge bioclim (left join - keep all base species)
    bioclim = load_bioclim()
    df = df.merge(bioclim, on="wfo_accepted_name", how="left", suffixes=("", "_bioclim"))
    logger.info(f"\nAfter bioclim merge: {len(df)} rows, {len(df.columns)} columns (+{len(df.columns) - initial_cols})")

    # 3. Merge Stage 7 labels (left join - only 405 species have labels)
    stage7_labels = load_stage7_labels()
    df = df.merge(stage7_labels, on="wfo_accepted_name", how="left")
    logger.info(f"After Stage 7 labels merge: {len(df)} rows, {len(df.columns)} columns")
    logger.info(f"  Species with qualitative labels: {df['L_label'].notna().sum()}/{len(df)}")

    # 4. Merge Stage 7 alignment (via legacy_slug, then join back)
    alignment = load_stage7_alignment()
    if not alignment.empty:
        df = df.merge(alignment, on="legacy_slug", how="left")
        logger.info(f"After Stage 7 alignment merge: {len(df)} rows, {len(df.columns)} columns")
        logger.info(f"  Species with reliability metrics: {df['L_verdict'].notna().sum()}/{len(df)}")
    else:
        logger.warning("No alignment data to merge")

    # Sanity check
    if len(df) != initial_rows:
        logger.error(f"ERROR: Row count changed from {initial_rows} to {len(df)}!")

    return df


def save_dataset(df):
    """Save comprehensive dataset to CSV."""
    logger.info(f"\nSaving comprehensive dataset to {OUTPUT}...")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUTPUT, index=False)
    logger.info(f"  Saved {len(df)} species × {len(df.columns)} columns")
    logger.info(f"\n✓ Comprehensive dataset created: {OUTPUT}")


def print_summary(df):
    """Print summary statistics."""
    logger.info("\n=== Dataset Summary ===")
    logger.info(f"Total species: {len(df)}")
    logger.info(f"Total columns: {len(df.columns)}")
    logger.info(f"\nData completeness:")
    logger.info(f"  EIVE values: {df['EIVEres-L'].notna().sum()}/{len(df)}")
    logger.info(f"  Bioclim variables: {df['bio1_mean'].notna().sum()}/{len(df)}")
    logger.info(f"  GloBI interactions: {df['globi_total_records'].notna().sum()}/{len(df)}")
    logger.info(f"  Stage 7 qualitative labels: {df['L_label'].notna().sum()}/{len(df)}")
    if "L_verdict" in df.columns:
        logger.info(f"  Stage 7 reliability metrics: {df['L_verdict'].notna().sum()}/{len(df)}")

    logger.info(f"\nColumn groups:")
    logger.info(f"  Trait columns: ~120")
    logger.info(f"  Bioclim columns: ~80 (mean, SD, quantiles, aridity)")
    logger.info(f"  GloBI columns: ~20")
    logger.info(f"  EIVE columns: 5 (L, M, R, N, T)")
    logger.info(f"  Stage 7 qualitative: 5 (L_label, M_label, etc.)")
    if "L_verdict" in df.columns:
        logger.info(f"  Stage 7 reliability: ~45 (9 metrics × 5 axes)")


def main():
    """Main execution."""
    df = merge_datasets()
    print_summary(df)
    save_dataset(df)


if __name__ == "__main__":
    main()
