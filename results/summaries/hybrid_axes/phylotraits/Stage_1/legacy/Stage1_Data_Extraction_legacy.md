Stage 1 — Initial Plant Shortlisting Log
=======================================

Date: 2025-10-12  
Prepared by: Stage 1 data curation pipeline (DuckDB/WFO refresh)

Overview
--------
- Objective: create a reconciled universe of candidate plants by merging the Duke ethnobotanical corpus with the EIVE reference list via the WFO backbone.  
- Motivation: this “ground truth” roster underpins the new science-based encyclopedia shortlisting process, ensuring trait-ready species are prioritised before downstream EIVE modelling and CSR strategy assignments.  
- Deliverables (generated 2025‑10‑12):
  - `src/Stage_1/Data_Extraction/stage1_duckdb_pipeline.py` (DuckDB canonicaliser)
  - `src/Stage_1/Data_Extraction/update_gbif_occurrence_counts.py` (GBIF attach)
  - `src/Stage_1/Data_Extraction/canonicalise_try_traits.py` (TRY canonicaliser)
  - `data/analysis/duke_eive_wfo_union.(csv|parquet)`
  - `data/stage1/*` canonical snapshots (Duke/EIVE/union parquet + unmatched logs)
  - `data/gbif/occurrence_plantae.parquet` (Plantae-only GBIF occurrence archive)
  - `data/stage1/try_canonical.parquet` (WFO-aligned TRY traits) + `try_unmatched.csv`

Source Datasets
---------------
- **Duke ethnobotanical JSONs**  
  `/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs/*.json`  
  - 14,030 records; raw Duke exports with author strings, no embedded WFO metadata.  
  - Represents “plants with documented human use”.  
- **EIVE canonical lists**  
  - Main table: `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv` (14,835 taxa with Ellenberg-style indicator values).  
  - Auxiliary lookup retained for QA only: `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`.
- **TRY enhanced trait means**  
  `data/Tryenhanced/Dataset/Species_mean_traits.xlsx` (46,047 aggregated species profiles).  
  - Canonicalised via DuckDB/Pandas to WFO, producing `data/stage1/try_canonical.parquet` after matching 45,266 records (~98.3 %).
- **WFO backbone**  
  `/home/olier/ellenberg/data/classification.csv` (tab‑separated).  
  - Provides accepted/synonym relationships used for normalisation.

Matching Methodology
--------------------
- Script: `src/Stage_1/Data_Extraction/stage1_duckdb_pipeline.py`
  - Registers the full WFO backbone (`data/classification.csv`) in DuckDB, exposing both accepted concepts and synonym → accepted mappings via canonicalised (`canonicalize`) strings.
  - Duke processing:
    - Reads the raw JSON corpus, extracts multiple candidate labels (`scientific_name`, `taxonomy.taxon`, genus + species, slugified `plant_key`), normalises each in DuckDB, and resolves to the accepted WFO identifier with provenance.  
    - Matched 11,733 of 14,030 Duke records (~83.7 %); exports canonical matches to `data/stage1/duke_canonical.parquet` and unmatched variants to `data/stage1/duke_unmatched.csv`.
  - EIVE processing:
    - Canonicalises `TaxonConcept` strings, applies the same WFO synonym map, and aggregates indicator axes per accepted concept.
    - Matched 13,456 of 14,835 taxa (~90.7 %); unmatched concepts are written to `data/stage1/eive_unmatched.csv`.
  - Union synthesis:
    - Performs a full outer join on accepted WFO IDs, recomputes aggregate columns (`duke_*`, `eive_*`, axis counts, etc.), and refreshes the master union table in both Parquet and CSV formats.
- TRY canonicalisation (`src/Stage_1/Data_Extraction/canonicalise_try_traits.py`):
  - Reads the TRY enhanced workbook, normalises TPL-standardised species names, and resolves them to WFO using the same synonym maps.
  - Aggregates duplicate matches per accepted WFO ID (averaging trait means, summing replicate counts) and computes readiness flags (`try_numeric_traits_ge3`, `try_core_traits_ge3`).
  - Output: `data/stage1/try_canonical.parquet` (45,266 matched profiles, ~98.3 % coverage) and `data/stage1/try_unmatched.csv` (781 unresolved names for audit).
- GBIF attachment (`src/Stage_1/Data_Extraction/update_gbif_occurrence_counts.py`):
  - Materialises a plant-only parquet (`data/gbif/occurrence_plantae.parquet`) from the 130 M-row GBIF master file.
  - Canonicalises each plant record, maps via WFO synonyms, and falls back to canonical strings only when no WFO ID exists.
  - Updates `data/analysis/duke_eive_wfo_union.(csv|parquet)` with `gbif_record_count` / `gbif_has_data` and logs the 21,049 residual unmatched taxa in `data/analysis/gbif_wfo_unmatched.csv`.
- Invocation:  
  ```
  conda run -n AI python src/Stage_1/Data_Extraction/stage1_duckdb_pipeline.py
  conda run -n AI python src/Stage_1/Data_Extraction/update_gbif_occurrence_counts.py
  ```
- Output paths land in `data/stage1/` (canonical snapshots) and `data/analysis/` (union CSV/Parquet).

Headline Numbers
----------------
| Category     | Count |
|--------------|------:|
| Total unique taxa (WFO-aligned union) | 68,996 |
| Duke only    | 10,894 |
| EIVE only    | 16,337 |
| Overlap (Duke ∩ EIVE) | 2,079 |
| TRY only (no Duke/EIVE record) | 39,686 |

Key Columns in `duke_eive_wfo_union.csv`
----------------------------------------
- `accepted_norm` – canonical lowercase WFO key used throughout Stages 1–3.  
- `accepted_name` – human-readable label (best available from Duke/EIVE list).  
- `wfo_ids` – joined list of WFO identifiers encountered (may be empty if WFO file lacks the row).  
- Presence / provenance flags:
  - `duke_present`, `duke_record_count`, `duke_files`, `duke_scientific_names`, `duke_matched_names`, `duke_original_names`.  
- `eive_present`, `eive_taxon_count`, `eive_taxon_concepts`, `eive_accepted_names`.  
- Aggregated EIVE indicator values for each axis (mean across matched concepts):
  - `eive_T`, `eive_M`, `eive_L`, `eive_R`, `eive_N`
  - per-axis availability counters (`*_count`)
  - `eive_axes_available` (number of axes with data)
  - `eive_axes_ge3` (flag when ≥3 axes are populated)
- TRY enhanced trait fields (species means from `Species_mean_traits.xlsx`):
  - `try_leaf_area_mm2`, `try_lma_g_m2`, `try_ldmc_g_g`, `try_nmass_mg_g`, `try_plant_height_m`, `try_diaspore_mass_mg`, `try_ssd_combined_mg_mm3`, `try_number_traits_with_values`
  - accompanying replicate counts (`*_count`)
  - `try_core_trait_count` (number of CSR-critical leaf traits present: LA, LMA, LDMC)
  - `try_core_traits_ge3` (true when all three core traits are available) and `try_present` overall flag
  - `try_numeric_trait_count` (how many numeric means are present across the full TRY panel) and `try_numeric_traits_ge3`
- CSR trait readiness (StrateFy inputs derived from TRY):
  - `try_csr_trait_count`, `try_csr_traits_ge3` (aliases of the LA/LMA/LDMC counts/flag)
- GBIF occurrence metadata:
  - `gbif_slug`, `gbif_file_path`, `gbif_record_count`, `gbif_has_data`

Usage Notes
-----------
1. **Shortlisting**  
   Filter for `duke_present == True` AND `eive_present == True` to prioritise taxa already supported by both ethnobotanical narratives and EIVE indicator values.  
2. **Gap analysis**  
 - `Duke only`: high ethnobotanical value but lacking Stage 2 trait coverage; candidates for future indicator modelling.  
  - `EIVE only`: strong trait/indicator backbone but no Duke ethnobotany—excellent for enriching encyclopedia narratives beyond medicinal bias.  
3. **WFO finalisation**  
   Always retain the `accepted_norm` column when passing species into Stage 2 and Stage 3 pipelines; composites, trait joins, and CSR calculations rely on that key.
4. **Canonical parquet practice**  
   Keep each canonical parquet (Duke, EIVE, TRY, GBIF) separate and join them on `accepted_wfo_id` / `accepted_norm` as needed; this ensures every dataset stays in sync with the WFO backbone while allowing targeted refreshes.  
5. **Next steps**  
   - Attach trait coverage stats (Stage 2 SEM tables) to this union to score data readiness.  
   - Overlay CSR trait readiness (`try_csr_traits_ge3`) and EIVE completeness to build an evidence-weighted shortlist for the encyclopedia launch.

Current Readiness Snapshots (2025‑10‑12)
-----------------------------------------
- **Dual-ready (≥3 EIVE axes & ≥3 TRY numeric traits)**: 3,677 taxa (~5.3 % of union).  
- **Either criterion satisfied**: 28,618 taxa (~41.5 %).  
- **EIVE-only readiness**: 13,826 taxa (~20.0 %).  
- **TRY trait-only readiness**: 11,115 taxa (~16.1 %).  
- **StrateFy inputs available (LA+LMA+LDMC)**: 2,290 taxa (~3.3 %); 1,804 of these already satisfy the EIVE ≥3 criterion.  
- **Direct SLA (TraitID 3115, petiole excluded)**: 8,117 taxa (~11.8 %) have measured SLA means attached.  
- **Either LDMC (from enhanced TRY) or SLA (3115) available**: 9,239 taxa (~13.4 %).  
- **GBIF coverage**: 46,394 taxa (~67.2 %) have an occurrence count; the median species contributes 50 records (mean ~1,079), and 41,006 taxa (~59.4 %) already have ≥3 occurrences.  
- **Qualified shortlist (≥3 GBIF records + ≥3 EIVE axes or ≥3 TRY numeric traits)**: 19,249 taxa (~27.9 %); their GBIF occurrences have a median of 130 records (mean ~2,039), and 2,675 shortlisted taxa still have <10 records.
- Remaining species currently lack ≥3 indicator axes and ≥3 numeric TRY traits; they remain in the union for future data enrichment.

Reproduction Checklist
----------------------
1. Ensure the following artefacts exist (regenerate if missing):
   - `data/classification.csv` (latest WFO export)
   - Duke JSON directory (`duke_complete_with_refs`)
   - EIVE CSVs (`EIVE_Paper_1.0_SM_08_csv/mainTable.csv`)
2. Run the DuckDB canonicaliser:  
   `conda run -n AI python src/Stage_1/Data_Extraction/stage1_duckdb_pipeline.py`
3. Canonicalise TRY traits and refresh GBIF counts:  
   `conda run -n AI python src/Stage_1/Data_Extraction/canonicalise_try_traits.py`  
   `conda run -n AI python src/Stage_1/Data_Extraction/update_gbif_occurrence_counts.py`
4. Inspect the canonical snapshots in `data/stage1/` and the updated union in `data/analysis/`.

Change Log
----------
- **2025‑09‑20** — Initial version documenting the WFO-based union workflow and headline statistics for Stage 1 shortlisting.  
- **2025‑10‑12** — Rebuilt Stage 1 using DuckDB + WFO backbone; canonicalised Duke/EIVE/TRY from their raw sources, produced TRY canonical parquet, materialised Plantae-only GBIF parquet, refreshed occurrence coverage, and updated readiness metrics.
