#!/usr/bin/env python3
"""
Convert an Excel workbook (.xlsx) sheet to CSV.

Arcane formula (CLI):
  python src/Stage_1_Data_Extraction/convert_excel_to_csv.py \
    --input_xlsx data/EIVE_Paper_1.0_SM_08.xlsx \
    --sheet mainTable \
    --output_csv data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv

Notes:
  - Defaults to sheet 'mainTable' if present, otherwise the first sheet.
  - Writes UTF-8 CSV with header, comma delimiter.
  - Creates parent directories for the output path.
"""

import argparse
import os
import sys
from pathlib import Path

import pandas as pd


def main() -> int:
    ap = argparse.ArgumentParser(description="Convert an Excel sheet to CSV (UTF-8)")
    ap.add_argument("--input_xlsx", required=True, help="Path to the .xlsx file")
    ap.add_argument("--sheet", default="mainTable", help="Sheet name or index; default 'mainTable'")
    ap.add_argument("--output_csv", required=True, help="Path to the output .csv")
    args = ap.parse_args()

    # Hygiene: normalize paths and validate inputs
    in_xlsx = Path(args.input_xlsx).resolve()
    out_csv = Path(args.output_csv)
    sheet = args.sheet

    if not in_xlsx.exists():
        print(f"[error] Input Excel not found: '{in_xlsx}'", file=sys.stderr)
        return 2

    # Determine sheet to use
    try:
        # Read only the sheet names first to choose deterministically
        with pd.ExcelFile(in_xlsx, engine="openpyxl") as xf:
            sheet_names = list(xf.sheet_names)
    except Exception as e:
        print(f"[error] Failed to read workbook: {e}", file=sys.stderr)
        return 3

    chosen_sheet: str
    if sheet.isdigit():
        idx = int(sheet)
        if idx < 0 or idx >= len(sheet_names):
            print(f"[error] Sheet index out of range: {idx} (available: 0..{len(sheet_names)-1})", file=sys.stderr)
            return 4
        chosen_sheet = sheet_names[idx]
    else:
        if sheet in sheet_names:
            chosen_sheet = sheet
        elif "mainTable" in sheet_names:
            chosen_sheet = "mainTable"
            print(f"[warn] Requested sheet '{sheet}' not found; using 'mainTable'", file=sys.stderr)
        else:
            chosen_sheet = sheet_names[0]
            print(f"[warn] Requested sheet '{sheet}' not found; falling back to first sheet '{chosen_sheet}'", file=sys.stderr)

    # Ensure output directory exists
    out_csv.parent.mkdir(parents=True, exist_ok=True)

    # Read and write
    print("Parameters:")
    print(f"  input_xlsx = {in_xlsx}")
    print(f"  sheet      = {chosen_sheet}")
    print(f"  output_csv = {out_csv}")

    try:
        df = pd.read_excel(in_xlsx, sheet_name=chosen_sheet, engine="openpyxl")
    except Exception as e:
        print(f"[error] Failed reading sheet '{chosen_sheet}': {e}", file=sys.stderr)
        return 5

    try:
        # Write UTF-8 CSV without index, keep NA as empty
        df.to_csv(out_csv, index=False)
    except Exception as e:
        print(f"[error] Failed writing CSV '{out_csv}': {e}", file=sys.stderr)
        return 6

    # Report size and rows
    try:
        size = out_csv.stat().st_size
    except Exception:
        size = -1
    print(f"Done: wrote '{out_csv}' (size={size} bytes, rows={len(df)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

