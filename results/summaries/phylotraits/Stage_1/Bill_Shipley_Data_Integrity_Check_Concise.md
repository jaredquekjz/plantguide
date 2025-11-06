# Stage 1 Data Integrity Check for Bill Shipley

**Purpose**: Independent R-based verification of Stage 1 pipeline integrity
**Date**: 2025-11-06
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

Bill's verification scripts read from these **9 canonical files only**. All outputs write to `data/shipley_checks/` (isolated verification universe).

### 8 Dataset Parquets (Original Data)

1. **Duke Ethnobotany**: `data/stage1/duke_original.parquet` (58K rows, 1.2 MB)
2. **EIVE Ecological Indicators**: `data/stage1/eive_original.parquet` (21K rows, 1.5 MB)
3. **Mabberly Genera**: `data/stage1/mabberly_original.parquet` (13K rows, 531 KB)
4. **TRY Enhanced Traits**: `data/stage1/tryenhanced_species_original.parquet` (46K rows, 3.1 MB)
5. **AusTraits Taxa**: `data/stage1/austraits/taxa.parquet` (33K rows, 1.4 MB)
6. **GBIF Plant Occurrences**: `data/gbif/occurrence_plantae.parquet` (161K rows, 5.4 GB)
7. **GloBI Plant Interactions**: `data/stage1/globi_interactions_plants.parquet` (4.6M rows, 444 MB)
8. **TRY Selected Traits**: `data/stage1/try_selected_traits.parquet` (81K rows, 20 MB)

### 1 WFO Taxonomy Backbone

9. **World Flora Online Backbone**: `data/classification.csv` (1.6M taxa, 570 MB, tab-separated, Latin-1 encoding)

**All scripts are read-only**: Canonical data is never modified. All Bill's outputs write to `data/shipley_checks/wfo_verification/`.

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
# Merge WorldFlora CSVs with original parquets (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/build_bill_enriched_parquets.R
```

**Output location**: `data/shipley_checks/wfo_verification/*_enriched_bill.parquet`

### Step 2: Verify Data Integrity

```bash
# Reconstruct master union and shortlist, compare to canonical (~15-20 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_stage1_integrity_bill.R | tee logs/bill_phase1_verification.log
```

### Expected Output

```
=== Stage 1 Data Integrity Check ===

PART 1: Building Master Taxa Union
  Duke: 10640 records
  EIVE: 12879 records
  Mabberly: 12664 records
  TRY Enhanced: 44286 records
  AusTraits: 28072 records

Unique WFO taxa: 86,815 ✓

PART 2: Building Shortlist Candidates
Shortlisted species: 24,542 ✓

=== CHECKSUM VERIFICATION ===
  ✓ PASS: Master union checksums match
  ✓ PASS: Shortlist checksums match

=== Integrity Check Complete ===
```

**Success**: Both checksums show **✓ PASS**

---

## Success Criteria 

### Phase 0: WFO Normalization
- [ ] All 5 WorldFlora scripts run without errors
- [ ] All 5 CSV checksums match expected values

### Phase 1: Data Integrity
- [ ] Enriched parquets script completes successfully
- [ ] Master union: 86,815 taxa
- [ ] Shortlist: 24,542 species
- [ ] Both verification checksums show **✓ PASS**

### Deliverable
- [ ] Report any ✗ FAIL messages or row count mismatches
- [ ] Code and methodology review notes: scripting or methodology concerns and improvements
- [ ] Ecological sanity check results: any biological anomalies

**If all checkboxes pass**: Stage 1 pipeline is independently verified. ✓

---

## File Locations

**Bill's scripts**: `src/Stage_1/bill_verification/`
**Bill's outputs**: `data/shipley_checks/wfo_verification/`
**Canonical inputs** (read-only): `data/stage1/*_original.parquet`, `data/classification.csv`
**Canonical outputs** (for comparison): `data/stage1/master_taxa_union.parquet`, `data/stage1/stage1_shortlist_candidates.parquet`

---

## System Requirements

```r
# Install once (if not already available)
install.packages(c("arrow", "dplyr", "data.table", "WorldFlora"))
```

**R environment**: Use `.Rlib` custom library via `R_LIBS_USER=.Rlib`
**R executable**: System R at `/usr/bin/Rscript`
**WFO backbone**: `data/classification.csv` (1.6M taxa, tab-separated, Latin-1 encoding)
