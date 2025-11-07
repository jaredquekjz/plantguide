# Data Preparation Verification (Bill Shipley)

**Purpose**: Independent R-based verification of Stage 1 data preparation pipeline
**Date**: 2025-11-07 (Updated)
**Environment**: Pure R, no Python/SQL required

---

## Bill's Verification Role

Bill should independently assess:

1. **Code logic review**: Examine R scripts in `src/Stage_1/bill_verification/` for methodological soundness, e.g.:
   - WorldFlora matching parameters (exact matching, no fuzzy)
   - Deduplication logic (rank-based tie-breaking)
   - Trait-richness filters (≥3 numeric traits per dataset)

2. **Ecological sanity checks**: Sample datasets to verify biological plausibility, e.g.:
   - EIVE index ranges (e.g., Nitrogen 1-9, Moisture 1-12)
   - TRY trait ranges (e.g., Plant height 0.01-100m, LMA 20-500 g/m²)
   - Taxonomic distribution (expect common genera: *Carex*, *Solanum*, *Eucalyptus*)
   - Match rates (Duke ~84%, EIVE ~95%, Mabberly ~99%)

---

## Workflow Overview

**Phase 0**: Run WorldFlora normalization (8 scripts) → Verify CSV checksums
**Phase 1**: Build enriched parquets → Verify data integrity → Compare checksums

---

## Required Source Data (Read-Only)

Bill's verification scripts read from these **13 canonical files**. All outputs write to `data/shipley_checks/` (isolated verification universe).

### 8 Dataset Parquets (Original Data)

1. **Duke Ethnobotany**: `data/stage1/duke_original.parquet` (58K rows, 1.2 MB)
2. **EIVE Ecological Indicators**: `data/stage1/eive_original.parquet` (21K rows, 1.5 MB)
3. **Mabberly Genera**: `data/stage1/mabberly_original.parquet` (13K rows, 531 KB)
4. **TRY Enhanced Traits**: `data/stage1/tryenhanced_species_original.parquet` (46K rows, 3.1 MB)
5. **AusTraits Taxa**: `data/stage1/austraits/taxa.parquet` (33K rows, 1.4 MB)
6. **GBIF Plant Occurrences**: `data/gbif/occurrence_plantae.parquet` (161K rows, 5.4 GB)
7. **GloBI Plant Interactions**: `data/stage1/globi_interactions_plants.parquet` (4.6M rows, 444 MB)
8. **TRY Selected Traits**: `data/stage1/try_selected_traits.parquet` (81K rows, 20 MB)

### 3 Environmental Occurrence Samples (Phase 2)

9. **WorldClim Occurrence Samples**: `data/stage1/worldclim_occ_samples.parquet` (31.5M rows, 3.6 GB, 63 variables)
10. **SoilGrids Occurrence Samples**: `data/stage1/soilgrids_occ_samples.parquet` (31.5M rows, 1.7 GB, 42 variables)
11. **Agroclim Occurrence Samples**: `data/stage1/agroclime_occ_samples.parquet` (31.5M rows, 3.0 GB, 51 variables)

### 1 WFO Taxonomy Backbone

12. **World Flora Online Backbone**: `data/classification.csv` (1.6M taxa, 570 MB, tab-separated, Latin-1 encoding)

### 1 GBIF WFO-Enriched File (Phase 1 Optional)

13. **GBIF with WFO IDs**: `data/gbif/occurrence_plantae_wfo.parquet` (49.7M rows, 5.4 GB)

**All scripts are read-only**: Canonical data is never modified. Bill's outputs write to `data/shipley_checks/`.

---

## Verification Scripts Overview

All scripts located in: `src/Stage_1/bill_verification/`

### Phase 0: Name Extraction (4 scripts)

1. **extract_all_names_bill.R** - Extract names from all 8 datasets
2. **extract_gbif_names_bill.R** - Extract GBIF occurrence names
3. **extract_globi_names_bill.R** - Extract GloBI interaction names
4. **extract_try_traits_names_bill.R** - Extract TRY traits names

### Phase 0: WorldFlora Matching (8 scripts)

5. **worldflora_duke_match_bill.R** - Match Duke ethnobotany names
6. **worldflora_eive_match_bill.R** - Match EIVE indicator names
7. **worldflora_mabberly_match_bill.R** - Match Mabberly genera names
8. **worldflora_tryenhanced_match_bill.R** - Match TRY Enhanced names
9. **worldflora_austraits_match_bill.R** - Match AusTraits names
10. **worldflora_gbif_match_bill.R** - Match GBIF occurrence names
11. **worldflora_globi_match_bill.R** - Match GloBI interaction names
12. **worldflora_try_traits_match_bill.R** - Match TRY traits names

### Phase 0: Checksum Verification (3 scripts)

13. **verify_worldflora_checksums_bill.R** - Verify CSV checksums
14. **compare_worldflora_csvs_bill.R** - Compare CSVs row-by-row
15. **compare_worldflora_checksums_bill.R** - Compare checksum files

### Phase 1: Core Data Integration (3 scripts)

16. **build_bill_enriched_parquets.R** - Build WFO-enriched parquets
17. **verify_stage1_integrity_bill.R** - Verify shortlist integrity
18. **add_gbif_counts_bill.R** - Add GBIF counts (optional)

### Phase 2: Environmental Aggregation (4 scripts)

19. **aggregate_env_summaries_bill.R** - Compute mean/stddev/min/max per species
20. **aggregate_env_quantiles_bill.R** - Compute q05/q50/q95/iqr per species (Type 1)
21. **verify_env_integrity_bill.R** - Verify against canonical outputs
22. **verify_env_quantiles_detailed.R** - Detailed quantile difference analysis

### Phase 3: Canonical Imputation Dataset (2 scripts)

23. **extract_phylo_eigenvectors_bill.R** - Extract 92 phylo eigenvectors from VCV matrix
24. **assemble_canonical_imputation_input_bill.R** - Assemble 268-column imputation dataset

**Total**: 24 R scripts for complete independent verification

---

## Phase 0: WFO Normalization

### Step 1: Extract Names from Datasets

# Extract distinct names from all 8 datasets (~1-2 minutes)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/extract_all_names_bill.R
```

**Output**: 8 name CSVs written to `data/shipley_checks/wfo_verification/`
- `duke_names_for_r.csv` (14,027 names)
- `eive_names_for_r.csv` (14,835 names)
- `mabberly_names_for_r.csv` (13,489 names)
- `tryenhanced_names_for_r.csv` (46,047 names)
- `austraits_names_for_r.csv` (33,370 names)
- `gbif_occurrence_names_for_r.tsv` (160,713 names)
- `globi_interactions_names_for_r.tsv` (74,002 names)
- `try_selected_traits_names_for_r.csv` (80,788 names)

### Step 2: Run WorldFlora Matching


# Run 8 WorldFlora matching scripts (~3-4 hours total)
# Tip: Run in parallel using nohup for efficiency

# Core datasets (8):
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_duke_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_eive_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_mabberly_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_tryenhanced_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_austraits_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_gbif_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_globi_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_try_traits_match_bill.R
```

**Note on "fuzzy matches" message**: Scripts show "Checking for fuzzy matches for X records" - this is misleading. With `Fuzzy=0`, NO string-distance fuzzy matching occurs (no Levenshtein tolerance). The message refers to fallback exact matching: if "Acacia albida subsp. X" fails, WorldFlora retries exact match on "Acacia albida", then "Acacia" against WFO backbone. Results show WHAT matched (subspecies/species/genus) - NOT a conversion to genus.

### Step 3: Verify WorldFlora Outputs (MD5 Checksums)

```bash
# MD5 checksum verification of WorldFlora CSVs (~5 seconds)
# Excludes OriSeq column (input row numbering) which differs due to extraction ordering
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_worldflora_checksums_bill.R
```

**Expected output**:
```
=== WorldFlora CSV Checksum Verification ===
(Excluding OriSeq column which reflects input ordering)

Mabberly        ✓ PASS (MD5: 9bddcab3)
Duke            ✓ PASS (MD5: 9361d55e)
EIVE            ✓ PASS (MD5: dbf7651f)
TRY Enhanced    ✓ PASS (MD5: 86b87648)
AusTraits       ✓ PASS (MD5: 5a1bdb71)
GBIF            ✓ PASS (MD5: c81d6452)
GloBI           ✓ PASS (MD5: f573ed29)
TRY traits      ✓ PASS (MD5: 49af4604)

=== Summary ===
✓ All WorldFlora CSV outputs verified (MD5 checksums match)
Note: OriSeq column excluded from comparison (reflects input row ordering)
```

**Success**: All 8 datasets show `✓ PASS` → Proceed to Phase 1

**Why exclude OriSeq?** R's extraction (`unique()`) produces different row ordering than the canonical DuckDB extraction (`SELECT DISTINCT`). This causes WorldFlora to assign different `OriSeq` values (sequential input row numbers). However, when OriSeq is excluded, the sorted CSVs produce **identical MD5 checksums**, proving that all WFO taxonomy matches are byte-for-byte identical.

---

## Phase 1: Data Integrity Check

### Step 1: Build Enriched Parquets

```bash
# Merge WorldFlora CSVs with original parquets (~60 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/build_bill_enriched_parquets.R
```

**Output location**: `data/shipley_checks/wfo_verification/*_worldflora_enriched.parquet`

**Datasets built (6):**
1. duke_worldflora_enriched.parquet (14,030 rows)
2. eive_worldflora_enriched.parquet (14,835 rows)
3. mabberly_worldflora_enriched.parquet (13,489 rows)
4. tryenhanced_worldflora_enriched.parquet (46,047 rows)
5. **austraits_traits_worldflora_enriched.parquet (1,798,215 rows)** - trait measurements + taxonomy
6. **try_selected_traits_worldflora_enriched.parquet (618,932 rows)** - categorical traits

**Note:** AusTraits traits parquet contains both trait measurements and WFO taxonomy (wfo_taxon_id, wfo_scientific_name), so a separate taxa parquet is not needed.

### Step 2: Verify Data Integrity

```bash
# Reconstruct master union and shortlist, compare to canonical (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_stage1_integrity_bill.R
```

**What it does**: Independently rebuilds master_taxa_union and stage1_shortlist_candidates from Bill's enriched parquets (using only original sources + Bill's WFO matching), then performs detailed verification:
- Builds from Bill's 7 enriched parquets (fully independent from canonical Python pipeline)
- Compares row counts, column schemas, WFO IDs, source coverage against canonical outputs
- Validates trait-richness filters (≥3 numeric traits per dataset)
- Checks dataset presence flags and qualification breakdown

**Independence guarantee**: Bill's pipeline uses ONLY:
- Original source parquets (common verified sources)
- Bill's independent WFO matching CSVs
- Bill's independently built enriched parquets
- NO canonical Python outputs are used as sources (only for final comparison)

### Expected Output

```
=== Stage 1 Data Integrity Check ===

PART 1: Building Master Taxa Union
Reading Bill's enriched parquet files...
  Duke: 10640 records
  EIVE: 12868 records
  Mabberly: 12664 records
  TRY Enhanced: 44266 records
  AusTraits: 28072 records
(Note: Reads from Bill's independently built enriched parquets in data/shipley_checks/wfo_verification/)

Combining sources...
  Total records before deduplication: 108510
Aggregating by wfo_taxon_id...
  Unique WFO taxa: 86592
  Expected: 86,592

PART 2: Building Shortlist Candidates
Applying trait-richness filters...
  Species with >=3 EIVE indices: 12599
  Species with >=3 TRY traits: 12655
  Species with >=3 AusTraits traits: 3849

Applying shortlist criteria...
  Shortlisted species: 24511
  Expected: 24,511

=== DETAILED VERIFICATION ===

1. Master Taxa Union
   Row counts match: TRUE
   Column names match: TRUE
   WFO IDs match: TRUE
   Sources match: TRUE

2. Shortlist Candidates
   Row counts match: TRUE
   Column names match: TRUE
   WFO IDs match: TRUE
   eive_numeric_count matches: TRUE
   try_numeric_count matches: TRUE
   austraits_numeric_count matches: TRUE

3. Binary File Checksums
   ✗ FAIL: Master union parquet files differ
   This may be due to minor encoding differences even if data matches
   ✗ FAIL: Shortlist parquet files differ
   This may be due to minor encoding differences even if data matches

=== Integrity Check Complete ===
```

### Interpreting Results

**Data Verification (Critical)**: All TRUE values in sections 1 & 2 → Data integrity verified ✓

**Binary Checksums (Expected to fail)**: Section 3 shows ✗ FAIL for parquet files. This is expected - R's `arrow` and Python's `pyarrow` produce different binary encodings. The data itself is identical (verified by sections 1 & 2).

---

### Step 3: Add GBIF Occurrence Counts 

```bash
# Add GBIF counts and create ≥30 subset (~30 seconds, uses Arrow streaming)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/add_gbif_counts_bill.R
```

**What it does**: 
- Counts GBIF occurrences by `wfo_taxon_id` using Arrow streaming (memory-efficient, no 5.4GB load)
- Merges counts with Bill's reconstructed shortlist
- Filters to ≥30 occurrences → Creates Bill's version of the reference shortlist (11,711 species)
- Compares against canonical `stage1_shortlist_with_gbif_ge30.parquet`

**Expected output**:

```
=== Phase 1 Step 3: GBIF Integration Verification (Optimized) ===

Step 1: Counting GBIF occurrences using Arrow compute engine...
  Unique WFO taxa with GBIF records: 144,655
  Total occurrences counted: 48,977,163
  Total georeferenced: 48,886,200

Step 2: Merging GBIF counts with shortlist...
  Species with GBIF records: 18,451
  Species with >=30 occurrences: 11,711

Step 3: Filtering to >=30 GBIF occurrences...
  ✓ PASS: Row count matches expected (11,711)

=== VERIFICATION AGAINST CANONICAL ===

1. Row counts match: TRUE
2. WFO IDs match: TRUE
3. Column names match: FALSE
   Only in canonical: legacy_wfo_ids
4. GBIF occurrence counts match: 11,711/11,711 (100%)
5. GBIF georeferenced counts match: 11,711/11,711 (100%)
6. Binary parquet checksums: ✗ FAIL (expected - R vs Python encoding)
```

**Note**: Column mismatch is benign - `legacy_wfo_ids` is a helper column tracking synonym history, not critical for verification.

---

## Phase 2: Environmental Data Verification 

**Purpose**: Independently verify that Bill's R-based environmental aggregations match canonical Python/DuckDB outputs.

**Prerequisites**:
- Phase 0 and Phase 1 must be complete
- Canonical environmental sampling must be complete (see `1.5_Environmental_Sampling_Workflows.md`)
- Requires 3 occurrence sample files: `worldclim_occ_samples.parquet`, `soilgrids_occ_samples.parquet`, `agroclime_occ_samples.parquet`

### Step 1: Aggregate Summary Statistics

```bash
# Compute per-species mean, stddev, min, max (pure R, ~5-10 minutes per dataset)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/aggregate_env_summaries_bill.R all
```

**What it does**: Reads canonical occurrence samples and computes species-level aggregations using pure R (`arrow` + `dplyr`). Equivalent to `aggregate_stage1_env_summaries.py`.

**Expected output**:
```
=== Environmental Summary Aggregation (Pure R) ===

=== Aggregating worldclim ===
  Found 63 environmental variables
  Reading occurrence samples...
  Computing per-species aggregations...
  Aggregated to 11,711 species
  ✓ Complete: worldclim_species_summary_R.parquet

=== Aggregating soilgrids ===
  Found 42 environmental variables
  Aggregated to 11,711 species
  ✓ Complete: soilgrids_species_summary_R.parquet

=== Aggregating agroclime ===
  Found 51 environmental variables
  Aggregated to 11,711 species
  ✓ Complete: agroclime_species_summary_R.parquet
```

### Step 2: Aggregate Quantile Statistics

```bash
# Compute per-species quantiles: q05, q50, q95, IQR (pure R, ~10-15 minutes per dataset)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/aggregate_env_quantiles_bill.R all
```

**What it does**: Computes species-level quantiles (5th, 50th, 95th percentiles, IQR) using R's `quantile()` and `IQR()` functions. Equivalent to DuckDB quantile script in `1.5_Environmental_Sampling_Workflows.md`.

**Expected output**:
```
=== Environmental Quantile Aggregation (Pure R) ===

=== Computing quantiles for worldclim ===
  Found 63 environmental variables
  Computing per-species quantiles...
  Computed quantiles for 11,711 species
  ✓ Complete: worldclim_species_quantiles_R.parquet

[Similar output for soilgrids and agroclime]
```

### Step 3: Verify Against Canonical Outputs

```bash
# Compare Bill's R aggregations vs canonical Python/DuckDB outputs (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_env_integrity_bill.R
```

**What it does**: Compares Bill's R-generated summaries and quantiles against canonical outputs:
- Row counts, WFO IDs, column schemas
- Numeric value matching (tolerance: 1e-6 for summaries, 1e-5 for quantiles)

**Expected output**:
```
=== Environmental Data Integrity Verification ===

PART 1: Summary Statistics (mean, stddev, min, max)

=== Verifying worldclim summaries ===
  Bill taxa:      11,711
  Canonical taxa: 11,711
  Row counts match: TRUE
  WFO IDs match: TRUE
  Column names match: TRUE
  Numeric values match: TRUE

[Similar for soilgrids and agroclime]

PART 2: Quantile Statistics (q05, q50, q95, iqr)

=== Verifying worldclim quantiles ===
  Bill taxa:      11,711
  Canonical taxa: 11,711
  Row counts match: TRUE
  WFO IDs match: TRUE
  Column names match: TRUE
  Numeric values match: TRUE

[Similar for soilgrids and agroclime]

=== SUMMARY ===

✓ ALL CHECKS PASSED
  Bill's R-generated environmental aggregations match canonical outputs
```

**Note on quantile algorithms**: Bill's R scripts use `quantile(..., type=1)` to match DuckDB's quantile method exactly (inverted empirical CDF). This achieves **perfect agreement** (0.000000 difference) across all species and variables. See `Quantile_Algorithm_Matching_Report.md` for technical details on why Type 1 was chosen over R's default Type 7.

---

## Phase 3: Canonical Imputation Dataset Preparation

**Purpose**: Build phylogenetic eigenvectors for 11,711-species shortlist to support canonical Perm 1/2/3 imputation datasets.

**Prerequisites**:
- Phase 1 must be complete (11,711-species shortlist established)
- WFO classification backbone: `data/classification.csv`
- GBOTB→WFO mapping: `data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet`

**Context**: After GBIF case-sensitivity bug fix (Nov 6-7), the shortlist expanded from 11,680 to 11,711 species (+31). The old phylogenetic tree (built Oct 27 for 11,676 species) had 287 species (2.5%) missing eigenvectors. Phase 3 rebuilds the tree to achieve 99.7% coverage.

---

### Step 1: Prepare Species List with Family

**Purpose**: Create species CSV with WFO family taxonomy required by V.PhyloMaker2

**Script**: Inline R (or extract to `prepare_species_list_bill.R` if reusable)

```bash
# Create species list with family column from WFO classification
cat > /tmp/create_species_list_11711.R << 'EOF'
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(data.table)
})

# Extract unique species from Bill's shortlist
shortlist <- read_parquet("data/shipley_checks/stage1_shortlist_with_gbif_ge30_bill.parquet")
species <- shortlist %>%
  select(wfo_taxon_id, wfo_scientific_name, genus) %>%
  distinct() %>%
  arrange(wfo_taxon_id)

# Join with WFO classification to get family
wfo <- fread("data/classification.csv",
             sep = "\t",
             encoding = "Latin-1",
             select = c("taxonID", "family"),
             data.table = FALSE)

result <- species %>%
  left_join(wfo %>% select(taxonID, family),
            by = c("wfo_taxon_id" = "taxonID")) %>%
  select(wfo_taxon_id, wfo_scientific_name, family, genus)

# Save
write_csv(result, "data/stage1/phlogeny/mixgb_shortlist_species_11711_20251107.csv")
cat("Species list created:", nrow(result), "species\n")
cat("Missing family:", sum(is.na(result$family)), "\n")
EOF

R_LIBS_USER=.Rlib /usr/bin/Rscript /tmp/create_species_list_11711.R
```

**Output**: `data/stage1/phlogeny/mixgb_shortlist_species_11711_20251107.csv` (11,711 species)

**Verification**:
- 11,711 species (10,887 species-level + 824 infraspecific)
- 100% family coverage (all species matched in WFO classification)

---

### Step 2: Build Phylogenetic Tree

**Purpose**: Generate phylogenetic tree for 11,711 species using V.PhyloMaker2

**Script**: `src/Stage_1/build_phylogeny_fixed_infraspecific.R` (existing canonical script)

```bash
# Build tree with proper infraspecific handling (~10-15 minutes)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/build_phylogeny_fixed_infraspecific.R \
    --species_csv=data/stage1/phlogeny/mixgb_shortlist_species_11711_20251107.csv \
    --gbotb_wfo_mapping=data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet \
    --output_newick=data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk \
    --output_mapping=data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv
```

**Methodology**:
1. Load species list (11,711 species)
2. Collapse infraspecific taxa to parent binomials (11,043 unique parents)
3. Build phylogenetic tree using V.PhyloMaker2 scenario S3
4. Create WFO→tree mapping (infraspecific taxa inherit parent's tree tip)

**Expected output**:
```
Input species: 11,711
  Species-level: 10,887
  Infraspecific: 824
  Unique parent binomials: 11,043

Tree built: 11,010 tips
  Species mapped: 11,673 (99.7%)
  Failed to place: 38 species (0.3%)

Outputs:
  ✓ Newick tree: data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk (559.7 KB)
  ✓ WFO→tree mapping: data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv (1.3 MB)
```

**Key improvements over old tree**:
- Old (Oct 27): 11,676 species input → 10,977 tips → 11,638 mapped (99.7%)
- New (Nov 7): 11,711 species input → 11,010 tips → 11,673 mapped (99.7%)
- Result: 35 additional species covered, only 38 unmapped (vs 287 before)

**Species that fail to place**: Primarily *Rumex* species where GBOTB lacks phylogenetic placement.

---

### Step 3: Extract Phylogenetic Eigenvectors

**Purpose**: Compute 92 phylogenetic eigenvectors from VCV matrix (broken stick rule, ~90% variance)

**Script**: `src/Stage_1/bill_verification/extract_phylo_eigenvectors_bill.R`

```bash
# Extract eigenvectors using full eigendecomposition (~10-20 minutes)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/extract_phylo_eigenvectors_bill.R
```

**Methodology**:
1. Load phylogenetic tree (11,010 tips)
2. Build variance-covariance matrix using `ape::vcv()` (11,010 × 11,010)
3. Perform full eigendecomposition using `base::eigen()` (symmetric = TRUE)
4. Apply broken stick rule to select significant eigenvectors
5. Map eigenvectors to all 11,711 species (infraspecific inherit parent values)

**Expected output**:
```
[1/7] Loading phylogenetic tree...
  ✓ Loaded tree with 11,010 tips

[2/7] Loading WFO→tree mapping...
  ✓ Loaded mapping with 11,711 rows
  ✓ Species with tree tips: 11,673 / 11,711 (99.7%)

[3/7] Building phylogenetic VCV matrix...
  ✓ VCV matrix dimensions: 11,010 × 11,010
  ✓ VCV matrix is symmetric and positive definite

[4/7] Performing full eigendecomposition...
  ✓ Extracted 11,010 eigenvalues/eigenvectors

[5/7] Applying broken stick rule...
  ✓ Selected 92 eigenvectors
  ✓ Variance explained: 89.8%

[6/7] Mapping eigenvectors to all species...
  ✓ Species with eigenvectors: 11,673 / 11,711 (99.7%)

[7/7] Writing output...
  ✓ Written: data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv
  ✓ File size: 11.2 MB
  ✓ Shape: 11,711 species × 93 columns (wfo_taxon_id + 92 eigenvectors)
```

**Coverage improvement**:
- Old tree: 11,424/11,676 species with eigenvectors (97.8%)
- New tree: 11,673/11,711 species with eigenvectors (99.7%)
- Missing: 38 species (couldn't be placed in phylogenetic tree)

**Output file**: `data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv`

**Columns**:
- `wfo_taxon_id`: WFO identifier
- `phylo_ev1` to `phylo_ev92`: Continuous phylogenetic eigenvectors

**Reference**: Moura et al. 2024, PLoS Biology - "A phylogeny-informed characterisation of global tetrapod traits addresses data gaps and biases" (DOI: 10.1371/journal.pbio.3002658)

---

### Step 4: Assemble Canonical Imputation Input

**Purpose:** Transform Bill's Phase 1/2/3 outputs into canonical 268-column imputation dataset

**Script:** `src/Stage_1/bill_verification/assemble_canonical_imputation_input_bill.R`

```bash
# Assemble canonical imputation input from Bill's verified components (~2 minutes)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/assemble_canonical_imputation_input_bill.R
```

**Methodology (10-step transformation):**
1. Load base shortlist (11,711 species → 2 IDs)
2. Extract environmental q50 features (156 columns from WorldClim + SoilGrids + Agroclim)
3. Extract TRY Enhanced traits (6 raw traits, convert to numeric, species-level median)
4. Extract AusTraits for SLA fallback (leaf_mass_per_area + LDMC + height + seed mass)
5. Compute canonical SLA waterfall + log transforms (anti-leakage: drop ALL raw traits)
6. Extract categorical traits (4 from TRY Enhanced, 3 from TRY Selected TraitIDs)
7. Extract EIVE indicators (5 columns)
8. Load phylogenetic eigenvectors (92 columns)
9. Merge all components (left joins on wfo_taxon_id)
10. Verify structure (11,711 × 268, no raw trait leakage) and write output

**Canonical SLA Waterfall Logic:**
```r
# Priority 1: TRY SLA (derived from LMA)
try_sla_mm2_mg = ifelse(try_lma_g_m2 > 0, 1000.0 / try_lma_g_m2, NA)

# Priority 2: AusTraits SLA (derived from LMA)
aust_sla_mm2_mg = ifelse(aust_lma_g_m2 > 0, 1000.0 / aust_lma_g_m2, NA)

# Canonical SLA (waterfall)
sla_mm2_mg = case_when(
  !is.na(try_sla_mm2_mg) ~ try_sla_mm2_mg,
  !is.na(aust_sla_mm2_mg) ~ aust_sla_mm2_mg,
  TRUE ~ NA_real_
)

# Log transform (anti-leakage: raw sla_mm2_mg is dropped from final output)
logSLA = ifelse(sla_mm2_mg > 0, log(sla_mm2_mg), NA)
```

**Expected output:**
```
========================================================================
SUCCESS: Canonical imputation input assembled
========================================================================

Output:
  File: data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv
  Shape: 11,711 species × 268 columns

Column breakdown:
  IDs: 2
  Categorical traits: 7
  Log transforms: 6
  Environmental q50: 156
  EIVE indicators: 5
  Phylo eigenvectors: 92
  Total: 268

Key coverage:
  logSLA: ~5,535 / 11,711 (47.3%)
  EIVE: ~6,277 / 11,711 (53.6%)
  Phylo: 11,673 / 11,711 (99.7%)
```

**Output file:** `data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv` (11,711 × 268, ~46 MB)

**Anti-leakage verification:** Script fails with error if ANY raw trait columns found in output (leaf_area_mm2, nmass_mg_g, ldmc_g_g, sla_mm2_mg, plant_height_m, seed_mass_mg, try_lma_g_m2, aust_lma_g_m2)

**Critical implementation note:** TRY Enhanced trait columns are stored as character type in parquet. Script includes explicit `as.numeric()` conversion before aggregation to ensure type consistency across species groups.

---

## Success Criteria

### Phase 0: WFO Normalization
- [ ] All 8 WorldFlora scripts run without errors
- [ ] All 8 CSV checksums show `✓ PASS`

### Phase 1: Data Integrity Checks (Core)
- [ ] Enriched parquets script completes successfully (Step 1)
- [ ] Verification script shows all TRUE in sections 1 & 2 (Step 2)
- [ ] Master union: 86,592 taxa
- [ ] Shortlist: 24,511 species
- [ ] Trait counts match: EIVE 12,599 | TRY 12,655 | AusTraits 3,849

**Note**: Section 3 binary checksums will show ✗ FAIL (expected - different binary encodings)

### Phase 1: GBIF Integration (Optional - Step 3)
- [ ] GBIF script completes successfully using Arrow streaming
- [ ] Species count: 11,711 with ≥30 GBIF occurrences
- [ ] WFO IDs match: TRUE (set equality - same species exist in both files)
- [ ] GBIF occurrence counts: 100% match per species (after joining by wfo_taxon_id)
- [ ] GBIF georeferenced counts: 100% match per species

**What "WFO IDs match" means**:
- ✓ Same 11,711 species (wfo_taxon_id) exist in both Bill's and canonical files
- ✓ For each species, GBIF counts match exactly (verified via inner join by wfo_taxon_id)
- ≠ Row-by-row positional matching (different SQL ORDER BY vs R arrange() may produce different row orders)
- **Verification approach**: Set equality + per-species count matching (sufficient for data integrity)

### Phase 2: Environmental Data (Optional)
- [ ] Summary aggregation script completes (Step 1)
- [ ] Quantile aggregation script completes (Step 2)
- [ ] Verification shows all TRUE for all 3 datasets (Step 3)
- [ ] All datasets: 11,711 species
- [ ] WorldClim: 63 variables | SoilGrids: 42 variables | Agroclim: 51 variables
- [ ] Row counts, WFO IDs, column schemas match: TRUE
- [ ] Summary statistics (mean/stddev/min/max) match: 0.000000 difference
- [ ] Quantile statistics (q05/q50/q95/iqr) match: 0.000000 difference

**Note**: Phase 2 verifies that Bill's pure R environmental aggregations match canonical Python/DuckDB outputs. R scripts use `type=1` quantiles to match DuckDB exactly, achieving **perfect 0.000000 agreement** (no tolerance needed).

### Phase 3: Canonical Imputation Dataset (Required for Imputation)
- [x] Species list created with family column (Step 1)
- [x] Species list: 11,711 species with 100% family coverage
- [x] Phylogenetic tree built successfully (Step 2)
- [x] Tree tips: 11,010 unique phylogenetic positions
- [x] Species mapped to tree: 11,673 / 11,711 (99.7%)
- [x] Eigenvector extraction completes (Step 3)
- [x] Eigenvectors selected: 92 (broken stick rule, ~90% variance)
- [x] Eigenvector coverage: 11,673 / 11,711 (99.7%)
- [x] Output file: `data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv`
- [x] Canonical imputation input assembled (Step 4)
- [x] Output: 11,711 species × 268 columns
- [x] Anti-leakage verified: No raw trait columns present
- [x] Output file: `data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv`
- [x] **Verification: Perfect R/Python agreement** (see 1.7b_Bill_Verification_11711.md)
  - Non-phylo components: Perfect match (max diff: 2.84e-14)
  - Phylo eigenvectors: Independent extraction, correlation > 0.9999
  - Data provenance: All sources verified as independent

**Note**: Phase 3 resolves the missing eigenvector issue. Old tree (Oct 27) had 287 species (2.5%) missing eigenvectors due to shortlist expansion after GBIF bug fix. New tree (Nov 7) covers 99.7% of species (only 38 unmapped, primarily *Rumex* species).

### Bill's Independent Assessment
- [ ] Code logic review: Examine deduplication, trait filters, WorldFlora parameters
- [ ] Ecological sanity checks: Sample datasets for biological plausibility
- [ ] Report findings: Any ✗ FAIL messages, row count mismatches, or methodological concerns

**If all core data verification checks pass**: Stage 1 pipeline is independently verified ✓

---

## ANNEX: Optional: Perfect Binary Checksum Parity

**Context**: All data verification shows TRUE (data is identical), but binary parquet checksums differ due to R vs Python encoding. To achieve byte-for-byte binary parity:

### Example: EIVE Dataset

```python
# Use DuckDB to re-export Bill's parquet with canonical format
import duckdb
con = duckdb.connect()

# Read Bill's R-generated parquet and write in Python format
con.execute("""
    COPY (SELECT * FROM read_parquet('data/shipley_checks/wfo_verification/eive_worldflora_enriched.parquet'))
    TO 'data/stage1/eive_worldflora_enriched_bill_canonical.parquet'
    (FORMAT PARQUET, COMPRESSION SNAPPY)
""")
```

```bash
# Verify binary checksums now match
md5sum data/stage1/eive_worldflora_enriched.parquet \
       data/stage1/eive_worldflora_enriched_bill_canonical.parquet
```

**Expected**: Both parquets produce identical MD5 checksums. Apply same approach to other datasets if desired.

---

## File Locations

**Bill's scripts**: `src/Stage_1/bill_verification/`
**Bill's outputs**:
- WFO verification: `data/shipley_checks/wfo_verification/`
- Environmental verification: `data/shipley_checks/*_species_{summary,quantiles}_R.parquet`

**Canonical inputs** (read-only):
- Dataset parquets: `data/stage1/*_original.parquet`
- WFO backbone: `data/classification.csv`
- Environmental samples: `data/stage1/{worldclim,soilgrids,agroclime}_occ_samples.parquet`

**Canonical outputs** (for comparison):
- Shortlists: `data/stage1/master_taxa_union.parquet`, `data/stage1/stage1_shortlist_candidates.parquet`
- Environmental: `data/stage1/{worldclim,soilgrids,agroclime}_species_{summary,quantiles}.parquet`

---

## System Requirements

```r
# Install once (if not already available)
install.packages(c("arrow", "dplyr", "data.table", "WorldFlora"))
```

**R environment**: Use `.Rlib` custom library via `R_LIBS_USER=.Rlib`
**R executable**: System R at `/usr/bin/Rscript`
**WFO backbone**: `data/classification.csv` (1.6M taxa, tab-separated, Latin-1 encoding)
