#!/usr/bin/env python3
"""
Verify checksum parity between Python and R guild scorer outputs.

Purpose: Gold standard verification for frontend implementations
"""

import hashlib
import pandas as pd
from pathlib import Path
import sys

def calculate_checksums(csv_path):
    """Calculate MD5 and SHA256 checksums for CSV file."""
    with open(csv_path, 'rb') as f:
        content = f.read()

    md5 = hashlib.md5(content).hexdigest()
    sha256 = hashlib.sha256(content).hexdigest()

    return md5, sha256

def compare_csv_files(python_path, r_path):
    """Compare two CSV files column by column."""

    print("\nLoading CSV files...")
    df_python = pd.read_csv(python_path)
    df_r = pd.read_csv(r_path)

    print(f"  Python: {len(df_python)} rows, {len(df_python.columns)} columns")
    print(f"  R:      {len(df_r)} rows, {len(df_r.columns)} columns")

    # Check row count
    if len(df_python) != len(df_r):
        print(f"\n❌ Row count mismatch: {len(df_python)} vs {len(df_r)}")
        return False

    # Check column names
    if list(df_python.columns) != list(df_r.columns):
        print("\n❌ Column names mismatch")
        python_cols = set(df_python.columns)
        r_cols = set(df_r.columns)
        print(f"  Only in Python: {python_cols - r_cols}")
        print(f"  Only in R: {r_cols - python_cols}")
        return False

    # Compare row by row
    differences = []
    tolerance = 1e-6  # Floating point tolerance

    for idx in range(len(df_python)):
        python_row = df_python.iloc[idx]
        r_row = df_r.iloc[idx]
        guild_id = python_row['guild_id']

        for col in df_python.columns:
            python_val = python_row[col]
            r_val = r_row[col]

            # Handle NaN comparison
            if pd.isna(python_val) and pd.isna(r_val):
                continue

            # Numeric comparison with tolerance
            if isinstance(python_val, (int, float)) and isinstance(r_val, (int, float)):
                if abs(python_val - r_val) > tolerance:
                    differences.append({
                        'guild_id': guild_id,
                        'column': col,
                        'python_value': python_val,
                        'r_value': r_val,
                        'diff': abs(python_val - r_val)
                    })
            # String comparison
            elif python_val != r_val:
                differences.append({
                    'guild_id': guild_id,
                    'column': col,
                    'python_value': python_val,
                    'r_value': r_val,
                    'diff': 'string_mismatch'
                })

    if differences:
        print(f"\n⚠ Found {len(differences)} differences:")
        for diff in differences[:20]:  # Show first 20
            if diff['diff'] == 'string_mismatch':
                print(f"  {diff['guild_id']}.{diff['column']}: '{diff['python_value']}' vs '{diff['r_value']}'")
            else:
                print(f"  {diff['guild_id']}.{diff['column']}: {diff['python_value']} vs {diff['r_value']} (diff: {diff['diff']:.9f})")
        if len(differences) > 20:
            print(f"  ... and {len(differences) - 20} more")

        # Categorize differences
        numeric_diffs = [d for d in differences if d['diff'] != 'string_mismatch']
        string_diffs = [d for d in differences if d['diff'] == 'string_mismatch']

        if numeric_diffs:
            print(f"\n  Numeric differences: {len(numeric_diffs)}")
            max_diff = max(d['diff'] for d in numeric_diffs)
            print(f"  Maximum numeric difference: {max_diff:.9f}")

        if string_diffs:
            print(f"  String differences: {len(string_diffs)}")

        return False

    return True

def verify_frontend_parity():
    """Main verification function."""

    python_path = Path('shipley_checks/stage4/guild_scores_python.csv')
    r_path = Path('shipley_checks/stage4/guild_scores_r.csv')

    print("=" * 70)
    print("Frontend Scorer Parity Verification")
    print("=" * 70)

    # Check files exist
    if not python_path.exists():
        print(f"\n❌ Python output not found: {python_path}")
        return False

    if not r_path.exists():
        print(f"\n❌ R output not found: {r_path}")
        return False

    print(f"\n✓ Both output files exist")

    # Calculate checksums
    print("\nCalculating checksums...")
    python_md5, python_sha256 = calculate_checksums(python_path)
    r_md5, r_sha256 = calculate_checksums(r_path)

    print(f"\nPython CSV:")
    print(f"  MD5:    {python_md5}")
    print(f"  SHA256: {python_sha256}")

    print(f"\nR CSV:")
    print(f"  MD5:    {r_md5}")
    print(f"  SHA256: {r_sha256}")

    # Compare checksums
    if python_md5 == r_md5 and python_sha256 == r_sha256:
        print("\n" + "=" * 70)
        print("✅ PERFECT CHECKSUM PARITY")
        print("=" * 70)
        print("Python and R produce byte-for-byte identical CSV outputs.")
        print("Gold standard verified for Rust implementation.")
        return True
    else:
        print("\n⚠ Checksums differ - performing detailed comparison...")

        # Detailed comparison
        if compare_csv_files(python_path, r_path):
            print("\n" + "=" * 70)
            print("✅ LOGICAL PARITY (values match, formatting may differ)")
            print("=" * 70)
            print("Python and R produce identical numerical results.")
            print("Minor differences in string formatting acceptable.")
            return True
        else:
            print("\n" + "=" * 70)
            print("❌ VERIFICATION FAILED")
            print("=" * 70)
            print("Python and R produce different results.")
            print("Review differences above and debug scorer implementations.")
            return False

if __name__ == '__main__':
    success = verify_frontend_parity()
    sys.exit(0 if success else 1)
