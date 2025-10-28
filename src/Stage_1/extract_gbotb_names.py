#!/usr/bin/env python3
"""
Extract species names from GBOTB.extended.TPL for WorldFlora matching.

Purpose:
    V.PhyloMaker2 uses GBOTB taxonomy (APG IV), but we use WFO taxonomy.
    This script extracts all GBOTB species names to match them to WFO IDs
    using the canonical WorldFlora matching pipeline.

Output:
    data/phylogeny/gbotb_names_for_wfo.csv

Usage:
    conda run -n AI python src/Stage_1/extract_gbotb_names.py
"""

import subprocess
import pandas as pd
from pathlib import Path

def extract_gbotb_from_r():
    """
    Extract GBOTB.extended.TPL dataset from R.

    Returns:
        DataFrame with columns: species, genus, family
    """
    print("Extracting GBOTB.extended.TPL from V.PhyloMaker2...")

    r_script = """
    library(V.PhyloMaker2)
    data("tips.info.TPL", package = "V.PhyloMaker2")

    # Extract species information (already contains species, genus, family)
    gbotb_df <- tips.info.TPL[, c("species", "genus", "family")]
    gbotb_df <- unique(gbotb_df)

    # Write to temp CSV
    write.csv(gbotb_df, "/tmp/gbotb_species.csv", row.names = FALSE)

    cat(sprintf("Extracted %d species from GBOTB tips.info.TPL\\n", nrow(gbotb_df)))
    """

    # Run R script using system R with custom .Rlib
    cmd = [
        "env", "R_LIBS_USER=/home/olier/ellenberg/.Rlib",
        "/usr/bin/Rscript", "-e", r_script
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("STDERR:", result.stderr)
        raise RuntimeError(f"Failed to extract GBOTB: {result.stderr}")

    print(result.stdout)

    # Read result
    df = pd.read_csv("/tmp/gbotb_species.csv")
    return df


def prepare_for_worldflora(gbotb_df):
    """
    Prepare GBOTB names for WorldFlora matching.

    Args:
        gbotb_df: DataFrame with species, genus, family

    Returns:
        DataFrame ready for WorldFlora with columns:
            gbotb_id, scientific_name, genus, family
    """
    print("\nPreparing names for WorldFlora...")

    # Create scientific name from genus + species epithet
    # GBOTB format: species = "Genus_species"
    df = gbotb_df.copy()

    # Convert underscore to space for scientific name
    df['scientific_name'] = df['species'].str.replace('_', ' ')

    # Add unique ID
    df['gbotb_id'] = range(len(df))

    # Select and reorder columns
    result = df[['gbotb_id', 'scientific_name', 'genus', 'family', 'species']].copy()

    print(f"  Prepared {len(result):,} species for matching")
    print(f"  Columns: {', '.join(result.columns)}")

    return result


def main():
    print("=" * 80)
    print("EXTRACT GBOTB SPECIES FOR WFO MATCHING")
    print("=" * 80)

    # Extract from R
    gbotb_df = extract_gbotb_from_r()

    # Prepare for WorldFlora
    wf_ready = prepare_for_worldflora(gbotb_df)

    # Save
    output_path = Path("data/phylogeny/gbotb_names_for_wfo.csv")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    wf_ready.to_csv(output_path, index=False)

    print(f"\n✓ Saved to: {output_path}")
    print(f"✓ Species count: {len(wf_ready):,}")

    print("\n" + "=" * 80)
    print("NEXT STEP:")
    print("env R_LIBS_USER=/home/olier/ellenberg/.Rlib \\")
    print("  /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_gbotb_match.R")
    print("=" * 80)


if __name__ == '__main__':
    main()
