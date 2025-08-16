#!/usr/bin/env python3
"""
Sort TRY "Trait List" export by AccSpecNum (descending) and, from the top-N,
flag traits likely relevant for predicting Ellenberg L (light preference).

Why: AccSpecNum (accepted species number) is a proxy for coverage — prioritizing
high-coverage traits improves model feasibility. Traits that capture leaf light
economy, plant architecture, or shade tolerance are plausible predictors of L.

Usage:
  python scripts/sort_try_traits.py \
    --input_txt "docs/TRY Traits.txt" \
    --output_sorted "docs/try_traits_sorted_by_accspecnum.tsv" \
    --output_top "docs/try_traits_top50.tsv" \
    --output_suggest "docs/try_traits_top50_L_candidates.tsv" \
    --top_n 50

Notes:
  - The input is a whitespace-aligned TXT from TRY Data Explorer.
  - Columns detected: TraitID, Trait, ObsNum, ObsGRNum, AccSpecNum.
  - We split on 2+ whitespace to preserve spaces inside Trait names.
  - Windows line endings (CRLF) and BOM are handled.
"""
from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from typing import Iterable, List, Tuple


HEADER_PATTERN = re.compile(r"^TraitID\s+Trait\s+ObsNum\s+ObsGRNum\s+AccSpecNum\s*$")
SPLIT_RE = re.compile(r"\s{2,}")  # split on 2+ whitespace, preserving spaces in Trait


@dataclass
class TraitRow:
    trait_id: int
    trait: str
    obs_num: int
    obs_gr_num: int
    acc_spec_num: int

    def to_tsv(self) -> str:
        return f"{self.trait_id}\t{self.trait}\t{self.obs_num}\t{self.obs_gr_num}\t{self.acc_spec_num}"


def read_lines(path: str) -> List[str]:
    with open(path, "rb") as f:
        raw = f.read()
    # Handle UTF-8 BOM and CRLF
    text = raw.decode("utf-8-sig", errors="replace").replace("\r\n", "\n")
    return text.splitlines()


def find_header_index(lines: Iterable[str]) -> int:
    for i, line in enumerate(lines):
        if HEADER_PATTERN.match(line.strip()):
            return i
    raise ValueError("Header line with expected columns not found.")


def parse_rows(lines: Iterable[str]) -> List[TraitRow]:
    rows: List[TraitRow] = []
    for ln in lines:
        s = ln.strip()
        if not s:
            continue
        parts = SPLIT_RE.split(s)
        if len(parts) < 5:
            # Skip non-data lines (e.g., section titles)
            continue
        try:
            trait_id = int(parts[0])
            trait = parts[1]
            obs_num = int(parts[2])
            obs_gr_num = int(parts[3])
            acc_spec_num = int(parts[4])
            rows.append(TraitRow(trait_id, trait, obs_num, obs_gr_num, acc_spec_num))
        except ValueError:
            # Skip lines that don't parse cleanly to expected numeric fields
            continue
    return rows


def write_tsv(path: str, rows: Iterable[TraitRow]) -> Tuple[int, int]:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    header = "TraitID\tTrait\tObsNum\tObsGRNum\tAccSpecNum\n"
    out_lines = [header] + [r.to_tsv() + "\n" for r in rows]
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out_lines)
    size = os.path.getsize(path)
    return len(out_lines) - 1, size


def suggest_L_predictors(rows: Iterable[TraitRow]) -> List[Tuple[TraitRow, str]]:
    """Heuristic filter for traits informative for light preference (L).

    Intuition: Prefer traits tied to light capture, shade tolerance, leaf economics,
    or plant architecture. Implemented via inclusive keyword rules plus a few
    disqualifiers. Returns (row, reason).
    """
    include_rules: List[Tuple[re.Pattern[str], str]] = [
        (re.compile(r"\b(specific leaf area|\bSLA\b|1/LMA|leaf area per leaf dry mass)", re.I),
         "Leaf economics: SLA"),
        (re.compile(r"\bLDMC|leaf dry matter content", re.I), "Leaf economics: LDMC"),
        (re.compile(r"leaf nitrogen|\bN\b content", re.I), "Leaf nitrogen"),
        (re.compile(r"leaf thickness", re.I), "Leaf thickness"),
        (re.compile(r"leaf (angle|orientation|inclination)", re.I), "Leaf angle/orientation"),
        (re.compile(r"leaf (area|length|width|shape|type)", re.I), "Leaf geometry/type"),
        (re.compile(r"leaf dry mass", re.I), "Leaf mass (structure)"),
        (re.compile(r"carbon.*per leaf (area|dry mass)|C/N ratio", re.I), "Leaf C, C/N (structure)"),
        (re.compile(r"photosynth(e)?sis pathway", re.I), "Photosynthesis pathway"),
        (re.compile(r"plant height", re.I), "Plant height (light environment)"),
        (re.compile(r"stem diameter|wood density|SSD", re.I), "Architecture/woodiness proxy"),
        (re.compile(r"woodiness|growth form|life form|functional type|phenology", re.I),
         "Syndrome: form/phenology"),
        (re.compile(r"mycorrhiza", re.I), "Forest affinity proxy"),
        (re.compile(r"seed dry mass", re.I), "Regeneration/shade tolerance proxy"),
    ]

    exclude_rules: List[re.Pattern[str]] = [
        re.compile(r"flower|fruit|dispersal|chromosome|genotype|ploidy|stamen", re.I),
        re.compile(r"fire|frost|climate", re.I),
    ]

    suggestions: List[Tuple[TraitRow, str]] = []
    for r in rows:
        name = r.trait
        if any(p.search(name) for p in exclude_rules):
            continue
        for p, reason in include_rules:
            if p.search(name):
                suggestions.append((r, reason))
                break
    return suggestions


def main() -> None:
    ap = argparse.ArgumentParser(description="Sort TRY traits by AccSpecNum and suggest L predictors.")
    ap.add_argument("--input_txt", required=True, help="Path to TRY Traits.txt (Trait List)")
    ap.add_argument("--output_sorted", required=True, help="Output TSV sorted by AccSpecNum desc")
    ap.add_argument("--output_top", required=True, help="Output TSV of top-N by AccSpecNum")
    ap.add_argument("--output_suggest", required=True, help="Output TSV of suggested L predictors from top-N")
    ap.add_argument("--top_n", type=int, default=50, help="How many top rows to consider (default: 50)")
    args = ap.parse_args()

    lines = read_lines(args.input_txt)
    header_idx = find_header_index(lines)
    rows = parse_rows(lines[header_idx + 1 :])
    if not rows:
        raise SystemExit("No data rows parsed — check input format.")

    rows_sorted = sorted(rows, key=lambda r: r.acc_spec_num, reverse=True)

    # Outputs
    n_all, size_all = write_tsv(args.output_sorted, rows_sorted)

    top_n = max(0, min(len(rows_sorted), args.top_n))
    top_rows = rows_sorted[:top_n]
    n_top, size_top = write_tsv(args.output_top, top_rows)

    suggestions = suggest_L_predictors(top_rows)
    if suggestions:
        # Write suggestions with reason
        os.makedirs(os.path.dirname(args.output_suggest) or ".", exist_ok=True)
        with open(args.output_suggest, "w", encoding="utf-8") as f:
            f.write("TraitID\tTrait\tAccSpecNum\tReason\n")
            for r, reason in suggestions:
                f.write(f"{r.trait_id}\t{r.trait}\t{r.acc_spec_num}\t{reason}\n")
        size_suggest = os.path.getsize(args.output_suggest)
        n_suggest = len(suggestions)
    else:
        size_suggest = 0
        n_suggest = 0

    # Print a concise manifest so the CLI user sees results without opening files
    print("Task complete.")
    print(f"Sorted: {args.output_sorted} (rows: {n_all}, bytes: {size_all})")
    print(f"Top-N:  {args.output_top} (rows: {n_top}, bytes: {size_top})")
    print(f"Suggest:{args.output_suggest} (rows: {n_suggest}, bytes: {size_suggest})")


if __name__ == "__main__":
    main()

