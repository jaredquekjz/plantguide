#!/usr/bin/env python3
"""Filter GBIF occurrences to Plantae and attach GBIF counts to union dataset.

GBIF Pipeline Step 2 of 3:
This script filters the sorted GBIF occurrences to Plantae kingdom only,
maps GBIF names to WFO (World Flora Online) taxonomic IDs, and attaches
occurrence counts to the Duke-EIVE union dataset for downstream analysis.

Data Flow:
Input 1: occurrence_sorted.parquet (129.85M rows, all kingdoms)
Input 2: classification.csv (WFO taxonomic backbone, ~1.5M species)
Input 3: duke_eive_wfo_union.csv (union dataset needing GBIF counts)
Output 1: occurrence_plantae.parquet (49.67M rows, Plantae only)
Output 2: duke_eive_wfo_union.csv/parquet (union + GBIF counts)
Output 3: gbif_wfo_unmatched.csv (species without GBIF matches)

Processing Steps:
1. Build WFO canonical name → accepted ID mapping
2. Filter GBIF to Plantae kingdom (38% reduction: 129.85M → 49.67M)
3. Canonicalize GBIF names and aggregate by WFO IDs
4. Attach GBIF counts to union dataset via WFO ID matching
5. Report match statistics and write unmatched species list

Performance:
- Execution time: ~20-30 minutes
- Peak memory: ~64GB
- DuckDB threads: 28 cores
"""

from __future__ import annotations

import math
import re
import sys
import unicodedata
from pathlib import Path
from typing import Dict, Iterable, Optional, Tuple

import duckdb
import pandas as pd

# ================================================================================
# Path Configuration
# ================================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]
PARQUET_PATH = REPO_ROOT / "data" / "gbif" / "occurrence_sorted.parquet"
PLANT_PARQUET_PATH = REPO_ROOT / "data" / "gbif" / "occurrence_plantae.parquet"
UNION_CSV_PATH = REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union.csv"
UNION_PARQUET_PATH = REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union.parquet"
CLASSIFICATION_PATH = REPO_ROOT / "data" / "classification.csv"
UNMATCHED_OUTPUT_PATH = REPO_ROOT / "data" / "analysis" / "gbif_wfo_unmatched.csv"


def canonicalize(raw: Optional[str]) -> Optional[str]:
    """Normalize plant scientific names to canonical form for matching.

    This function implements a rigorous canonicalization algorithm to reconcile
    name variations across GBIF, WFO, Duke, and EIVE datasets:

    Normalization Rules:
    1. Unicode: NFKD normalization + strip diacritics (é → e)
    2. Hybrids: × symbol → " x " with spaces
    3. Authorities: Remove parenthetical author names (L.) Sm. → remove
    4. Punctuation: Remove non-alphanumeric chars (hyphens, underscores)
    5. Case: Lowercase for case-insensitive matching
    6. Ranks: Standardize infraspecific ranks (ssp, var, f)
    7. Tokens: Limit to 4 tokens (genus, species, rank, epithet)
    8. Trailing ranks: Remove orphaned rank markers

    Examples:
    - "Quercus robur L." → "quercus robur"
    - "Pinus sylvestris subsp. nevadensis" → "pinus sylvestris subsp nevadensis"
    - "Achillea millefolium var. millefolium" → "achillea millefolium var millefolium"
    - "Arabis × arendsii" → "arabis x arendsii"

    Returns:
    - Canonical name string (lowercase, space-separated)
    - None if input is empty or cannot be canonicalized
    """
    # ================================================================================
    # STEP 1: Input Validation and Trimming
    # ================================================================================
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None

    # ================================================================================
    # STEP 2: Unicode Normalization (NFKD) and Diacritic Removal
    # ================================================================================
    # Decompose combined characters (é → e + ´) then strip combining marks
    # This handles accented characters in author names and geographic epithets
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.category(ch).startswith("M"))

    # ================================================================================
    # STEP 3: Character Normalization
    # ================================================================================
    # Standardize hybrid notation (botanical × vs ASCII x)
    text = text.replace("×", " x ")

    # Remove parenthetical author names: "(L.) DC." → ""
    text = re.sub(r"\([^)]*\)", " ", text)

    # Normalize word separators (underscores, hyphens → spaces)
    text = text.replace("_", " ").replace("-", " ")

    # Remove all non-alphanumeric characters except spaces and periods
    text = re.sub(r"[^A-Za-z0-9\s\.]", " ", text)

    # Collapse multiple spaces and convert to lowercase
    text = re.sub(r"\s+", " ", text).strip().lower()
    if not text:
        return None

    # ================================================================================
    # STEP 4: Token Processing and Infraspecific Rank Standardization
    # ================================================================================
    # Recognized infraspecific rank markers (standardize to consistent forms)
    rank_tokens = {
        "subsp",
        "subspecies",
        "ssp",
        "var",
        "variety",
        "f",
        "forma",
        "subvar",
        "subvariety",
        "subform",
        "cv",
        "cultivar",
    }

    normalised: list[str] = []
    for token in text.split():
        # Remove trailing periods (abbreviations)
        token = token.rstrip(".")
        if not token:
            continue

        # Standardize subspecies abbreviations
        if token in rank_tokens:
            normalised.append("subsp" if token in {"subspecies", "ssp"} else token)
            continue

        # Preserve hybrid marker "x"
        if token == "x":
            normalised.append(token)
            continue

        # Stop at cultivar numbers or accession codes
        if any(ch.isdigit() for ch in token):
            break

        # Skip single-character tokens (initials)
        if len(token) <= 1:
            continue

        # Stop at abbreviated tokens (likely author initials)
        if token.endswith("."):
            break

        normalised.append(token)

        # Limit to 4 tokens: genus + species + rank + epithet
        if len(normalised) >= 4:
            break

    # ================================================================================
    # STEP 5: Trailing Rank Cleanup
    # ================================================================================
    # Remove orphaned rank markers at end (e.g., "quercus robur var" → "quercus robur")
    if len(normalised) >= 2 and normalised[-1] in rank_tokens:
        normalised = normalised[:-1]

    if not normalised:
        return None

    return " ".join(normalised)


def build_wfo_maps() -> Tuple[Dict[str, str], Dict[str, str]]:
    """Build bidirectional WFO name ↔ ID mappings for GBIF name resolution.

    WFO (World Flora Online) provides the taxonomic backbone for resolving:
    - Synonyms → accepted names (e.g., "Chrysanthemum" → "Glebionis")
    - Name variations → stable IDs (e.g., spelling variants, authorities)

    Returns:
    Tuple of two dictionaries:
    1. canonical_to_accepted: canonical name → accepted WFO ID
       Maps all name variants (accepted + synonyms) to their accepted WFO ID
    2. accepted_to_canonical: accepted WFO ID → canonical name
       Maps accepted IDs back to their canonical name form
    """
    print("[1/5] Loading WFO classification")

    # ================================================================================
    # STEP 1: Load WFO Classification (Tab-Delimited, ~1.5M Taxa)
    # ================================================================================
    # Latin-1 encoding required for botanical author names with accents
    # keep_default_na=False prevents "NA" (Namibia country code) from becoming NaN
    wfo_df = pd.read_csv(
        CLASSIFICATION_PATH,
        sep="\t",
        dtype=str,
        encoding="latin-1",
        keep_default_na=False,
        na_values=[],
    )

    # ================================================================================
    # STEP 2: Canonicalize WFO Scientific Names
    # ================================================================================
    # Apply same canonicalization used for GBIF names
    # This creates consistent lookup keys across both datasets
    wfo_df["scientificName"] = wfo_df["scientificName"].str.strip().replace(
        {"": pd.NA}
    )
    wfo_df = wfo_df.dropna(subset=["scientificName"])
    wfo_df["canonical_name"] = wfo_df["scientificName"].apply(canonicalize)
    wfo_df["canonical_name"] = wfo_df["canonical_name"].replace({None: pd.NA})

    # ================================================================================
    # STEP 3: Build Bidirectional Name-ID Mappings
    # ================================================================================
    canonical_to_accepted: Dict[str, str] = {}
    accepted_to_canonical: Dict[str, str] = {}

    for _, row in wfo_df.iterrows():
        canon = row["canonical_name"]
        if not isinstance(canon, str) or not canon:
            continue

        taxon_id = row.get("taxonID", "")
        accepted_id = row.get("acceptedNameUsageID", "")
        status = (row.get("taxonomicStatus") or "").lower()

        # Determine accepted ID for this taxon
        # If taxonomic status is "accepted" or no synonym link exists, use own ID
        if status == "accepted" or not accepted_id:
            accepted_id = taxon_id

        # Map canonical name to its accepted WFO ID (first occurrence wins)
        if accepted_id:
            canonical_to_accepted.setdefault(canon, accepted_id)

        # Map accepted WFO ID back to its canonical name (accepted names only)
        if status == "accepted" and accepted_id and canon:
            accepted_to_canonical.setdefault(accepted_id, canon)

    print(
        f"[1/5] WFO maps ready: {len(accepted_to_canonical):,} accepted concepts, "
        f"{len(canonical_to_accepted):,} canonical name aliases"
    )
    return canonical_to_accepted, accepted_to_canonical


def build_gbif_counts(con: duckdb.DuckDBPyConnection) -> Tuple[pd.DataFrame, Dict[str, int]]:
    """Filter GBIF to Plantae, canonicalize names, and aggregate by WFO IDs.

    This function implements the core GBIF processing pipeline:
    1. Filter 129.85M GBIF occurrences to 49.67M Plantae records
    2. Construct scientific names from GBIF Darwin Core fields
    3. Canonicalize names for matching with WFO
    4. Aggregate occurrence counts by canonical name
    5. Map canonical names to accepted WFO IDs
    6. Sum counts by WFO ID (handles synonyms)

    Returns:
    Tuple containing:
    1. DataFrame: WFO ID → occurrence count (aggregated by accepted names)
    2. Dict: canonical name → occurrence count (for fallback matching)
    """
    if not PARQUET_PATH.exists():
        raise FileNotFoundError(f"GBIF parquet not found: {PARQUET_PATH}")

    canonical_to_accepted, accepted_to_canonical = build_wfo_maps()

    # ================================================================================
    # STEP 1: Materialize Plantae-Only Parquet (If Not Exists)
    # ================================================================================
    # Filter 129.85M total occurrences → 49.67M Plantae occurrences
    # This reduces downstream processing by 62% and enables faster lookups
    # Uses parameterized query (SECURE - no SQL injection risk)
    if not PLANT_PARQUET_PATH.exists():
        print("[2/5] Materialising Plantae-only GBIF parquet")
        con.execute(
            """
            COPY (
                SELECT *
                FROM read_parquet(?)
                WHERE kingdom = 'Plantae'
            )
            TO ?
            (FORMAT PARQUET, COMPRESSION ZSTD)
            """,
            [str(PARQUET_PATH), str(PLANT_PARQUET_PATH)],
        )

    # ================================================================================
    # STEP 2: Configure DuckDB and Register Canonicalize UDF
    # ================================================================================
    print("[2/5] Aggregating GBIF occurrences via DuckDB")
    con.execute("PRAGMA threads=28")
    con.execute("PRAGMA memory_limit='64GB'")

    # Register Python canonicalize() function as DuckDB UDF
    # null_handling="special" allows function to handle NULL inputs
    con.create_function("canonicalize", canonicalize, null_handling="special")

    # ================================================================================
    # STEP 3: Construct Scientific Names from Darwin Core Fields
    # ================================================================================
    # GBIF Darwin Core provides multiple name fields with hierarchical priority:
    # 1. For infraspecific ranks (subspecies, varieties, forms):
    #    genus + specificEpithet + rank abbreviation + infraspecificEpithet
    #    Example: "Quercus" + "robur" + "var." + "pedunculata" → "Quercus robur var. pedunculata"
    #
    # 2. For species (most common):
    #    Use pre-constructed "species" field OR genus + specificEpithet
    #
    # 3. Fallback to scientificName (includes authorities, may be less clean)
    #
    # Then canonicalize each constructed name using our UDF and aggregate counts
    gbif_counts_df = con.execute(
        """
        SELECT
            canonicalize(raw_name) AS canonical_name,
            COUNT(*) AS record_count
        FROM (
            SELECT
                CASE
                    -- Priority 1: Infraspecific taxa (subspecies, varieties, forms)
                    -- Construct: genus + species + rank + infraspecific epithet
                    WHEN LOWER(taxonRank) IN (
                        'subspecies','infraspecies','variety',
                        'form','subvariety','subform','cultivar'
                    )
                     AND genus IS NOT NULL
                     AND specificEpithet IS NOT NULL
                     AND infraspecificEpithet IS NOT NULL THEN
                        genus || ' ' || specificEpithet || ' ' ||
                        CASE LOWER(taxonRank)
                            WHEN 'subspecies' THEN 'subsp.'
                            WHEN 'infraspecies' THEN 'subsp.'
                            WHEN 'variety' THEN 'var.'
                            WHEN 'subvariety' THEN 'subvar.'
                            WHEN 'form' THEN 'f.'
                            WHEN 'subform' THEN 'subf.'
                            WHEN 'cultivar' THEN 'cv.'
                            ELSE LOWER(taxonRank)
                        END || ' ' || infraspecificEpithet

                    -- Priority 2: Species (use pre-constructed field if available)
                    WHEN species IS NOT NULL AND species <> '' THEN species

                    -- Priority 3: Construct binomial from genus + specificEpithet
                    WHEN genus IS NOT NULL AND specificEpithet IS NOT NULL THEN
                        genus || ' ' || specificEpithet

                    -- Priority 4: Fallback to scientificName (may include authorities)
                    WHEN scientificName IS NOT NULL AND scientificName <> '' THEN
                        scientificName

                    ELSE NULL
                END AS raw_name
            FROM read_parquet(?)
        )
        WHERE raw_name IS NOT NULL
        GROUP BY canonical_name
        """,
        [str(PLANT_PARQUET_PATH)],
    ).fetchdf()

    # ================================================================================
    # STEP 4: Clean and Type-Convert Aggregated Counts
    # ================================================================================
    gbif_counts_df = gbif_counts_df.dropna(subset=["canonical_name"])
    gbif_counts_df["record_count"] = gbif_counts_df["record_count"].astype("int64")

    # ================================================================================
    # STEP 5: Map Canonical Names to Accepted WFO IDs
    # ================================================================================
    # This step resolves synonyms: multiple GBIF canonical names may map to
    # the same accepted WFO ID, requiring aggregation by WFO ID
    gbif_counts_df["accepted_wfo_id"] = gbif_counts_df["canonical_name"].map(
        canonical_to_accepted
    )

    # ================================================================================
    # STEP 6: Aggregate by Accepted WFO ID (Handle Synonyms)
    # ================================================================================
    # Sum occurrence counts for all names pointing to the same accepted WFO ID
    # Example: "Chrysanthemum segetum" + "Glebionis segetum" → both map to WFO ID
    # for accepted name "Glebionis segetum", counts are summed
    gbif_counts_by_wfo = (
        gbif_counts_df.dropna(subset=["accepted_wfo_id"])
        .groupby("accepted_wfo_id", as_index=False)["record_count"]
        .sum()
    )

    # ================================================================================
    # STEP 7: Create Canonical Name Lookup (Fallback for Unmatched WFO IDs)
    # ================================================================================
    # Keep dictionary of canonical name → count for species that don't have
    # WFO IDs in the union dataset (e.g., newly described species)
    gbif_canonical_lookup: Dict[str, int] = dict(
        zip(gbif_counts_df["canonical_name"], gbif_counts_df["record_count"])
    )

    print(
        f"[2/5] GBIF canonical rows: {len(gbif_counts_df):,}; "
        f"accepted WFO matches: {len(gbif_counts_by_wfo):,}"
    )
    return gbif_counts_by_wfo, gbif_canonical_lookup


def calc_gbif_counts_for_union(
    union_df: pd.DataFrame,
    gbif_by_wfo: Dict[str, int],
    gbif_by_canonical: Dict[str, int],
) -> pd.DataFrame:
    """Attach GBIF counts to the union dataframe."""

    def wfo_ids_iter(value: Optional[str]) -> Iterable[str]:
        if value is None or (isinstance(value, float) and math.isnan(value)):
            return []
        text = str(value).strip()
        if not text:
            return []
        for part in text.split(";"):
            part = part.strip()
            if part:
                yield part

    def row_count(row: pd.Series) -> int:
        total = 0
        ids = list(wfo_ids_iter(row.get("wfo_ids")))
        if ids:
            totals = [gbif_by_wfo.get(wfo_id, 0) for wfo_id in ids]
            total = sum(totals)
        if total == 0:
            candidates = set()
            candidates.add(canonicalize(row.get("accepted_norm")))
            candidates.add(canonicalize(row.get("accepted_name")))
            for cand in candidates:
                if cand and cand in gbif_by_canonical:
                    total += gbif_by_canonical[cand]
        return int(total)

    gbif_by_wfo = {k.strip(): v for k, v in gbif_by_wfo.items() if isinstance(k, str)}

    union_df = union_df.copy()
    union_df["gbif_record_count"] = union_df.apply(row_count, axis=1)
    union_df["gbif_has_data"] = union_df["gbif_record_count"] > 0
    return union_df


def main() -> int:
    if not UNION_CSV_PATH.exists():
        raise FileNotFoundError(f"Union CSV not found: {UNION_CSV_PATH}")

    con = duckdb.connect()
    gbif_counts_by_wfo_df, gbif_canonical_lookup = build_gbif_counts(con)
    con.close()

    gbif_by_wfo = dict(
        zip(gbif_counts_by_wfo_df["accepted_wfo_id"], gbif_counts_by_wfo_df["record_count"])
    )

    print("[3/5] Loading union dataset")
    union_df = pd.read_csv(UNION_CSV_PATH, low_memory=False)

    print("[4/5] Attaching GBIF counts")
    enriched_union = calc_gbif_counts_for_union(
        union_df,
        gbif_by_wfo,
        gbif_canonical_lookup,
    )

    unmatched_df = enriched_union.loc[
        enriched_union["gbif_record_count"] == 0,
        ["accepted_norm", "accepted_name", "wfo_ids"],
    ].sort_values("accepted_norm")

    print("[5/5] Writing refreshed outputs")
    enriched_union.to_csv(UNION_CSV_PATH, index=False)
    enriched_union.to_parquet(UNION_PARQUET_PATH, index=False)
    unmatched_df.to_csv(UNMATCHED_OUTPUT_PATH, index=False)

    matched = int((enriched_union["gbif_record_count"] > 0).sum())
    total = len(enriched_union)
    unmatched = total - matched
    print(
        f"Completed: matched {matched:,} taxa, {unmatched:,} unmatched "
        f"(see {UNMATCHED_OUTPUT_PATH})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
