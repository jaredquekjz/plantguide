# Stage 1: Data Extraction Process

## Executive Summary
- Species matching (WFO, canonical Python): 1,051/1,068 matched (98.7%); output `artifacts/gbif_complete_trait_matches_wfo.json`.
- Bioclim-first pipeline (extract → clean → summarize): 5,239,194 cleaned occurrences; 1,008 species with bioclim; 654 species with ≥3 occurrences.
- Coordinate de-duplication policy (UPDATED): species-level environmental summaries now use unique coordinates per species (no overweighting repeated observations) across Bioclim, SoilGrids, and Aridity Index.
- Final modeling datasets (expanded600):
  - Core traits: `artifacts/model_data_bioclim_subset.csv` (654 × 29)
  - Enhanced traits (NEW): `artifacts/model_data_bioclim_subset_enhanced.csv` (654 × 39; adds leaf thickness, phenology, photosynthesis, frost tolerance, plus Narea)
- Enhanced trait coverage among 654 species:
  - Phenology 90.8% (594), Photosynthesis 94.6% (619), Leaf thickness 53.4% (349), Frost tolerance 23.4% (153)
- WFO normalization status: 0 missing/empty `wfo_accepted_name` in the expanded600 datasets.
- Canonical commands: `make bioclim_first`, `make try_extract_traits`, `make try_merge_enhanced_subset`.

## Overview
Stage 1 focuses on extracting and matching trait data with GBIF occurrence data to maximize species coverage for hybrid trait-bioclim models. Enhanced TRY traits (leaf thickness, phenology, photosynthesis pathway, frost tolerance) are now extracted and merged into dedicated datasets for upcoming modeling.

Methodological update (2025‑09‑13): Environmental summaries (Bioclim, SoilGrids, Aridity Index) are computed from unique coordinates per species. Multiple observations at the same lon/lat for a species count as a single spatial point for environmental averaging and SDs. This prevents overweighting heavily sampled locations and yields more spatially representative species profiles.

## Data Lineage (Expanded 600)

```
[TRY Traits]
  artifacts/model_data_complete_case_with_myco.csv
            │
            │ (names normalized; WFO-aligned upstream)
            ▼
  (Stage 1, Step 6c) ───────────────┐
                                    │  join + filter ≥3 occurrences
                                    │
[GBIF Occurrences + Matches]
  artifacts/gbif_complete_trait_matches_wfo.json
  /home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete/*.gz
            │
            │ extract bioclim (WorldClim v2.1, 30s) for ALL coords
            ▼
  data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv
            │
            │ species summary (means/sd + n_occ)
            ▼
  data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv
                                    │
                                    ├────────► artifacts/model_data_bioclim_subset.csv
                                    │              (654 species × 29 cols)
                                    │
                                    └────────► artifacts/model_data_bioclim_subset_enhanced.csv
                                                   (654 species × 39 cols; +4 new TRY traits + Narea)

Downstream (Stage 3 RF/Hybrid):
  Consumes:
    - traits: artifacts/model_data_bioclim_subset.csv (or artifacts/model_data_bioclim_subset_enhanced.csv)
    - bioclim: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv (means/SDs from unique coordinates per species)
```

## Key Achievements
- **1,051 of 1,068 trait species matched with GBIF (98.7%)**
- **1,008 species successfully extracted with bioclim data (96% of matched)**
- **654 species with ≥3 occurrences suitable for modeling**
- **5,239,194 quality-controlled occurrences with bioclim variables**
- **Trait data source: `/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv`**

## Data Sources

### 1. Trait Data
- **Source**: `/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv`
- **Species**: 1,068 with complete trait cases (29 columns total)
- **Core functional traits (6)**: 
  - Leaf area (mm2) - LA
  - Leaf Mass per Area (g/m2) - LMA  
  - Plant height (m) - H
  - Diaspore mass (mg) - SM (seed mass)
  - Stem Specific Density (mg/mm3) - SSD
  - Leaf nitrogen mass (mg/g) - Nmass
- **Ecological groupings**: 
  - Myco_Group_Final (mycorrhiza type)
  - Woodiness (woody/non-woody)
  - Growth Form
  - Leaf type

### 2. GBIF Occurrence Data  
- **Source**: `/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete`
- **Total files**: 386,493 (including hybrids, unnamed taxa)
- **Matched files**: 1,051 species from trait dataset
- **Total raw occurrences**: 5,667,399 from matched species

## Species Matching Pipeline

### Approach Comparison

| Method | Tool | Match Rate | Notes |
|--------|------|------------|-------|
| Simple normalization | Basic string matching | 559/1,068 (52%) | Original approach, limited |
| WFO synonym resolution | Python + WFO CSV | 1,051/1,068 (98.7%) | **Best performance** |
| WorldFlora R package | WFO.match() | 311/1,068 (29%) | Capitalization issues |

### Winning Strategy
```python
# Three-pass matching with WFO backbone
1. Direct normalized name matching → 1,033 species
2. Match via WFO synonyms → 2 species  
3. Reverse WFO lookup → 16 species
Total: 1,051 matches (98.7%)
```

**Key files**:
- Matching script: `/home/olier/ellenberg/src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py`
- Match results: `/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json`

## Bioclim Extraction Pipeline (Improved)

### Novel Approach: Extract First, Clean Later
Unlike traditional pipelines that clean coordinates before extraction, we extract bioclim for ALL coordinates first, then apply quality filters. This provides complete visibility into data loss causes.

**Extraction script**: `/home/olier/ellenberg/src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R`

### Processing Steps

1. **Load all 1,051 matched species** from GBIF files
2. **Basic coordinate validation**: Remove invalid lat/lon and 0,0 coordinates
3. **Extract bioclim for 2,195,865 unique coordinates**
   - 2,148,104 coordinates with valid bioclim (97.8%)
   - 47,761 coordinates in ocean/no-data areas (2.2%)
4. **Apply coordinate cleaning** (CoordinateCleaner)
   - Tests: capitals (20km), institutions (2km), centroids, equal lat/lon, GBIF HQ
   - 314,059 occurrences flagged (5.7%)
   - 5,239,194 occurrences passed all tests (94.3%)

### Species Loss Analysis

| Stage | Species Count | Loss | Reason |
|-------|--------------|------|--------|
| Initial matched | 1,051 | - | - |
| Valid coordinates | 1,051 | 0 | All have coordinates |
| Has bioclim data | 1,045 | 6 | Ocean/no-data locations |
| Pass coord cleaning | 1,008 | 37 | Near capitals/institutions |
| ≥3 occurrences | 654 | 354 | Too few occurrences |

**Species tracking file**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/diagnostics/species_tracking.csv`

## 📍 FINAL EXTRACTED DATA

### Primary Output File
**`/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`**
- **Size**: 1,576,074,682 bytes (1.47 GB)
- **Format**: CSV with all occurrences (including duplicates at same location)
- **Rows**: 5,239,194 data rows (excluding header)
- **Species**: 1,008 species
- **Variables**: coordinates, species name, 19 bioclim variables, metadata

### Occurrence Statistics

#### All 1,008 Species
- **Total occurrences**: 5,239,194
- **Mean per species**: 5,197.6
- **Median per species**: 6
- **Range**: 1 to 889,123

#### 654 Species with ≥3 Occurrences (Modeling-Ready)
- **Total occurrences**: 5,238,729 (99.99% of all data)
- **Mean per species**: 8,010.3
- **Median per species**: 19
- **25th percentile**: 6 occurrences
- **75th percentile**: 147 occurrences

### Top Species by Occurrences
1. Hedera helix: 889,123
2. Leucanthemum vulgare: 659,025
3. Rumex crispus: 500,845
4. Phleum pratense: 333,820
5. Silene vulgaris: 327,642

### Diagnostic Files
- **Species tracking**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/diagnostics/species_tracking.csv`
- **Individual species files**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/species_data/`

### De‑duplication Policy (Bioclim)
- Extraction: both the bioclim‑first pipeline and the cleaned pipeline extract at unique coordinates to reduce compute.
- Summary (UPDATED): species‑level bioclim means/SDs are computed from unique coordinate rows per species (not weighted by repeated observations at that coordinate). The summary reports `n_occurrences` (all cleaned observations) and also `n_unique_coords` per species.
- Sufficiency rule: species inclusion still uses `n_occurrences` (≥3 cleaned occurrences), not `n_unique_coords`. Unique‑coordinate roll‑up is only for computing means/SDs to avoid sampling bias.

### Cleaned Pipeline (Unique‑Coordinates Summary)
- Canonical targets (updated):
  - `make clean_extract_bioclim` → runs `src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_noDups.R`
  - `make clean_extract_bioclim_v2` → runs `src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_noSea.R`
- Both produce `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv` with:
  - `n_occurrences` (all cleaned observations)
  - `n_unique_coords` (count of unique lon/lat per species)
  - Per‑species means/SDs computed from unique coordinates
- Recommendation: use `clean_extract_bioclim` (noDups) for parity with bioclim‑first; use `*_v2` (noSea) if sea‑test hangs are an issue.

Deprecated references:
- Old helper names under `scripts/clean_gbif_extract_bioclim*.R` are not used anymore. The source of truth lives under `src/Stage_1_Data_Extraction/gbif_bioclim/`.

## GloBI Interactions (Stage 3) — Extraction + Join

Purpose

- Add species–interaction features (pollination, herbivory, pathogen, dispersal proxies) to the Stage 3 plant list, using the local GloBI cache and the WFO backbone for robust name matching.

Inputs

- GloBI interactions (local cache): `/home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz`
- WFO classification backbone: `/home/olier/plantsdatabase/data/Stage_1/classification.csv`
- Stage 3 trait table (654 spp): `/home/olier/ellenberg/artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv`

Outputs

- Per‑plant GloBI features (Stage 3 set): `/home/olier/ellenberg/artifacts/globi_mapping/stage3_globi_interaction_features.csv`
- Final joined dataset (Stage 3 traits + GloBI features): `/home/olier/ellenberg/artifacts/globi_mapping/stage3_traits_with_globi_features.csv`
- Raw matched interactions (for drill‑downs): `/home/olier/ellenberg/artifacts/globi_mapping/globi_interactions_raw.csv.gz`
- Report (coverage, top partners, sanity checks): `results/summaries/hybrid_axes/phylotraits/Stage 3/globi_interactions_report.md`

Procedure (repro)

1) Extract plant binomials from GloBI (streaming)

```bash
cd /home/olier/plantsdatabase
tmux new -s globi_binom -d "python src/Stage_3/extract_globi_plant_binomials_streaming.py > logs/globi_binom.log 2>&1"
tmux attach -t globi_binom  # monitor; output: data/Stage_3/globi_plant_binomials.csv
```

2) WFO normalization of GloBI plants (parallel + fuzzy)

```bash
cd /home/olier/plantsdatabase
# smoke test on 100 names
R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript src/Stage_3/globi_wfo_normalize.R --test > logs/globi_wfo_test.log 2>&1

# full run in tmux
tmux new -s globi_wfo -d "R_LIBS_USER='/home/olier/ellenberg/.Rlib' Rscript src/Stage_3/globi_wfo_normalize.R > logs/globi_wfo.log 2>&1"
tmux attach -t globi_wfo

# outputs
# data/Stage_3/globi_plants_wfo/globi_plants_with_wfo.csv
# data/Stage_3/globi_plants_wfo/normalization_summary.txt
```

3) Stream interactions and build Stage 3 features (WFO synonyms aware)

```bash
cd /home/olier/ellenberg
mkdir -p artifacts/globi_mapping logs
tmux new -s globi_join -d "python -u scripts/globi_join_stage3.py > logs/globi_join.log 2>&1"
tmux attach -t globi_join  # monitor progress; writes raw + features + final join
```

4) Generate summary report

```bash
cd /home/olier/ellenberg
python scripts/globi_report_stage3.py
# report: results/summaries/hybrid_axes/phylotraits/Stage 3/globi_interactions_report.md
```

Notes

- Name matching strictly follows the WFO backbone (accepted + synonyms), normalized (lowercase; diacritics removed). GloBI matches are credited to the canonical `wfo_accepted_name`.
- Herbivory currently includes some nectar/pollen “eats” events for pollinators. If you prefer herbivory to reflect tissue consumers only, post‑filter the raw interactions by excluding partners that also “pollinate/visitFlowersOf” the same plant, or limit herbivory to records with plant as target and partner kingdom = Animalia.
- Dispersal categories depend on available interaction labels in the GloBI dump; extend mapping in `scripts/globi_join_stage3.py` if needed.

Key Artifacts (canonical locations)

- GloBI→WFO normalized plants: `/home/olier/plantsdatabase/data/Stage_3/globi_plants_wfo/globi_plants_with_wfo.csv`
- Stage 3 features (per plant): `/home/olier/ellenberg/artifacts/globi_mapping/stage3_globi_interaction_features.csv`
- Final modelling dataset with GloBI features: `/home/olier/ellenberg/artifacts/globi_mapping/stage3_traits_with_globi_features.csv`

## Expanded 600: Final Traits+Bioclim Dataset + Merge Script (Ground Truth)

This section records the exact dataset and merge step used for the expanded 600‑species runs. It aligns with the Makefile targets and the expanded600 hybrid summaries in this folder.

### Final Dataset Used by Expanded 600 Runs

- Trait subset (≥3 cleaned occurrences): `artifacts/model_data_bioclim_subset.csv`
  - Size: 186,002 bytes (181.64 KB)
  - Rows (species): 654
  - Columns: 29 (EIVE targets + 6 core traits + metadata)
  - Species column: `wfo_accepted_name` (WFO‑aligned)

- Species‑level climate summary used by hybrid runs: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv`
  - Size: 536,834 bytes (524.25 KB)
  - Rows (species): 1,008 total; 654 with `n_occurrences ≥ 3`
  - Columns: 41 (per‑species `n_occurrences`, `bio1…bio19` means and SDs, flags)
  - Note: functionally identical to the Stage‑1 summary under `bioclim_first`; mirrored here for Stage‑3 consumption

- Provenance record (occurrence‑level): `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`
  - Size: 1,576,074,682 bytes (1.47 GB)
  - Rows (occurrences): 5,239,194 (header excluded)
  - Species: 1,008 with ≥1 climate‑valid record; 654 with ≥3 after cleaning

Cross‑reference:
- Summaries consuming this dataset: `results/summaries/hybrid_axes/expanded600/hybrid_summary_*_expanded600.md`
- Makefile defaults pointing here: `Makefile.hybrid` (`TRAIT_CSV`, `BIOCLIM_SUMMARY`)

### Merge Script Used (Stage 1)

The bioclim‑subset trait CSV used in the expanded 600 runs is produced inside the Stage‑1 pipeline (Step 6c) by merging the species‑level climate summary onto the trait table and filtering to species with ≥3 valid occurrences.

- Script: `src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R` (Step 6c)
- Effective inputs:
  - Traits: `artifacts/model_data_complete_case_with_myco.csv`
- Bioclim summary: `data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv`
  - Threshold: `min_occurrences = 3`
- Output (ground truth consumed by Stage 3):
  - `artifacts/model_data_bioclim_subset.csv` (654 × 29)

Note: The ≥3 inclusion threshold refers to occurrence count. Environmental summaries (means/SDs) are derived from unique coordinates. The summary table includes both `n_occurrences` and `n_unique_coords` for transparency.

### Enhanced TRY Traits (New)

- Extraction command:
  - `make try_extract_traits`
- Expected outputs (RDS) in `/home/olier/ellenberg/artifacts/stage1_data_extraction/`:
  - `trait_46_leaf_thickness.rds`
  - `trait_37_leaf_phenology_type.rds`
  - `trait_22_photosynthesis_pathway.rds`
  - `trait_31_species_tolerance_to_frost.rds`
  - `extracted_traits_summary.csv`

### Merge New TRY Traits into Datasets

- Full (all 1,068 species):
  - `make try_merge_enhanced_full`
  - Outputs:
    - `artifacts/model_data_enhanced_traits_full.csv` (1068 × 39)
    - `artifacts/model_data_enhanced_traits_complete.csv` (1068 × 39)
- Expanded600 subset (≥3 occurrences):
  - `make try_merge_enhanced_subset`
  - Outputs:
    - `artifacts/model_data_bioclim_subset_enhanced.csv` (654 × 39)
    - `artifacts/model_data_bioclim_subset_enhanced_complete.csv` (654 × 39)

### Enhanced Traits Coverage — Expanded 600 (654 species)

- Coverage (non-missing, usable values):
  - Leaf thickness (mm): 349/654 (53.4%)
  - Leaf phenology (evergreen/deciduous/…): 594/654 (90.8%)

## SoilGrids Extraction and Aggregation (aligned with Bioclim)

- Extraction: `scripts/extract_soilgrids_efficient.R` extracts values for unique coordinates, then joins back to occurrences.
- Aggregation (UPDATED): `scripts/aggregate_soilgrids_species.R` collapses to unique coordinates per species before computing means/SDs and valid counts per layer. Output summary includes both `n_occurrences` and `n_unique_coords`.

## Aridity Index (AI)

- Annual AI raster: `data/PET/Global-AI_ET0__annual_v3_1/ai_v31_yr.tif` (UInt16; scaled by 1/10000 to dimensionless P/PET).
- Augmentation utility: `src/Stage_1_Data_Extraction/gbif_bioclim/augment_bioclim_summary_with_ai.R` adds `ai_mean`/`ai_sd` and standardized aliases `aridity_mean`/`aridity_sd` to the species bioclim summary.
- De‑duplication: AI stats are computed from unique (species, lon, lat) coordinates (consistent with Bioclim/Soil).

### Monthly AI (P/PET) Features (Added)
- Extraction‑first pipeline (fast + robust):
  1) Extract monthly AI at unique coordinates to part CSVs (sharded):
     - `make -f Makefile.hybrid ai_month_extract_tmux AI_MONTH_DIR=data/PET/Global_AI__monthly_v3_1/Global_AI__monthly_v3_1 SHARDS=8 CHUNK=80000`
     - Outputs: `data/bioclim_extractions_bioclim_first/ai_monthly_coords_part_0{i}of0{K}.csv` with columns:
       - `species, lon, lat, ai_m01, …, ai_m12` (dimensionless monthly AI)
  2) Aggregate per‑species dryness features and merge to summary:
     - `make -f Makefile.hybrid ai_month_aggregate PARTS_DIR=data/bioclim_extractions_bioclim_first BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv BIOCLIM_SUMMARY_OUT_AIMONTH=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
     - Adds the following indicators (unique‑coordinate median per species):
       - `ai_month_min`: minimum monthly AI (intensity of driest month)
       - `ai_month_p10`: 10th percentile monthly AI (robust low‑end)
       - `ai_roll3_min`: minimum 3‑month rolling mean AI (seasonal dryness severity)
       - `ai_dry_frac_t020`: fraction of months with AI < 0.20 (arid/semi‑arid exposure)
       - `ai_dry_run_max_t020`: longest consecutive months with AI < 0.20
       - `ai_dry_frac_t050`: fraction of months with AI < 0.50 (dry‑subhumid exposure)
       - `ai_dry_run_max_t050`: longest consecutive months with AI < 0.50
       - `ai_amp`: amplitude p90 − p10 (seasonality of aridity)
       - `ai_cv_month`: coefficient of variation across months (relative variability)
       - `n_ai_m`: number of unique coordinates (per species) contributing monthly AI (post‑patch; accurate count)
  - Notes:
    - All monthly AI features are computed from unique (species, lon, lat) coordinates and then summarized per species by median.
    - Set `SHARDS` high enough to use available cores; adjust `CHUNK` to balance memory/throughput.
  - Photosynthesis pathway (C3/C4/CAM): 619/654 (94.6%)
  - Frost tolerance score: 153/654 (23.4%)

- Combined coverage (count of valid new traits per species):
  - 0 traits: 22 species
  - 1 trait: 23 species
  - 2 traits: 244 species
  - 3 traits: 256 species
  - 4 traits: 109 species

- Notes on merging and unmatched cases:
  - Matching uses normalized WFO accepted names; merges are inner-on-species (left on traits table).
  - Unmatched by trait (counts of species without a value):
    - Leaf thickness: 305 species
    - Leaf phenology: 60 species
    - Photosynthesis pathway: 35 species
    - Frost tolerance: 501 species
  - A small subset (22 species) lacks all four new traits (example subset: Centaurea rhaetica; Cerastium fontanum subsp. vulgare; Coreopsis tinctoria; Crepis froelichiana; Dipsacus fullonum; Erigeron canadensis; Euphorbia variabilis; Helianthemum apenninum; Inula britannica; Inula montana).

Interpretation:
- Phenology and photosynthesis pathway are pervasive in the expanded 600 and are immediately useful for modeling.
- Leaf thickness has moderate coverage (~53%). Frost tolerance is sparse (~23%) but still potentially informative; consider phylogenetic imputation for improved coverage.

Notes:
- Species name alignment in Step 6c uses normalized strings consistent with WFO‑accepted names set upstream during GBIF matching; no additional synonym expansion is required at this step.
- An auxiliary preparer exists (`src/Stage_3RF_Hybrid/prepare_bioclim_subset_traits.R`) which can also filter traits by `n_occurrences ≥ 3` against a provided summary (output default: `artifacts/model_data_bioclim_subset_expanded600.csv`). The expanded600 runs documented here used the Stage‑1 output `artifacts/model_data_bioclim_subset.csv` per the Makefile defaults and summary files.

### Reproducible Commands

- One‑shot Stage‑1 pipeline (copies GBIF if needed → extract bioclim → clean → summarize → merge+filter ≥3):
  - `make bioclim_first`
  - Key outputs echoed on completion:
    - `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`
    - `data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv`
    - `artifacts/model_data_bioclim_subset.csv`

- Hybrid runs (expanded600) consuming these exact artifacts (no phylo / with phylo):
  - No p_k:
    - `make -f Makefile.hybrid hybrid_cv AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_bioclim_subset TRAIT_CSV=artifacts/model_data_bioclim_subset.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000`
  - With p_k:
    - `make -f Makefile.hybrid hybrid_pk AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk TRAIT_CSV=artifacts/model_data_bioclim_subset.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0`

- To run with enhanced traits, set `TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced.csv` in the above commands.

### Effective Parameters and Assumptions

- Encoding: UTF‑8 for all CSVs
- Chunking: occurrence extraction operates on unique coordinates; duplicates preserved on merge‑back
- Cleaning thresholds: capitals 20 km, institutions 2 km; tests = capitals, centroids, equal lat/lon, GBIF HQ, institutions
- Filter: `min_occurrences = 3` applied at species level after cleaning
- Bioclim: WorldClim v2.1, 30 arc‑seconds; variables `bio1…bio19`
- Name alignment: WFO‑accepted names from upstream WFO matching (`wfo_accepted_name`); bioclim summary keys derived from `species_clean`
- Soil: excluded from expanded600 dataset due to incomplete VRT coverage (see SoilGrids section below)

## Comparison with Previous Pipeline

| Metric | Old Pipeline | New Pipeline | Improvement |
|--------|-------------|--------------|-------------|
| Species processed | 837 | 1,008 | +171 (+20.4%) |
| Species with ≥3 occ | 559 | 654 | +95 (+17.0%) |
| Total occurrences | Unknown | 5,239,194 | Fully tracked |
| Duplicate preservation | Unclear | Preserved | ✓ Verified |
| Ocean/no-data tracking | Unknown | 6 species | ✓ Identified |
| Coord cleaning losses | Unknown | 37 species | ✓ Tracked |

## Technical Implementation

### Key Scripts
1. **Species matching**: `/home/olier/ellenberg/src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py`
2. **Bioclim extraction**: `/home/olier/ellenberg/src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R`
3. **Validation**: `/home/olier/ellenberg/validate_extraction_results.R`

### Configuration
- **WFO backbone**: 1.6M records in `/home/olier/ellenberg/data/classification.csv`
- **WorldClim**: Version 2.1 at 30s resolution (≈1km)
- **Bioclim variables**: All 19 standard variables (bio1-bio19)
- **Coordinate cleaning**: CoordinateCleaner with relaxed thresholds
- **Parallel processing**: 8 cores for extraction

## Canonical Pipelines & Scripts (Authoritative)

- Species name standardization (WFO backbone)
  - Canonical (Python): `src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py`
  - Output of record: `artifacts/gbif_complete_trait_matches_wfo.json`
  - WFO backbone: `data/classification.csv`
  - Note: This is the Python script highlighted in the “Species Matching Pipeline” above and is NOT legacy. It is the authoritative matcher with the 3‑pass strategy (normalized → synonyms → reverse lookup) achieving 98.7% matches.

- TRY traits (enhanced) — extraction and merge
  - Extract (canonical): `make try_extract_traits`
    - Script: `src/Stage_1_Data_Extraction/extract_try_traits.R`
    - Outputs: `artifacts/stage1_data_extraction/trait_{46|37|22|31}*.rds`, `extracted_traits_summary.csv`
  - Merge into traits (canonical):
    - Full: `make try_merge_enhanced_full`
      - Script: `src/Stage_2_Data_Processing/assemble_model_data_with_enhanced_traits.R`
      - Outputs: `artifacts/model_data_enhanced_traits_full.csv`, `..._complete.csv`
    - Expanded600 subset: `make try_merge_enhanced_subset`
      - Script: same as above
      - Outputs: `artifacts/model_data_bioclim_subset_enhanced.csv`, `..._enhanced_complete.csv`

- GBIF → WorldClim (bioclim) — extract, clean, summarize (duplicates preserved)
  - Canonical one‑shot: `make bioclim_first`
    - Script: `src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R`
    - Outputs: `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`,
      `.../summary_stats/species_bioclim_summary.csv`, `artifacts/model_data_bioclim_subset.csv`
  - Legacy alternatives (bioclim extraction only — not matching):
    - Python (legacy bioclim extractor): `scripts/extract_bioclim_pipeline.py`
    - R (older variants): `scripts/extract_bioclim_pipeline.R`, `scripts/clean_gbif_extract_bioclim*.R`, `scripts/clean_gbif_extract_bioclim.py`

- SoilGrids — extract, aggregate, WFO merge
  - Extract: `make soil_extract` → `scripts/extract_soilgrids_efficient.R`
  - Aggregate: `make soil_aggregate` → `scripts/aggregate_soilgrids_species.R`
  - Merge (canonical WFO alignment): `make soil_merge` → `scripts/merge_trait_bioclim_soil_wfo.R`
  - One‑shot pipeline: `make soil_pipeline`

## Common Merge Methodology (TRY, GBIF/WorldClim, Soil)

- Canonical join key
  - Species‑level merges converge on the WFO accepted name: `wfo_accepted_name`.
  - WFO backbone: `data/classification.csv`.

- Name normalization (shared idea)
  - Lowercase, trim, collapse spaces, ASCII transliteration, and removal of stray hybrid markers (`×`).
  - Example (R):
    - `normalize_name()` in `scripts/merge_trait_bioclim_soil_wfo.R`.

- WFO resolution (how strings become accepted names)
  - Build mapping: normalized `scientificName` → accepted WFO name using `taxonomicStatus`/`acceptedNameUsageID`.
  - Prefer accepted names over synonyms (rank ordering); keep one best entry per normalized key.
  - Outputs a stable accepted name column used downstream (`wfo_accepted_name`).

- Join rules by data type
  - TRY enhanced traits → traits base:
    - Inputs: TRY RDS with `AccSpeciesName`; base trait CSV with `wfo_accepted_name`.
    - Normalize both to `species_norm`, then LEFT‑join onto the base (keeps all trait species).
    - Aggregation: numeric → median (+ mean/sd); categorical → majority value. Counts stored with `_n` suffix.
    - Script: `src/Stage_2_Data_Processing/assemble_model_data_with_enhanced_traits.R`.
  - Bioclim/Soil species summaries → traits base:
    - Summaries carry `species` (from occurrences). Normalize and harmonize to WFO (`wfo_final`).
    - INNER‑join by design (both sides must exist) to create strictly “available‑data” merged tables.
    - Climate stats columns: `bio{1..19}_mean`, `bio{1..19}_sd`; Soil columns: `phh2o_*`, `soc_*`, `bdod_*`, etc.
    - Script: `scripts/merge_trait_bioclim_soil_wfo.R`.

- Aggregation and de‑duplication
  - Occurrence‑level duplicates at identical coordinates are preserved in `all_occurrences_cleaned.csv` (provenance).
  - Species summaries compute mean/sd per species; `n_occurrences` recorded; `has_sufficient_data` flagged.

- Filtering & thresholds (for modeling subsets)
  - Default: `min_occurrences = 3` (species‑level) applied to bioclim summaries to derive the expanded600 trait subset.
  - Output: `artifacts/model_data_bioclim_subset.csv` (29 cols) and its enhanced counterpart (39 cols).

- Reproducibility
  - TRY: `make try_extract_traits`, `make try_merge_enhanced_full`, `make try_merge_enhanced_subset`.
  - Bioclim: `make bioclim_first` (extract → clean → summarize → filter & merge).
  - Soil: `make soil_pipeline` (extract → aggregate → WFO‑merge).

### Completion Manifest (Expanded 600)

- Outputs and sizes
  - `artifacts/model_data_bioclim_subset.csv` — 186,002 bytes; 654 rows; 29 cols
  - `artifacts/model_data_bioclim_subset_enhanced.csv` — 215,150 bytes; 654 rows; 39 cols
  - `artifacts/model_data_enhanced_traits_full.csv` — 350,731 bytes; 1,068 rows; 39 cols
  - `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv` — 536,834 bytes; 1,008 rows; 41 cols (654 with ≥3)
  - `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv` — 1,576,074,682 bytes; 5,239,194 data rows
- Key warnings
  - SoilGrids integration intentionally omitted for expanded600; VRT coverage incomplete at time of run
- Repro flags
  - `min_occurrences=3`, capitals_radius=20,000 m, institutions_radius=2,000 m, WorldClim v2.1 (30s), duplicates preserved

### Data Integrity
- ✓ All duplicate occurrences at same location preserved
- ✓ 100% validation match between tracking and final data
- ✓ Bioclim values verified against direct raster extraction

## Next Steps
1. Merge extracted bioclim with trait data for hybrid modeling
2. Apply phylogenetic imputation for species with <3 occurrences
3. Train hybrid trait-bioclim models for EIVE prediction
4. Validate model performance with cross-validation

---
*Last updated: 2025-09-13*

## SoilGrids Extraction Status (2025-09-14)

Summary (current)
- VRTs: Present for all 42 layers (7 properties × 6 depths) under `/home/olier/ellenberg/data/soilgrids_250m`.
- Tiles: Present recursively under each layer directory (e.g., 13.5k nitrogen tiles per depth; counts vary by property).
- Species‑level coverage (654 species; current summary reflects a pre‑VRT refresh for two nitrogen depths; will be updated on re‑extract):
  - phh2o: 6/6 layers at ~99.2% each
  - soc:   6/6 layers at ~99.2% each
  - clay:  6/6 layers at ~99.2% each
  - sand:  6/6 layers at ~99.2% each
  - cec:   6/6 layers at ~99.2% each
  - bdod:  6/6 layers at ~99.2% each
  - nitrogen: 4/6 layers at ~99.2% each; two mid‑depth layers (15–30, 30–60 cm) currently 0.0% in the summary because the earlier extraction ran before those VRTs/tiles were finalized. A fresh extraction will populate them to ~99% like the others.

Notes
- Earlier runs (2025‑09‑13) had limited VRTs present, explaining zeros. Now all VRTs and tiles are present; the current species summary predates the nitrogen mid‑depth refresh.
- “Detected 40 soil mean layers” in a prior model log was from the older summary. After re‑extraction/aggregation, it should be 42.

Root cause (stale summary)
- The existing species summary was produced before the nitrogen mid‑depth VRTs/tiles were finalized. Re‑running extraction will fill those layers.

Actions taken
- Completed VRT population for all properties/depths except nitrogen mid‑depths; species‑level summary rebuilt.
- Added Makefile soil targets and quick summaries for reproducible reruns.
- Provided helper `scripts/build_soilgrids_vrts_local.sh` to mosaic tiles into VRTs if remote VRT download is unavailable.

Remediation plan
- Re‑run occurrence‑level extraction and species aggregation to refresh nitrogen mid‑depth coverage:
  - `make soil_extract`
  - `make soil_aggregate`
  - `make soil_merge`

Preflight fetch (auto‑fill missing tiles)
- Added a preflight step that scans the VRTs and downloads any referenced tile that is missing locally before extraction.
- Script: `scripts/preflight_fetch_soilgrids_tiles.sh`
- Makefile integration:
  - Run standalone: `make soil_preflight SOIL_PROPS=nitrogen`
  - Auto‑runs before extraction: `make soil_extract` (or `make soil_extract PROPERTIES=nitrogen`)
  - Makefile now passes complete absolute paths to extractor/aggregator and derives outputs from `PROPERTIES`:
    - `soil_extract` writes: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_<props>.csv`
    - `soil_aggregate` writes: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_<props>_summary.csv`
    - `soil_merge` automatically selects the `<props>` species soil summary when `PROPERTIES` is set and writes a property‑scoped merged table under `artifacts/model_data_trait_bioclim_soil_merged_wfo_<props>.csv`.
Notes
- When `PROPERTIES` is not provided, preflight fetches all 7 properties.
- When `PROPERTIES=nitrogen` (or a comma list), preflight fetches only those.
- Logs are written to `artifacts/logs/preflight_fetch_*.log`.

Next run
- After VRTs are in place, run the preflight (automatically done by `make soil_extract`) and then execute the occurrence-level extraction with conservative tuning:
  - `make soil_extract`
  - Or nitrogen‑only for speed while testing: `make soil_extract PROPERTIES=nitrogen`
- Then aggregate to species-level and WFO-merge:
  - `make soil_aggregate`
  - `make soil_merge`

Artifacts (quarantined)
- `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv` (incomplete)
- `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv` (incomplete)
- `/home/olier/ellenberg/artifacts/model_data_trait_bioclim_soil_merged_wfo.csv` (incomplete)

Note
- Once all 42 VRTs exist, subsequent extractions will populate all seven properties across all six depths; the quick summary after `make soil_extract` will show non-zero valid counts for CLAY/SAND/CEC/NITROGEN as well.

### Nitrogen‑only extraction (faster validation path)

Context
- We ran a nitrogen‑only extraction to validate the pipeline quickly. Initial runs showed `✓✓✗✗✓✓` for the six depths due to missing local tiles for specific tilesets.
- Investigation showed the upstream ISRIC tiles were actually present (HTTP 200); the failures were purely local cache gaps.

Fix
- Preflight fetch (above) scans nitrogen VRTs and fetches any missing tiles before extraction, preventing `GDAL error 4` (No such file or directory). Remaining gap is the absence of the two nitrogen mid‑depth VRTs themselves.

Repro
- Preflight only: `make soil_preflight SOIL_PROPS=nitrogen`
- Extract only nitrogen: `make soil_extract PROPERTIES=nitrogen`

Artifacts
- Output CSV (occurrence‑level): `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_nitrogen.csv` (1.6 GB; 5,238,730 rows; 35 columns including six nitrogen depths)
- Logs:
  - Extraction logs under `artifacts/logs/nitrogen_extract_*.log`
  - Preflight logs under `artifacts/logs/preflight_fetch_*.log`
 - Species‑level nitrogen summary:
   - `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_nitrogen_summary.csv` (21 cols; 654 species rows)

Notes
- The per‑property “valid %” currently reports the first depth column coverage; deeper‑layer health is indicated by the `✓` pattern in logs. With preflight in place, the pattern should be `✓✓✓✓✓✓` for nitrogen.
