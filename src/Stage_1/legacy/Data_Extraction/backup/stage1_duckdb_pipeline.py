#!/usr/bin/env python3
"""Stage 1 canonical taxon pipeline using DuckDB + WFO backbone."""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

import duckdb
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "data"
DUKE_DIR = Path("/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs")
EIVE_MAIN = DATA_DIR / "EIVE" / "EIVE_Paper_1.0_SM_08_csv" / "mainTable.csv"
CLASSIFICATION = DATA_DIR / "classification.csv"

OUTPUT_DIR = DATA_DIR / "stage1"
OUTPUT_DIR.mkdir(exist_ok=True, parents=True)

DUKE_CANONICAL = OUTPUT_DIR / "duke_canonical.parquet"
DUKE_UNMATCHED = OUTPUT_DIR / "duke_unmatched.csv"
EIVE_CANONICAL = OUTPUT_DIR / "eive_canonical.parquet"
EIVE_UNMATCHED = OUTPUT_DIR / "eive_unmatched.csv"
UNION_CANONICAL = OUTPUT_DIR / "stage1_union_canonical.parquet"
TRY_CANONICAL = OUTPUT_DIR / "try_canonical.parquet"

UPDATED_UNION_CSV = DATA_DIR / "analysis" / "duke_eive_wfo_union.csv"
UPDATED_UNION_PARQUET = DATA_DIR / "analysis" / "duke_eive_wfo_union.parquet"


def canonicalize_name(raw: str | None) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.category(ch).startswith("M"))
    text = text.replace("×", " x ")
    text = re.sub(r"\([^)]*\)", " ", text)
    text = text.replace("_", " ").replace("-", " ")
    text = re.sub(r"[^A-Za-z0-9\s\.]", " ", text)
    text = re.sub(r"\s+", " ", text).strip().lower()
    if not text:
        return None

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
        "cv",
        "cultivar",
    }
    normalized = []
    for token in text.split():
        token = token.rstrip(".")
        if not token:
            continue
        if token in rank_tokens:
            normalized.append(token if token != "subspecies" else "subsp")
            continue
        if token == "x":
            normalized.append(token)
            continue
        if any(ch.isdigit() for ch in token):
            break
        if len(token) <= 1:
            continue
        if token.endswith("."):
            break
        normalized.append(token)
        if len(normalized) >= 4:
            # limit to genus + epithet + rank + epithet
            break
    if len(normalized) >= 2:
        if normalized[-1] in rank_tokens:
            normalized = normalized[:-1]
    if not normalized:
        return None
    return " ".join(normalized)


def main() -> None:
    con = duckdb.connect()
    con.execute("PRAGMA threads=28")
    con.create_function("canonicalize", canonicalize_name, null_handling="special")

    # ------------------------------------------------------------------ WFO
    wfo_df = pd.read_csv(
        CLASSIFICATION,
        sep="\t",
        dtype=str,
        encoding="latin-1",
        keep_default_na=False,
        na_values=[],
    )
    con.register("wfo_raw_df", wfo_df)
    con.execute("CREATE OR REPLACE TABLE wfo_raw AS SELECT * FROM wfo_raw_df")

    con.execute(
        """
        CREATE OR REPLACE TABLE wfo_canonical AS
        SELECT
            taxonID,
            COALESCE(NULLIF(acceptedNameUsageID, ''), taxonID) AS accepted_wfo_id,
            canonicalize(scientificName) AS canonical_name,
            scientificName,
            LOWER(taxonomicStatus) AS taxonomic_status,
            family,
            genus,
            specificEpithet,
            infraspecificEpithet
        FROM wfo_raw
        WHERE scientificName IS NOT NULL
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE wfo_name_map AS
        SELECT canonical_name, MIN(accepted_wfo_id) AS accepted_wfo_id
        FROM wfo_canonical
        WHERE canonical_name IS NOT NULL AND canonical_name <> ''
        GROUP BY canonical_name
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE wfo_accepted AS
        SELECT *
        FROM (
            SELECT
                taxonID AS accepted_wfo_id,
                scientificName AS accepted_name,
                canonical_name AS accepted_norm,
                family,
                genus,
                specificEpithet,
                infraspecificEpithet,
                ROW_NUMBER() OVER (
                    PARTITION BY taxonID
                    ORDER BY
                        CASE WHEN taxonomic_status = 'accepted' THEN 0 ELSE 1 END
                ) AS rn
            FROM wfo_canonical
            WHERE taxonID = accepted_wfo_id
        )
        WHERE rn = 1
        """
    )

    # ------------------------------------------------------------------ Duke
    duke_records: list[dict[str, str | None]] = []
    for path in DUKE_DIR.glob("*.json"):
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        taxonomy = payload.get("taxonomy") or {}
        duke_records.append(
            {
                "plant_key": payload.get("plant_key"),
                "scientific_name": payload.get("scientific_name"),
                "genus": payload.get("genus"),
                "species": payload.get("species"),
                "taxonomy_taxon": taxonomy.get("taxon"),
                "taxonomy_species": taxonomy.get("species"),
                "taxonomy_variety": taxonomy.get("variety"),
                "taxonomy_forma": taxonomy.get("forma"),
                "source_file": path.name,
            }
        )
    duke_df = pd.DataFrame(duke_records)
    con.register("duke_raw_df", duke_df)
    con.execute("CREATE OR REPLACE TABLE duke_raw AS SELECT * FROM duke_raw_df")

    con.execute(
        """
        CREATE OR REPLACE VIEW duke_candidates AS
        SELECT plant_key,
               canonicalize(scientific_name) AS canonical_name,
               1 AS priority,
               scientific_name AS original
        FROM duke_raw
        UNION ALL
        SELECT plant_key,
               canonicalize(taxonomy_taxon) AS canonical_name,
               2 AS priority,
               taxonomy_taxon AS original
        FROM duke_raw
        UNION ALL
        SELECT plant_key,
               canonicalize(genus || ' ' || species) AS canonical_name,
               3 AS priority,
               genus || ' ' || species AS original
        FROM duke_raw
        UNION ALL
        SELECT plant_key,
               canonicalize(replace(plant_key, '_', ' ')) AS canonical_name,
               4 AS priority,
               replace(plant_key, '_', ' ') AS original
        FROM duke_raw
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE duke_matches AS
        SELECT
            plant_key,
            accepted_wfo_id,
            priority
        FROM duke_candidates c
        JOIN wfo_name_map w USING (canonical_name)
        WHERE canonical_name IS NOT NULL
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE duke_best_match AS
        SELECT plant_key, accepted_wfo_id
        FROM (
            SELECT
                plant_key,
                accepted_wfo_id,
                ROW_NUMBER() OVER (
                    PARTITION BY plant_key
                    ORDER BY best_priority, accepted_wfo_id
                ) AS rn
            FROM (
                SELECT
                    plant_key,
                    accepted_wfo_id,
                    MIN(priority) AS best_priority
                FROM duke_matches
                GROUP BY plant_key, accepted_wfo_id
            )
        )
        WHERE rn = 1
        """
    )

    con.execute(
        """
        COPY (
            SELECT DISTINCT
                plant_key,
                canonical_name,
                priority,
                original
            FROM duke_candidates
            WHERE canonical_name IS NOT NULL
                AND plant_key NOT IN (SELECT plant_key FROM duke_best_match)
        )
        TO ?
        (FORMAT CSV, HEADER TRUE)
        """,
        [str(DUKE_UNMATCHED)],
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE duke_canonical AS
        SELECT
            b.accepted_wfo_id,
            w.accepted_norm,
            w.accepted_name,
            COUNT(*) AS duke_record_count,
            STRING_AGG(DISTINCT dr.scientific_name, '; ') AS duke_scientific_names,
            STRING_AGG(DISTINCT dr.taxonomy_taxon, '; ') AS duke_matched_names,
            STRING_AGG(DISTINCT replace(dr.plant_key, '_', ' '), '; ') AS duke_original_names,
            STRING_AGG(DISTINCT dr.source_file, '; ') AS duke_files
        FROM duke_best_match b
        JOIN duke_raw dr USING (plant_key)
        LEFT JOIN wfo_accepted w ON w.accepted_wfo_id = b.accepted_wfo_id
        GROUP BY b.accepted_wfo_id, w.accepted_norm, w.accepted_name
        """
    )

    con.execute(
        """
        COPY duke_canonical
        TO ?
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        [str(DUKE_CANONICAL)],
    )

    duke_matched = con.execute("SELECT COUNT(*) FROM duke_best_match").fetchone()[0]
    duke_total = con.execute("SELECT COUNT(*) FROM duke_raw").fetchone()[0]
    print(f"Duke matches: {duke_matched:,} / {duke_total:,}")

    # ------------------------------------------------------------------ EIVE
    con.execute(
        """
        CREATE OR REPLACE TABLE eive_raw AS
        SELECT *
        FROM read_csv_auto(?, header=TRUE, all_varchar=TRUE);
        """,
        [str(EIVE_MAIN)],
    )

    con.execute(
        """
        CREATE OR REPLACE VIEW eive_candidates AS
        SELECT
            TaxonConcept,
            canonicalize(TaxonConcept) AS canonical_name
        FROM eive_raw
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE eive_matches AS
        SELECT
            TaxonConcept,
            accepted_wfo_id
        FROM eive_candidates
        JOIN wfo_name_map USING (canonical_name)
        WHERE canonical_name IS NOT NULL
        """
    )

    con.execute(
        """
        COPY (
            SELECT DISTINCT
                TaxonConcept,
                canonical_name
            FROM eive_candidates
            WHERE canonical_name IS NOT NULL
              AND TaxonConcept NOT IN (SELECT TaxonConcept FROM eive_matches)
        )
        TO ?
        (FORMAT CSV, HEADER TRUE)
        """,
        [str(EIVE_UNMATCHED)],
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE eive_canonical AS
        SELECT
            m.accepted_wfo_id,
            w.accepted_norm,
            w.accepted_name,
            COUNT(*) AS eive_taxon_count,
            STRING_AGG(DISTINCT r.TaxonConcept, '; ') AS eive_taxon_concepts,
            AVG(TRY_CAST(r."EIVEres-T" AS DOUBLE)) AS eive_T,
            AVG(TRY_CAST(r."EIVEres-M" AS DOUBLE)) AS eive_M,
            AVG(TRY_CAST(r."EIVEres-L" AS DOUBLE)) AS eive_L,
            AVG(TRY_CAST(r."EIVEres-R" AS DOUBLE)) AS eive_R,
            AVG(TRY_CAST(r."EIVEres-N" AS DOUBLE)) AS eive_N,
            SUM(CASE WHEN TRY_CAST(r."EIVEres-T" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) AS eive_T_count,
            SUM(CASE WHEN TRY_CAST(r."EIVEres-M" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) AS eive_M_count,
            SUM(CASE WHEN TRY_CAST(r."EIVEres-L" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) AS eive_L_count,
            SUM(CASE WHEN TRY_CAST(r."EIVEres-R" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) AS eive_R_count,
            SUM(CASE WHEN TRY_CAST(r."EIVEres-N" AS DOUBLE) IS NOT NULL THEN 1 ELSE 0 END) AS eive_N_count
        FROM eive_matches m
        JOIN eive_raw r USING (TaxonConcept)
        LEFT JOIN wfo_accepted w ON w.accepted_wfo_id = m.accepted_wfo_id
        GROUP BY m.accepted_wfo_id, w.accepted_norm, w.accepted_name
        """
    )

    con.execute(
        """
        COPY eive_canonical
        TO ?
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        [str(EIVE_CANONICAL)],
    )

    eive_matched = con.execute("SELECT COUNT(*) FROM eive_matches").fetchone()[0]
    eive_total = con.execute("SELECT COUNT(*) FROM eive_raw").fetchone()[0]
    print(f"EIVE matches: {eive_matched:,} / {eive_total:,}")

    # ------------------------------------------------------------------ TRY
    if TRY_CANONICAL.exists():
        print("Loading TRY canonical parquet …")
        con.execute(
            """
            CREATE OR REPLACE TABLE try_canonical AS
            SELECT * FROM read_parquet(?)
            """,
            [str(TRY_CANONICAL)],
        )
    else:
        print("TRY canonical parquet not found; continuing without TRY traits")
        con.execute(
            """
            CREATE OR REPLACE TABLE try_canonical AS
            SELECT CAST(NULL AS VARCHAR) AS accepted_wfo_id
            WHERE FALSE
            """
        )

    con.execute(
        """
        CREATE OR REPLACE TABLE union_de AS
        SELECT
            COALESCE(d.accepted_wfo_id, e.accepted_wfo_id) AS accepted_wfo_id,
            COALESCE(d.accepted_norm, e.accepted_norm) AS accepted_norm,
            COALESCE(d.accepted_name, e.accepted_name) AS accepted_name,
            COALESCE(d.accepted_wfo_id, e.accepted_wfo_id) AS wfo_id,
            d.duke_record_count,
            d.duke_scientific_names,
            d.duke_matched_names,
            d.duke_original_names,
            d.duke_files,
            CASE WHEN d.accepted_wfo_id IS NOT NULL THEN TRUE ELSE FALSE END AS duke_present,
            e.eive_taxon_count,
            e.eive_taxon_concepts,
            e.eive_T,
            e.eive_M,
            e.eive_L,
            e.eive_R,
            e.eive_N,
            e.eive_T_count,
            e.eive_M_count,
            e.eive_L_count,
            e.eive_R_count,
            e.eive_N_count,
            CASE
                WHEN e.eive_taxon_count IS NOT NULL THEN
                    (CASE WHEN e.eive_T_count > 0 THEN 1 ELSE 0 END +
                     CASE WHEN e.eive_M_count > 0 THEN 1 ELSE 0 END +
                     CASE WHEN e.eive_L_count > 0 THEN 1 ELSE 0 END +
                     CASE WHEN e.eive_R_count > 0 THEN 1 ELSE 0 END +
                     CASE WHEN e.eive_N_count > 0 THEN 1 ELSE 0 END)
                ELSE 0
            END AS eive_axes_available,
            CASE
                WHEN e.eive_T_count > 0 AND e.eive_M_count > 0 AND e.eive_L_count > 0 THEN TRUE
                WHEN e.eive_T_count > 0 AND e.eive_R_count > 0 AND e.eive_L_count > 0 THEN TRUE
                WHEN e.eive_T_count > 0 AND e.eive_M_count > 0 AND e.eive_R_count > 0 THEN TRUE
                WHEN e.eive_M_count > 0 AND e.eive_L_count > 0 AND e.eive_R_count > 0 THEN TRUE
                WHEN e.eive_T_count > 0 AND e.eive_N_count > 0 AND e.eive_L_count > 0 THEN TRUE
                ELSE FALSE
            END AS eive_axes_ge3,
            CASE WHEN e.accepted_wfo_id IS NOT NULL THEN TRUE ELSE FALSE END AS eive_present
        FROM duke_canonical d
        FULL OUTER JOIN eive_canonical e USING (accepted_wfo_id, accepted_norm, accepted_name)
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE union_canonical AS
        SELECT
            COALESCE(de.accepted_wfo_id, t.accepted_wfo_id) AS accepted_wfo_id,
            COALESCE(de.accepted_norm, t.accepted_norm) AS accepted_norm,
            COALESCE(de.accepted_name, t.accepted_name) AS accepted_name,
            COALESCE(de.wfo_id, t.accepted_wfo_id) AS wfo_id,
            COALESCE(de.duke_record_count, 0) AS duke_record_count,
            de.duke_scientific_names,
            de.duke_matched_names,
            de.duke_original_names,
            de.duke_files,
            COALESCE(de.duke_present, FALSE) AS duke_present,
            COALESCE(de.eive_taxon_count, 0) AS eive_taxon_count,
            de.eive_taxon_concepts,
            de.eive_T,
            de.eive_M,
            de.eive_L,
            de.eive_R,
            de.eive_N,
            COALESCE(de.eive_T_count, 0) AS eive_T_count,
            COALESCE(de.eive_M_count, 0) AS eive_M_count,
            COALESCE(de.eive_L_count, 0) AS eive_L_count,
            COALESCE(de.eive_R_count, 0) AS eive_R_count,
            COALESCE(de.eive_N_count, 0) AS eive_N_count,
            COALESCE(de.eive_axes_available, 0) AS eive_axes_available,
            COALESCE(de.eive_axes_ge3, FALSE) AS eive_axes_ge3,
            COALESCE(de.eive_present, FALSE) AS eive_present,
            t."TRY 30 AccSpecies ID" AS try_accspecies_ids,
            t.Genus AS try_genus,
            t.Family AS try_family,
            t."Phylogenetic Group within angiosperms" AS try_phylo_group_angiosperms,
            t."Phylogenetic Group General" AS try_phylo_group_general,
            t."Adaptation to terrestrial or aquatic habitats" AS try_habitat_adaptation,
            t.Woodiness AS try_woodiness,
            t."Growth Form" AS try_growth_form,
            t.Succulence AS try_succulence,
            t."Nutrition type (parasitism)" AS try_parasitism,
            t."Nutrition type (carnivory)" AS try_carnivory,
            t."Leaf type" AS try_leaf_type,
            t."Leaf area (mm2)" AS try_leaf_area_mm2,
            t."Nmass (mg/g)" AS try_nmass_mg_g,
            t."LMA (g/m2)" AS try_lma_g_m2,
            t."Plant height (m)" AS try_plant_height_m,
            t."Diaspore mass (mg)" AS try_diaspore_mass_mg,
            t."SSD combined (mg/mm3)" AS try_ssd_combined_mg_mm3,
            t."LDMC (g/g)" AS try_ldmc_g_g,
            t."Number of traits with values" AS try_number_traits_with_values,
            t."Leaf area (n.o.)" AS try_leaf_area_mm2_count,
            t."Nmass (n.o.)" AS try_nmass_mg_g_count,
            t."LMA (n.o.)" AS try_lma_g_m2_count,
            t."Plant height (n.o.)" AS try_plant_height_m_count,
            t."Diaspore mass (n.o.)" AS try_diaspore_mass_mg_count,
            t."SSD (n.o.)" AS try_ssd_combined_mg_mm3_count,
            t."LDMC (n.o.)" AS try_ldmc_g_g_count,
            t."Number of traits with values" AS try_number_traits_with_values_count,
            t.try_numeric_trait_count,
            t.try_numeric_traits_ge3,
            t.try_core_trait_count,
            t.try_core_traits_ge3,
            t.try_core_trait_count AS try_csr_trait_count,
            t.try_core_traits_ge3 AS try_csr_traits_ge3,
            t.try_present,
            t.try_source_species,
            NULL AS try_sla_petiole_excluded_mm2_mg,
            NULL AS try_sla_petiole_excluded_count
        FROM union_de de
        FULL OUTER JOIN try_canonical t USING (accepted_wfo_id)
        """
    )


    con.execute(
        """
        COPY union_canonical
        TO ?
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        [str(UNION_CANONICAL)],
    )

    # Merge with existing union table to retain downstream columns (TRY etc.)
    con.execute(
        """
        CREATE OR REPLACE TABLE union_existing AS
        SELECT *
        FROM read_csv_auto(?, header=TRUE, all_varchar=TRUE);
        """,
        [str(UPDATED_UNION_CSV)],
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE union_updated AS
        SELECT
            COALESCE(c.accepted_norm, e.accepted_norm) AS accepted_norm,
            COALESCE(c.accepted_name, e.accepted_name) AS accepted_name,
            CAST(COALESCE(c.wfo_id, e.wfo_ids) AS VARCHAR) AS wfo_ids,
            COALESCE(c.duke_present, CAST(e.duke_present AS BOOLEAN)) AS duke_present,
            COALESCE(CAST(c.duke_record_count AS BIGINT), TRY_CAST(e.duke_record_count AS BIGINT), 0) AS duke_record_count,
            COALESCE(c.duke_scientific_names, e.duke_scientific_names) AS duke_scientific_names,
            COALESCE(c.duke_matched_names, e.duke_matched_names) AS duke_matched_names,
            COALESCE(c.duke_original_names, e.duke_original_names) AS duke_original_names,
            COALESCE(c.duke_files, e.duke_files) AS duke_files,
            COALESCE(c.eive_present, CAST(e.eive_present AS BOOLEAN)) AS eive_present,
            COALESCE(CAST(c.eive_taxon_count AS BIGINT), TRY_CAST(e.eive_taxon_count AS BIGINT), 0) AS eive_taxon_count,
            COALESCE(c.eive_taxon_concepts, e.eive_taxon_concepts) AS eive_taxon_concepts,
            COALESCE(c.eive_T, TRY_CAST(e.eive_T AS DOUBLE)) AS eive_T,
            COALESCE(c.eive_M, TRY_CAST(e.eive_M AS DOUBLE)) AS eive_M,
            COALESCE(c.eive_L, TRY_CAST(e.eive_L AS DOUBLE)) AS eive_L,
            COALESCE(c.eive_R, TRY_CAST(e.eive_R AS DOUBLE)) AS eive_R,
            COALESCE(c.eive_N, TRY_CAST(e.eive_N AS DOUBLE)) AS eive_N,
            COALESCE(CAST(c.eive_T_count AS BIGINT), TRY_CAST(e.eive_T_count AS BIGINT), 0) AS eive_T_count,
            COALESCE(CAST(c.eive_M_count AS BIGINT), TRY_CAST(e.eive_M_count AS BIGINT), 0) AS eive_M_count,
            COALESCE(CAST(c.eive_L_count AS BIGINT), TRY_CAST(e.eive_L_count AS BIGINT), 0) AS eive_L_count,
            COALESCE(CAST(c.eive_R_count AS BIGINT), TRY_CAST(e.eive_R_count AS BIGINT), 0) AS eive_R_count,
            COALESCE(CAST(c.eive_N_count AS BIGINT), TRY_CAST(e.eive_N_count AS BIGINT), 0) AS eive_N_count,
            COALESCE(CAST(c.eive_axes_available AS BIGINT), TRY_CAST(e.eive_axes_available AS BIGINT), 0) AS eive_axes_available,
            COALESCE(c.eive_axes_ge3, CAST(e.eive_axes_ge3 AS BOOLEAN)) AS eive_axes_ge3,
            c.try_accspecies_ids,
            c.try_genus,
            c.try_family,
            c.try_phylo_group_angiosperms,
            c.try_phylo_group_general,
            c.try_habitat_adaptation,
            c.try_woodiness,
            c.try_growth_form,
            c.try_succulence,
            c.try_parasitism,
            c.try_carnivory,
            c.try_leaf_type,
            COALESCE(c.try_leaf_area_mm2, TRY_CAST(e.try_leaf_area_mm2 AS DOUBLE)) AS try_leaf_area_mm2,
            COALESCE(c.try_nmass_mg_g, TRY_CAST(e.try_nmass_mg_g AS DOUBLE)) AS try_nmass_mg_g,
            COALESCE(c.try_lma_g_m2, TRY_CAST(e.try_lma_g_m2 AS DOUBLE)) AS try_lma_g_m2,
            COALESCE(c.try_plant_height_m, TRY_CAST(e.try_plant_height_m AS DOUBLE)) AS try_plant_height_m,
            COALESCE(c.try_diaspore_mass_mg, TRY_CAST(e.try_diaspore_mass_mg AS DOUBLE)) AS try_diaspore_mass_mg,
            COALESCE(c.try_ssd_combined_mg_mm3, TRY_CAST(e.try_ssd_combined_mg_mm3 AS DOUBLE)) AS try_ssd_combined_mg_mm3,
            COALESCE(c.try_ldmc_g_g, TRY_CAST(e.try_ldmc_g_g AS DOUBLE)) AS try_ldmc_g_g,
            COALESCE(c.try_number_traits_with_values, TRY_CAST(e.try_number_traits_with_values AS DOUBLE)) AS try_number_traits_with_values,
            COALESCE(CAST(c.try_leaf_area_mm2_count AS BIGINT), TRY_CAST(e.try_leaf_area_mm2_count AS BIGINT), 0) AS try_leaf_area_mm2_count,
            COALESCE(CAST(c.try_nmass_mg_g_count AS BIGINT), TRY_CAST(e.try_nmass_mg_g_count AS BIGINT), 0) AS try_nmass_mg_g_count,
            COALESCE(CAST(c.try_lma_g_m2_count AS BIGINT), TRY_CAST(e.try_lma_g_m2_count AS BIGINT), 0) AS try_lma_g_m2_count,
            COALESCE(CAST(c.try_plant_height_m_count AS BIGINT), TRY_CAST(e.try_plant_height_m_count AS BIGINT), 0) AS try_plant_height_m_count,
            COALESCE(CAST(c.try_diaspore_mass_mg_count AS BIGINT), TRY_CAST(e.try_diaspore_mass_mg_count AS BIGINT), 0) AS try_diaspore_mass_mg_count,
            COALESCE(CAST(c.try_ssd_combined_mg_mm3_count AS BIGINT), TRY_CAST(e.try_ssd_combined_mg_mm3_count AS BIGINT), 0) AS try_ssd_combined_mg_mm3_count,
            COALESCE(CAST(c.try_ldmc_g_g_count AS BIGINT), TRY_CAST(e.try_ldmc_g_g_count AS BIGINT), 0) AS try_ldmc_g_g_count,
            COALESCE(CAST(c.try_number_traits_with_values_count AS BIGINT), TRY_CAST(e.try_number_traits_with_values_count AS BIGINT), 0) AS try_number_traits_with_values_count,
            COALESCE(CAST(c.try_numeric_trait_count AS BIGINT), TRY_CAST(e.try_numeric_trait_count AS BIGINT), 0) AS try_numeric_trait_count,
            COALESCE(c.try_numeric_traits_ge3, CAST(e.try_numeric_traits_ge3 AS BOOLEAN)) AS try_numeric_traits_ge3,
            COALESCE(CAST(c.try_core_trait_count AS BIGINT), TRY_CAST(e.try_core_trait_count AS BIGINT), 0) AS try_core_trait_count,
            COALESCE(c.try_core_traits_ge3, CAST(e.try_core_traits_ge3 AS BOOLEAN)) AS try_core_traits_ge3,
            COALESCE(CAST(c.try_csr_trait_count AS BIGINT), TRY_CAST(e.try_csr_trait_count AS BIGINT), 0) AS try_csr_trait_count,
            COALESCE(c.try_csr_traits_ge3, CAST(e.try_csr_traits_ge3 AS BOOLEAN)) AS try_csr_traits_ge3,
            COALESCE(c.try_present, CAST(e.try_present AS BOOLEAN)) AS try_present,
            COALESCE(c.try_sla_petiole_excluded_mm2_mg, TRY_CAST(e.try_sla_petiole_excluded_mm2_mg AS DOUBLE)) AS try_sla_petiole_excluded_mm2_mg,
            COALESCE(CAST(c.try_sla_petiole_excluded_count AS BIGINT), TRY_CAST(e.try_sla_petiole_excluded_count AS BIGINT), 0) AS try_sla_petiole_excluded_count,
            c.try_source_species AS try_source_species,
            e.* EXCLUDE (
                accepted_norm,
                accepted_name,
                wfo_ids,
                duke_present,
                duke_record_count,
                duke_scientific_names,
                duke_matched_names,
                duke_original_names,
                duke_files,
                eive_present,
                eive_taxon_count,
                eive_taxon_concepts,
                eive_T,
                eive_M,
                eive_L,
                eive_R,
                eive_N,
                eive_T_count,
                eive_M_count,
                eive_L_count,
                eive_R_count,
                eive_N_count,
                eive_axes_available,
                eive_axes_ge3,
                try_leaf_area_mm2,
                try_nmass_mg_g,
                try_lma_g_m2,
                try_plant_height_m,
                try_diaspore_mass_mg,
                try_ssd_combined_mg_mm3,
                try_ldmc_g_g,
                try_number_traits_with_values,
                try_leaf_area_mm2_count,
                try_nmass_mg_g_count,
                try_lma_g_m2_count,
                try_plant_height_m_count,
                try_diaspore_mass_mg_count,
                try_ssd_combined_mg_mm3_count,
                try_ldmc_g_g_count,
                try_number_traits_with_values_count,
                try_numeric_trait_count,
                try_numeric_traits_ge3,
                try_core_trait_count,
                try_core_traits_ge3,
                try_csr_trait_count,
                try_csr_traits_ge3,
                try_present,
                try_sla_petiole_excluded_mm2_mg,
                try_sla_petiole_excluded_count
            )
        FROM union_canonical c
        FULL OUTER JOIN union_existing e USING (accepted_norm)
        """
    )

    con.execute(
        """
        COPY union_updated
        TO ?
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        [str(UPDATED_UNION_PARQUET)],
    )

    con.execute(
        """
        COPY union_updated
        TO ?
        (FORMAT CSV, HEADER TRUE)
        """,
        [str(UPDATED_UNION_CSV)],
    )

    total_union = con.execute("SELECT COUNT(*) FROM union_updated").fetchone()[0]
    print(f"Stage 1 union rows: {total_union:,}")

    con.close()


if __name__ == "__main__":
    main()
