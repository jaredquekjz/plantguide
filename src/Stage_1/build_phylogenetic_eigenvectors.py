#!/usr/bin/env python3
"""
Extract phylogenetic eigenvectors from newick tree using VCV matrix decomposition.

Workflow:
1. Load phylogenetic tree (newick format with ~11k unique species)
2. Load WFO→tree mapping (links all ~11.7k species including subspecies to tree tips)
3. Build VCV matrix using R's ape::vcv() (gold standard)
4. Eigendecomposition
5. Broken stick rule to select K eigenvectors
6. Map eigenvectors to ALL species (infraspecific taxa inherit parent eigenvectors)
7. Save eigenvector matrix for all species

Based on: Moura et al. 2024, PLoS Biology
"A phylogeny-informed characterisation of global tetrapod traits addresses data gaps and biases"
DOI: https://doi.org/10.1371/journal.pbio.3002658

Usage:
conda run -n AI python src/Stage_1/build_phylogenetic_eigenvectors.py \
  --tree=data/phylogeny/mixgb_tree_11008_species_20251027.nwk \
  --mapping=data/phylogeny/mixgb_wfo_to_tree_mapping_11680.csv \
  --output=model_data/inputs/phylo_eigenvectors_11680_20251027.csv
"""

import argparse
import numpy as np
import pandas as pd
from pathlib import Path
import sys
import subprocess
import os

def load_tree_and_build_vcv(tree_path, vcv_output_path=None):
    """
    Load newick tree and build VCV matrix using R's ape package.

    Args:
        tree_path: Path to newick tree file
        vcv_output_path: Optional path to save VCV matrix CSV

    Returns:
        vcv_matrix: numpy array (n_species × n_species)
        species_ids: list of wfo IDs
    """
    print(f"\n[1] Loading phylogenetic tree and building VCV matrix")
    print(f"  Tree file: {tree_path}")

    # Create temporary VCV matrix file if not specified
    if vcv_output_path is None:
        vcv_output_path = Path("model_data/inputs/phylo_vcv_matrix_11680_temp.csv")
    else:
        vcv_output_path = Path(vcv_output_path)

    vcv_output_path.parent.mkdir(parents=True, exist_ok=True)

    # Call R script to compute VCV matrix
    print("  Building VCV matrix using ape::vcv() (via R script)...")

    r_script = "src/Stage_1/compute_vcv_matrix.R"

    # Use system Rscript with custom R library (conda R is broken)
    # System R can load nlme from system libs and ape from custom .Rlib
    cmd = [
        "env", "R_LIBS_USER=/home/olier/ellenberg/.Rlib",
        "/usr/bin/Rscript",
        r_script, str(tree_path), str(vcv_output_path)
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to build VCV matrix")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
        sys.exit(1)

    # Load VCV matrix from CSV
    print(f"\n[2] Loading VCV matrix from CSV...")
    vcv_df = pd.read_csv(vcv_output_path, index_col=0)
    vcv_matrix = vcv_df.values
    species_ids = vcv_df.index.tolist()

    print(f"  ✓ VCV matrix: {vcv_matrix.shape[0]:,} × {vcv_matrix.shape[1]:,}")
    print(f"  ✓ Matrix size: {vcv_matrix.nbytes / 1e9:.2f} GB")
    print(f"  ✓ Extracted {len(species_ids):,} species IDs")

    # Verify VCV matrix properties
    is_symmetric = np.allclose(vcv_matrix, vcv_matrix.T)
    print(f"  ✓ VCV matrix symmetric: {is_symmetric}")

    if not is_symmetric:
        print(f"  WARNING: VCV matrix not symmetric - taking average with transpose")
        vcv_matrix = (vcv_matrix + vcv_matrix.T) / 2

    return vcv_matrix, species_ids


def broken_stick_rule(eigenvalues):
    """
    Apply broken stick rule to select number of eigenvectors to retain.

    Keep eigenvalue k if:
        eigenvalue[k] / sum(eigenvalues) > broken_stick[k]

    where broken_stick[k] = (1/n) * sum(1/i for i in k to n)

    Args:
        eigenvalues: numpy array of eigenvalues (sorted descending)

    Returns:
        n_keep: number of eigenvectors to retain
    """
    n = len(eigenvalues)

    # Compute broken stick distribution
    broken_stick = np.array([
        sum(1/i for i in range(k, n+1)) / n
        for k in range(1, n+1)
    ])

    # Proportion of variance explained by each eigenvalue
    eigenvalue_proportions = eigenvalues / eigenvalues.sum()

    # Keep eigenvectors where observed > expected by chance
    keep_mask = eigenvalue_proportions > broken_stick
    n_keep = keep_mask.sum()

    print(f"\n[4] Broken stick rule:")
    print(f"  Total eigenvalues: {n:,}")
    print(f"  Eigenvalues to keep: {n_keep:,}")
    print(f"  Proportion retained: {n_keep/n*100:.1f}%")
    print(f"  Variance explained: {eigenvalue_proportions[:n_keep].sum()*100:.1f}%")

    # Show top 10 eigenvalues
    print(f"\n  Top 10 eigenvalues:")
    for i in range(min(10, len(eigenvalues))):
        status = "KEEP" if i < n_keep else "DROP"
        print(f"    [{i+1:3d}] λ={eigenvalues[i]:10.4f} "
              f"({eigenvalue_proportions[i]*100:5.2f}%) "
              f"vs broken_stick={broken_stick[i]*100:5.2f}% [{status}]")

    return n_keep


def extract_eigenvectors(vcv_matrix, species_ids):
    """
    Perform eigendecomposition and select eigenvectors using broken stick rule.

    Args:
        vcv_matrix: numpy array (n_species × n_species)
        species_ids: list of wfo IDs

    Returns:
        df_eigenvectors: DataFrame with wfo_taxon_id + phylo_ev1...phylo_evK
    """
    print(f"\n[3] Eigendecomposition")
    print(f"  Computing eigenvalues and eigenvectors...")

    # Eigendecomposition (eigh for symmetric matrices)
    eigenvalues, eigenvectors = np.linalg.eigh(vcv_matrix)

    # Sort descending (eigh returns ascending)
    idx = eigenvalues.argsort()[::-1]
    eigenvalues = eigenvalues[idx]
    eigenvectors = eigenvectors[:, idx]

    print(f"  ✓ Computed {len(eigenvalues):,} eigenvalues")
    print(f"  ✓ Eigenvalue range: [{eigenvalues.min():.4f}, {eigenvalues.max():.4f}]")

    # Apply broken stick rule
    n_keep = broken_stick_rule(eigenvalues)

    # Extract top K eigenvectors
    eigenvectors_selected = eigenvectors[:, :n_keep]

    print(f"\n[5] Creating eigenvector DataFrame")
    print(f"  Selected eigenvectors: {n_keep}")
    print(f"  Matrix shape: {eigenvectors_selected.shape[0]:,} species × {eigenvectors_selected.shape[1]} eigenvectors")

    # Create DataFrame
    df_eigenvectors = pd.DataFrame(
        eigenvectors_selected,
        columns=[f'phylo_ev{i+1}' for i in range(n_keep)],
        index=species_ids
    )
    df_eigenvectors.index.name = 'wfo_taxon_id'

    # Summary statistics
    print(f"\n  Eigenvector summary:")
    print(f"    Mean abs value: {np.abs(eigenvectors_selected).mean():.6f}")
    print(f"    Std abs value:  {np.abs(eigenvectors_selected).std():.6f}")
    print(f"    Min value:      {eigenvectors_selected.min():.6f}")
    print(f"    Max value:      {eigenvectors_selected.max():.6f}")

    return df_eigenvectors


def map_eigenvectors_to_all_species(df_tree_eigenvectors, mapping_path):
    """
    Map eigenvectors from tree tips to all species (including infraspecific taxa).

    Infraspecific taxa inherit eigenvectors from their parent species.

    Args:
        df_tree_eigenvectors: DataFrame with eigenvectors for tree tips (wfo_taxon_id index)
        mapping_path: Path to WFO→tree mapping CSV

    Returns:
        df_all_eigenvectors: DataFrame with eigenvectors for ALL species
    """
    print(f"\n[6] Mapping eigenvectors to all species")
    print(f"  Mapping file: {mapping_path}")

    # Load mapping
    mapping = pd.read_csv(mapping_path)
    print(f"  ✓ Loaded mapping: {len(mapping):,} species")

    # Parse tree tip format: "wfo-XXXXXXX|Genus_species"
    # Extract WFO ID from tree tip labels
    def extract_wfo_from_tip(tip_label):
        if pd.isna(tip_label):
            return None
        return tip_label.split('|')[0] if '|' in tip_label else None

    mapping['tree_wfo_id'] = mapping['tree_tip'].apply(extract_wfo_from_tip)

    # Count mappings
    n_total = len(mapping)
    n_mapped = mapping['tree_wfo_id'].notna().sum()
    n_unmapped = n_total - n_mapped

    print(f"  Species with tree tips: {n_mapped:,} / {n_total:,} ({100*n_mapped/n_total:.1f}%)")
    print(f"  Species without tree: {n_unmapped}")

    # Merge eigenvectors
    df_all = mapping[['wfo_taxon_id', 'tree_wfo_id', 'is_infraspecific']].copy()

    # Join eigenvectors from tree tips
    df_all = df_all.merge(
        df_tree_eigenvectors,
        left_on='tree_wfo_id',
        right_index=True,
        how='left'
    )

    # Check coverage
    eigenvector_cols = [col for col in df_all.columns if col.startswith('phylo_ev')]
    n_with_eigenvectors = df_all[eigenvector_cols[0]].notna().sum()

    print(f"\n  ✓ Eigenvectors mapped to {n_with_eigenvectors:,} / {n_total:,} species ({100*n_with_eigenvectors/n_total:.1f}%)")

    # Show infraspecific inheritance
    infraspecific = df_all[df_all['is_infraspecific'] == True]
    n_infraspecific = len(infraspecific)
    n_infraspecific_mapped = infraspecific[eigenvector_cols[0]].notna().sum()

    print(f"  Infraspecific taxa: {n_infraspecific:,}")
    print(f"  Infraspecific inheriting eigenvectors: {n_infraspecific_mapped:,} ({100*n_infraspecific_mapped/n_infraspecific:.1f}%)")

    # Return DataFrame with wfo_taxon_id as index
    df_result = df_all.set_index('wfo_taxon_id')[eigenvector_cols]

    return df_result


def verify_eigenvectors(df_eigenvectors, expected_species=11680):
    """
    Verify eigenvector DataFrame integrity.

    Args:
        df_eigenvectors: DataFrame with eigenvector features
        expected_species: Expected number of species
    """
    print(f"\n[7] Verification")

    # Check species count
    n_species = len(df_eigenvectors)
    if n_species == expected_species:
        print(f"  ✓ Species count: {n_species:,} (expected: {expected_species:,})")
    else:
        print(f"  ⚠  Species count: {n_species:,} (expected: {expected_species:,})")

    # Check for missing values
    n_missing = df_eigenvectors.isna().sum().sum()
    n_rows_with_missing = df_eigenvectors.isna().any(axis=1).sum()
    coverage_pct = 100 * (n_species - n_rows_with_missing) / n_species

    if n_missing == 0:
        print(f"  ✓ No missing values")
    else:
        print(f"  ⚠  Missing values: {n_missing:,} total")
        print(f"  ⚠  Rows with missing: {n_rows_with_missing:,} / {n_species:,} ({100*n_rows_with_missing/n_species:.1f}%)")
        print(f"  ✓ Coverage: {coverage_pct:.1f}%")

    # Check for infinite values
    n_inf = np.isinf(df_eigenvectors.values).sum()
    if n_inf == 0:
        print(f"  ✓ No infinite values")
    else:
        print(f"  ✗ WARNING: {n_inf} infinite values found")

    # Check ID format
    sample_ids = df_eigenvectors.index[:5].tolist()
    all_wfo_format = all(str(id).startswith('wfo-') for id in sample_ids)
    if all_wfo_format:
        print(f"  ✓ IDs follow wfo- format")
    else:
        print(f"  ⚠  WARNING: Some IDs may not follow wfo- format")
        print(f"    Sample: {sample_ids}")


def main():
    parser = argparse.ArgumentParser(description="Extract phylogenetic eigenvectors from tree")
    parser.add_argument("--tree", required=True, help="Path to newick tree file")
    parser.add_argument("--mapping", required=False,
                        help="Path to WFO→tree mapping CSV (for subspecies inheritance)")
    parser.add_argument("--output", required=True, help="Output CSV path")
    parser.add_argument("--save_vcv", action="store_true",
                        help="Save VCV matrix (large file ~1GB)")
    args = parser.parse_args()

    print("=" * 80)
    print("PHYLOGENETIC EIGENVECTOR EXTRACTION")
    print("=" * 80)
    print(f"Tree: {args.tree}")
    if args.mapping:
        print(f"Mapping: {args.mapping}")
    print(f"Output: {args.output}")

    # Check tree file exists
    tree_path = Path(args.tree)
    if not tree_path.exists():
        print(f"\n✗ ERROR: Tree file not found: {tree_path}")
        sys.exit(1)

    print(f"  ✓ Tree file found ({tree_path.stat().st_size / 1024:.1f} KB)")

    # Check mapping file if provided
    if args.mapping:
        mapping_path = Path(args.mapping)
        if not mapping_path.exists():
            print(f"\n✗ ERROR: Mapping file not found: {mapping_path}")
            sys.exit(1)
        print(f"  ✓ Mapping file found ({mapping_path.stat().st_size / 1024:.1f} KB)")

    # Build VCV matrix
    vcv_output_path = None
    if args.save_vcv:
        tree_tip_count = args.tree.split('_')[2] if '_' in args.tree else '10977'
        vcv_output_path = Path(args.output).parent / f"phylo_vcv_matrix_{tree_tip_count}.csv"

    vcv_matrix, species_ids = load_tree_and_build_vcv(args.tree, vcv_output_path)

    # Extract eigenvectors for tree tips
    df_tree_eigenvectors = extract_eigenvectors(vcv_matrix, species_ids)

    # Map to all species if mapping provided
    if args.mapping:
        df_eigenvectors = map_eigenvectors_to_all_species(df_tree_eigenvectors, args.mapping)
    else:
        df_eigenvectors = df_tree_eigenvectors
        print(f"\n  ⚠  No mapping file provided - outputting tree tips only")

    # Verify
    expected_species = 11680 if args.mapping else len(species_ids)
    verify_eigenvectors(df_eigenvectors, expected_species=expected_species)

    # Save
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"\n[8] Saving eigenvector matrix")
    df_eigenvectors.to_csv(output_path)
    file_size_mb = output_path.stat().st_size / 1e6

    print(f"  ✓ Saved to: {output_path}")
    print(f"  ✓ File size: {file_size_mb:.2f} MB")
    print(f"  ✓ Dimensions: {df_eigenvectors.shape[0]:,} species × {df_eigenvectors.shape[1]} eigenvectors")

    print("\n" + "=" * 80)
    print("✓ EIGENVECTOR EXTRACTION COMPLETE")
    print("=" * 80)

    print("\nNext steps:")
    print("1. Build Perm8 dataset:")
    print("   conda run -n AI python src/Stage_1/build_xgboost_perm8_eigenvectors.py")
    print(f"\n2. Verify eigenvectors merged correctly")
    print(f"3. Run fast 3-fold CV to validate performance")


if __name__ == '__main__':
    main()
