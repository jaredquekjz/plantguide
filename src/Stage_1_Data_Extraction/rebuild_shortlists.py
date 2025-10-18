#!/usr/bin/env python3
"""Rebuild Stage 1 shortlist artefacts using accepted WFO identifiers.

This script regenerates:
    - stage1_shortlist_candidates.(parquet/csv)
    - stage1_shortlist_with_gbif.(parquet/csv)
    - stage1_shortlist_with_gbif_ge30.(parquet/csv)
    - stage1_modelling_shortlist.(parquet/csv)
    - stage1_modelling_shortlist_with_gbif.(parquet/csv)
    - stage1_modelling_shortlist_with_gbif_ge30.(parquet/csv)

Counts are recomputed after the WFO matching update so that every artefact
uses the accepted WFO identifier. GBIF occurrence totals are now derived
directly from the WFO ID instead of a lowercase canonical name string.
"""

from __future__ import annotations

from pathlib import Path

import duckdb


ROOT = Path("/home/olier/ellenberg")
STAGE1_DIR = ROOT / "data" / "stage1"

EIVE_PATH = STAGE1_DIR / "eive_worldflora_enriched.parquet"
TRY_ENH_PATH = STAGE1_DIR / "tryenhanced_worldflora_enriched.parquet"
TRY_RAW_PATH = STAGE1_DIR / "try_selected_traits_worldflora_enriched.parquet"
DUKE_PATH = STAGE1_DIR / "duke_worldflora_enriched.parquet"
AUSTRAITS_TAXA_PATH = STAGE1_DIR / "austraits" / "austraits_taxa_worldflora_enriched.parquet"
AUSTRAITS_TRAIT_PATH = STAGE1_DIR / "austraits" / "traits_try_overlap.parquet"
GBIF_OCC_PATH = ROOT / "data" / "gbif" / "occurrence_plantae_wfo.parquet"
GBIF_COUNTS_WFO_PARQUET = STAGE1_DIR / "gbif_occurrence_counts_by_wfo.parquet"
GBIF_COUNTS_WFO_CSV = STAGE1_DIR / "gbif_occurrence_counts_by_wfo.csv"

SHORTLIST_PARQUET = STAGE1_DIR / "stage1_shortlist_candidates.parquet"
SHORTLIST_CSV = STAGE1_DIR / "stage1_shortlist_candidates.csv"
SHORTLIST_GBIF_PARQUET = STAGE1_DIR / "stage1_shortlist_with_gbif.parquet"
SHORTLIST_GBIF_CSV = STAGE1_DIR / "stage1_shortlist_with_gbif.csv"
SHORTLIST_GBIF_GE30_PARQUET = STAGE1_DIR / "stage1_shortlist_with_gbif_ge30.parquet"
SHORTLIST_GBIF_GE30_CSV = STAGE1_DIR / "stage1_shortlist_with_gbif_ge30.csv"

MODELLING_PARQUET = STAGE1_DIR / "stage1_modelling_shortlist.parquet"
MODELLING_CSV = STAGE1_DIR / "stage1_modelling_shortlist.csv"
MODELLING_GBIF_PARQUET = STAGE1_DIR / "stage1_modelling_shortlist_with_gbif.parquet"
MODELLING_GBIF_CSV = STAGE1_DIR / "stage1_modelling_shortlist_with_gbif.csv"
MODELLING_GBIF_GE30_PARQUET = STAGE1_DIR / "stage1_modelling_shortlist_with_gbif_ge30.parquet"
MODELLING_GBIF_GE30_CSV = STAGE1_DIR / "stage1_modelling_shortlist_with_gbif_ge30.csv"


def rebuild_shortlist(con: duckdb.DuckDBPyConnection) -> None:
    """Rebuild the trait shortlist and attach GBIF counts."""

    con.execute("PRAGMA threads=8;")

    # --- Trait coverage -------------------------------------------------
    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE eive_counts AS
        SELECT
            wfo_taxon_id,
            MAX(
                (CASE WHEN TRY_CAST("EIVEres-M" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("EIVEres-N" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("EIVEres-R" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("EIVEres-L" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("EIVEres-T" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END)
            ) AS eive_numeric_count
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
        GROUP BY wfo_taxon_id
        """,
        (str(EIVE_PATH),),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE try_enhanced_counts AS
        SELECT
            wfo_taxon_id,
            MAX(
                (CASE WHEN TRY_CAST("Leaf area (mm2)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("Nmass (mg/g)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("LMA (g/m2)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("Plant height (m)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("Diaspore mass (mg)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("SSD observed (mg/mm3)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("SSD imputed (mg/mm3)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("SSD combined (mg/mm3)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) +
                (CASE WHEN TRY_CAST("LDMC (g/g)" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END)
            ) AS try_numeric_count
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
        GROUP BY wfo_taxon_id
        """,
        (str(TRY_ENH_PATH),),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE austraits_enriched AS
        SELECT
            taxa.wfo_taxon_id,
            taxa.wfo_scientific_name,
            traits.trait_name,
            traits.value
        FROM read_parquet(?) AS traits
        JOIN read_parquet(?) AS taxa
          ON lower(trim(traits.taxon_name)) = lower(trim(taxa.taxon_name))
        WHERE taxa.wfo_taxon_id IS NOT NULL AND trim(taxa.wfo_taxon_id) <> ''
          AND traits.trait_name IN ('leaf_area','leaf_N_per_dry_mass','leaf_mass_per_area',
                                    'plant_height','diaspore_dry_mass','wood_density',
                                    'leaf_dry_matter_content','leaf_thickness')
        """,
        (str(AUSTRAITS_TRAIT_PATH), str(AUSTRAITS_TAXA_PATH)),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE austraits_counts AS
        SELECT
            wfo_taxon_id,
            COUNT(DISTINCT CASE
                WHEN TRY_CAST(trim(value) AS DOUBLE) IS NOT NULL THEN trait_name
            END) AS austraits_numeric_count
        FROM austraits_enriched
        GROUP BY wfo_taxon_id
        """
    )

    # --- Presence flags & legacy identifiers ---------------------------
    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE presence AS
        SELECT
            wfo_taxon_id,
            MIN(canonical_name) AS canonical_name,
            STRING_AGG(DISTINCT legacy_wfo, ',') FILTER (WHERE legacy_wfo IS NOT NULL) AS legacy_wfo_ids,
            MAX(CASE WHEN source = 'eive' THEN 1 ELSE 0 END) AS in_eive,
            MAX(CASE WHEN source = 'try_enhanced' THEN 1 ELSE 0 END) AS in_try_enhanced,
            MAX(CASE WHEN source = 'duke' THEN 1 ELSE 0 END) AS in_duke,
            MAX(CASE WHEN source = 'austraits' THEN 1 ELSE 0 END) AS in_austraits
        FROM (
            SELECT
                wfo_taxon_id,
                COALESCE(wfo_scientific_name, TaxonConcept) AS canonical_name,
                COALESCE(NULLIF(trim(wfo_original_id), ''), wfo_taxon_id) AS legacy_wfo,
                'eive' AS source
            FROM read_parquet(?)
            WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
            UNION ALL
            SELECT
                wfo_taxon_id,
                COALESCE(wfo_scientific_name, "Species name standardized against TPL") AS canonical_name,
                COALESCE(NULLIF(trim(wfo_original_id), ''), wfo_taxon_id) AS legacy_wfo,
                'try_enhanced' AS source
            FROM read_parquet(?)
            WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
            UNION ALL
            SELECT
                wfo_taxon_id,
                COALESCE(wfo_scientific_name, scientific_name) AS canonical_name,
                COALESCE(NULLIF(trim(wfo_original_id), ''), wfo_taxon_id) AS legacy_wfo,
                'duke' AS source
            FROM read_parquet(?)
            WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
            UNION ALL
            SELECT
                wfo_taxon_id,
                wfo_scientific_name AS canonical_name,
                COALESCE(NULLIF(trim(wfo_original_id), ''), wfo_taxon_id) AS legacy_wfo,
                'austraits' AS source
            FROM read_parquet(?)
            WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
        ) AS combined
        GROUP BY wfo_taxon_id
        """,
        (
            str(EIVE_PATH),
            str(TRY_ENH_PATH),
            str(DUKE_PATH),
            str(AUSTRAITS_TAXA_PATH),
        ),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE shortlist_union AS
        SELECT
            p.wfo_taxon_id,
            p.canonical_name,
            p.legacy_wfo_ids,
            p.in_eive,
            p.in_try_enhanced,
            p.in_duke,
            p.in_austraits,
            COALESCE(e.eive_numeric_count, 0) AS eive_numeric_count,
            COALESCE(t.try_numeric_count, 0) AS try_numeric_count,
            COALESCE(a.austraits_numeric_count, 0) AS austraits_numeric_count
        FROM presence p
        LEFT JOIN eive_counts e USING (wfo_taxon_id)
        LEFT JOIN try_enhanced_counts t USING (wfo_taxon_id)
        LEFT JOIN austraits_counts a USING (wfo_taxon_id)
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE shortlist_final AS
        SELECT
            *,
            CASE WHEN eive_numeric_count >= 3 THEN 1 ELSE 0 END AS qualifies_via_eive,
            CASE WHEN try_numeric_count >= 3 THEN 1 ELSE 0 END AS qualifies_via_try,
            CASE WHEN austraits_numeric_count >= 3 THEN 1 ELSE 0 END AS qualifies_via_austraits,
            CASE WHEN (eive_numeric_count >= 3)
                   OR (try_numeric_count >= 3)
                   OR (austraits_numeric_count >= 3)
                 THEN 1 ELSE 0 END AS shortlist_flag
        FROM shortlist_union
        WHERE (eive_numeric_count >= 3)
           OR (try_numeric_count >= 3)
           OR (austraits_numeric_count >= 3)
        """
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_final
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(SHORTLIST_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_final
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(SHORTLIST_CSV),),
    )

    # --- GBIF counts (accepted WFO IDs) -------------------------------
    con.execute(
        """
        CREATE OR REPLACE TABLE tmp_gbif_occurrence_counts AS
        SELECT
            wfo_taxon_id,
            COUNT(*) AS gbif_occurrence_count,
            COUNT(*) FILTER (
                WHERE decimalLatitude IS NOT NULL AND decimalLongitude IS NOT NULL
            ) AS gbif_georeferenced_count
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
        GROUP BY wfo_taxon_id
        """,
        (str(GBIF_OCC_PATH),),
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM tmp_gbif_occurrence_counts
            ORDER BY gbif_occurrence_count DESC
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(GBIF_COUNTS_WFO_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM tmp_gbif_occurrence_counts
            ORDER BY gbif_occurrence_count DESC
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(GBIF_COUNTS_WFO_CSV),),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE shortlist_with_gbif AS
        SELECT
            s.*,
            COALESCE(g.gbif_occurrence_count, 0) AS gbif_occurrence_count,
            COALESCE(g.gbif_georeferenced_count, 0) AS gbif_georeferenced_count
        FROM shortlist_final s
        LEFT JOIN tmp_gbif_occurrence_counts g USING (wfo_taxon_id)
        """
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_with_gbif
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(SHORTLIST_GBIF_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_with_gbif
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(SHORTLIST_GBIF_CSV),),
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_with_gbif
            WHERE gbif_occurrence_count >= 30
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(SHORTLIST_GBIF_GE30_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM shortlist_with_gbif
            WHERE gbif_occurrence_count >= 30
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(SHORTLIST_GBIF_GE30_CSV),),
    )


def rebuild_modelling_shortlist(con: duckdb.DuckDBPyConnection) -> None:
    """Rebuild the modelling shortlist and attach GBIF counts."""

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE eive_complete AS
        SELECT
            wfo_taxon_id,
            COALESCE(wfo_scientific_name, TaxonConcept) AS canonical_name,
            COALESCE(NULLIF(trim(wfo_original_id), ''), wfo_taxon_id) AS legacy_wfo
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> ''
          AND TRY_CAST("EIVEres-M" AS DOUBLE) IS NOT NULL
          AND TRY_CAST("EIVEres-N" AS DOUBLE) IS NOT NULL
          AND TRY_CAST("EIVEres-R" AS DOUBLE) IS NOT NULL
          AND TRY_CAST("EIVEres-L" AS DOUBLE) IS NOT NULL
          AND TRY_CAST("EIVEres-T" AS DOUBLE) IS NOT NULL
        """,
        (str(EIVE_PATH),),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE try_enhanced_numeric AS
        SELECT wfo_taxon_id, 'leaf_area' AS trait FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("Leaf area (mm2)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'leaf_n_mass' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("Nmass (mg/g)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'leaf_mass_per_area' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("LMA (g/m2)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'plant_height' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("Plant height (m)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'diaspore_mass' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("Diaspore mass (mg)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'wood_density_observed' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("SSD observed (mg/mm3)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'wood_density_imputed' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("SSD imputed (mg/mm3)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'wood_density_combined' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("SSD combined (mg/mm3)" AS DOUBLE) IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'leaf_dry_matter_content' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TRY_CAST("LDMC (g/g)" AS DOUBLE) IS NOT NULL
        """,
        (str(TRY_ENH_PATH),) * 9,
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE try_raw_numeric AS
        SELECT wfo_taxon_id, 'leaf_dry_matter_content' AS trait FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TraitSlug = 'leaf_dry_matter_content' AND StdValue IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'leaf_thickness' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TraitSlug = 'leaf_thickness' AND StdValue IS NOT NULL
        UNION ALL
        SELECT wfo_taxon_id, 'leaf_mass_per_area' FROM read_parquet(?) WHERE wfo_taxon_id IS NOT NULL AND trim(wfo_taxon_id) <> '' AND TraitSlug = 'specific_leaf_area' AND StdValue IS NOT NULL
        """,
        (str(TRY_RAW_PATH),) * 3,
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE try_numeric_union AS
        SELECT
            wfo_taxon_id,
            COUNT(DISTINCT CASE WHEN source = 'enhanced' THEN trait END) AS try_enhanced_numeric_traits,
            COUNT(DISTINCT CASE WHEN source = 'raw' THEN trait END) AS try_raw_numeric_traits,
            COUNT(DISTINCT trait) AS total_numeric_traits
        FROM (
            SELECT wfo_taxon_id, trait, 'enhanced' AS source FROM try_enhanced_numeric
            UNION ALL
            SELECT wfo_taxon_id, trait, 'raw' AS source FROM try_raw_numeric
        )
        GROUP BY wfo_taxon_id
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE modelling_shortlist AS
        SELECT
            e.wfo_taxon_id,
            e.canonical_name,
            STRING_AGG(DISTINCT e.legacy_wfo, ',') FILTER (WHERE e.legacy_wfo IS NOT NULL) AS legacy_wfo_ids,
            COALESCE(MAX(t.try_enhanced_numeric_traits), 0) AS try_enhanced_count,
            COALESCE(MAX(t.try_raw_numeric_traits), 0) AS try_raw_count,
            COALESCE(MAX(t.total_numeric_traits), 0) AS total_try_numeric_traits
        FROM eive_complete e
        LEFT JOIN try_numeric_union t USING (wfo_taxon_id)
        GROUP BY e.wfo_taxon_id, e.canonical_name
        HAVING COALESCE(MAX(t.total_numeric_traits), 0) >= 8
        """
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_shortlist
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(MODELLING_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_shortlist
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(MODELLING_CSV),),
    )

    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE modelling_with_gbif AS
        SELECT
            m.*,
            COALESCE(g.gbif_occurrence_count, 0) AS gbif_occurrence_count,
            COALESCE(g.gbif_georeferenced_count, 0) AS gbif_georeferenced_count
        FROM modelling_shortlist m
        LEFT JOIN tmp_gbif_occurrence_counts g USING (wfo_taxon_id)
        """
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_with_gbif
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(MODELLING_GBIF_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_with_gbif
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(MODELLING_GBIF_CSV),),
    )

    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_with_gbif
            WHERE gbif_occurrence_count >= 30
            ORDER BY canonical_name
        ) TO ? (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        (str(MODELLING_GBIF_GE30_PARQUET),),
    )
    con.execute(
        """
        COPY (
            SELECT *
            FROM modelling_with_gbif
            WHERE gbif_occurrence_count >= 30
            ORDER BY canonical_name
        ) TO ? (HEADER, DELIMITER ',')
        """,
        (str(MODELLING_GBIF_GE30_CSV),),
    )


def main() -> None:
    con = duckdb.connect()
    try:
        rebuild_shortlist(con)
        rebuild_modelling_shortlist(con)
    finally:
        con.close()


if __name__ == "__main__":
    main()
