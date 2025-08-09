#!/usr/bin/env python3
import argparse
import csv
import os
import sys
import unicodedata
from typing import Iterable, List, Set


def normalize_name(name: str) -> str:
    if name is None:
        return ""
    s = str(name).strip()
    # Unify hybrid sign and odd chars
    s = s.replace("×", "x")
    # Unicode normalize and strip diacritics
    s = unicodedata.normalize("NFKD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    # Remove replacement char artifacts
    s = s.replace("�", "")
    # Collapse whitespace
    s = " ".join(s.split())
    return s.lower()


def load_taxa_set(eive_csv: str) -> Set[str]:
    taxa: Set[str] = set()
    with open(eive_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if "TaxonConcept" not in reader.fieldnames:
            raise SystemExit("TaxonConcept column not found in EIVE CSV")
        for row in reader:
            name = row.get("TaxonConcept", "")
            norm = normalize_name(name)
            if norm:
                taxa.add(norm)
    return taxa


def iter_matching_rows(path: str, taxa_norm: Set[str]) -> Iterable[List[str]]:
    # Stream a large TSV file and yield rows whose SpeciesName or AccSpeciesName matches
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
        header_line = f.readline()
        if not header_line:
            return
        # Split header; drop empty trailing column names
        header = [h.strip() for h in header_line.rstrip("\n\r").split("\t")]
        # Identify key columns
        try:
            idx_species = header.index("SpeciesName")
        except ValueError:
            idx_species = None
        try:
            idx_acc = header.index("AccSpeciesName")
        except ValueError:
            idx_acc = None

        if idx_species is None and idx_acc is None:
            raise SystemExit(f"No SpeciesName/AccSpeciesName in {path}")

        yield ("HEADER", header)

        for line in f:
            line = line.rstrip("\n\r")
            if not line:
                continue
            cols = line.split("\t")
            # Guard length mismatches by padding
            if len(cols) < len(header):
                cols += [""] * (len(header) - len(cols))
            sn = normalize_name(cols[idx_species]) if idx_species is not None else ""
            an = normalize_name(cols[idx_acc]) if idx_acc is not None else ""
            if sn in taxa_norm or an in taxa_norm:
                yield cols


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge trait rows for EIVE taxa from TRY extract TSVs")
    ap.add_argument("--eive_csv", default="data/EIVE_Paper_1.0_SM_08_csv/mainTable.csv")
    ap.add_argument("--sources", nargs="+", required=True, help="Paths to TRY extract .txt files (TSV)")
    ap.add_argument("--out", default="data/traits_for_eive_taxa.tsv")
    ap.add_argument("--append", action="store_true", help="Append to existing output (skip header)")
    args = ap.parse_args()

    taxa_norm = load_taxa_set(args.eive_csv)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    out_exists = os.path.exists(args.out)
    wrote_header = False
    with open(args.out, "a" if args.append else "w", encoding="utf-8", newline="\n") as out_f:
        writer = None
        for src in args.sources:
            src_label = os.path.basename(os.path.dirname(src)) or os.path.basename(src)
            count = 0
            header = None
            for row in iter_matching_rows(src, taxa_norm):
                if isinstance(row, tuple) and row[0] == "HEADER":
                    header = row[1]
                    # Prepare writer with Source column
                    if writer is None:
                        # Write header if not appending or file absent
                        if not args.append or not out_exists:
                            out_f.write("\t".join(header + ["Source"]) + "\n")
                            wrote_header = True
                        writer = out_f
                    continue
                # Write data row with Source tag
                out_f.write("\t".join(row + [src_label]) + "\n")
                count += 1
            print(f"Processed {src}: wrote {count} matching rows", file=sys.stderr)

    if not wrote_header and not out_exists and not args.append:
        print("Warning: no header written (no sources produced a header)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

