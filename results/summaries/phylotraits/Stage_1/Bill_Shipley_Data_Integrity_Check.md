# Stage 1 Data Integrity Check for Bill Shipley

Date: 2025-11-06
Purpose: Independent R-based verification of Stage 1 data pipeline integrity
Target reviewer: Prof. Bill Shipley (R environment)

## Overview

This document provides an 80/20 data integrity check of the Stage 1 pipeline using pure R code. The verification proceeds in two phases:

**Phase 0: WFO Normalization Verification** (prequel)
- Verify WorldFlora taxonomy matching produces identical outputs
- Uses existing R WorldFlora scripts (no Python required)
- Validates 5 datasets: Duke, EIVE, Mabberly, TRY Enhanced, AusTraits

**Phase 1: Data Integrity Check** (main verification)
- Independently reconstruct master shortlist from normalized parquet files
- Verify results match Python-generated versions via checksum comparison
- Validates full pipeline: union building, trait filtering, GBIF coverage

## Phase 0: WFO Normalization Verification

### Purpose

Verify that Bill's execution of the WorldFlora matching scripts produces CSV outputs byte-for-byte identical to the canonical versions. This confirms the taxonomy normalization step is reproducible.

### Input/Output Files

| Dataset | Original (input) | WorldFlora CSV (Bill's output) | Bill's WorldFlora script |
|---------|------------------|-------------------------|-------------------|
| Duke | `data/stage1/duke_original.parquet` | `data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv` | `src/Stage_1/bill_verification/worldflora_duke_match_bill.R` |
| EIVE | `data/stage1/eive_original.parquet` | `data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv` | `src/Stage_1/bill_verification/worldflora_eive_match_bill.R` |
| Mabberly | `data/stage1/mabberly_original.parquet` | `data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv` | `src/Stage_1/bill_verification/worldflora_mabberly_match_bill.R` |
| TRY Enhanced | `data/stage1/tryenhanced_species_original.parquet` | `data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv` | `src/Stage_1/bill_verification/worldflora_tryenhanced_match_bill.R` |
| AusTraits | `data/stage1/austraits/taxa.parquet` | `data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv` | `src/Stage_1/bill_verification/worldflora_austraits_match_bill.R` |

**Note**: The WorldFlora scripts produce CSV files containing the raw WFO matching results. These CSV files are the gold-standard outputs for Phase 0 verification.

### Running WorldFlora Matching Scripts

Bill should run Bill-specific WorldFlora scripts that are identical to the canonical versions except they output directly to `data/shipley_checks/wfo_verification/` instead of `data/stage1/`.

**Important**: These scripts require the WFO backbone file: `data/classification.csv` (tab-separated, Latin-1 encoding)

**Run Bill's WorldFlora scripts:**

```bash
cd /home/olier/ellenberg

# Run all 5 Bill-specific WorldFlora matching scripts
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_duke_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_eive_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_mabberly_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_tryenhanced_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_austraits_match_bill.R
```

**Note**: Each script takes 5-25 minutes depending on dataset size. Total runtime: ~1-2 hours for all 5 datasets. These scripts automatically create the output directory and write results to `data/shipley_checks/wfo_verification/`.

### Verifying WFO Normalization Outputs

After running Bill's WorldFlora scripts, verify the CSV outputs match the canonical checksums:

```bash
cd /home/olier/ellenberg

# Verify Duke
md5sum data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv
# Expected: 481806e6c81ebb826475f23273eca17e

# Verify EIVE
md5sum data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv
# Expected: fae234cfd05150f4efefc66837d1a1d4

# Verify Mabberly
md5sum data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv
# Expected: 0c82b665f9c66716c2f1ec9eafc4431d

# Verify TRY Enhanced
md5sum data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv
# Expected: ce0f457c56120c8070f34d65f53af4b1

# Verify AusTraits
md5sum data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv
# Expected: ebed20d3f33427b1f29f060309f5959d
```

**All-in-one verification**:
```bash
md5sum data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv
```

### Phase 0 Success Criteria

- ✓ All 5 WorldFlora scripts run without errors
- ✓ Each CSV checksum matches the expected value exactly
- ✓ Total verification time: ~5 seconds (checksum computation only)

**If all 5 CSV checksums match**, Phase 0 is COMPLETE and Bill can proceed to Phase 1 (main data integrity check).

### Phase 0 Round 1 Results

**Date**: 2025-11-06
**System**: Development workstation (Ubuntu 22.04, R 4.x)
**Runtime**: WorldFlora matching ~45 minutes (all 5 datasets), verification ~5 seconds

All WorldFlora CSV files produced **PERFECT checksum matches**:

| Dataset | Canonical Checksum | Bill Checksum | Status | Rows |
|---------|-------------------|---------------|--------|------|
| Duke | `481806e6c81ebb826475f23273eca17e` | `481806e6c81ebb826475f23273eca17e` | ✓ PASS | 17,341 |
| EIVE | `fae234cfd05150f4efefc66837d1a1d4` | `fae234cfd05150f4efefc66837d1a1d4` | ✓ PASS | 19,291 |
| Mabberly | `0c82b665f9c66716c2f1ec9eafc4431d` | `0c82b665f9c66716c2f1ec9eafc4431d` | ✓ PASS | 14,487 |
| TRY Enhanced | `ce0f457c56120c8070f34d65f53af4b1` | `ce0f457c56120c8070f34d65f53af4b1` | ✓ PASS | 53,852 |
| AusTraits | `ebed20d3f33427b1f29f060309f5959d` | `ebed20d3f33427b1f29f060309f5959d` | ✓ PASS | 35,974 |

**Verification status**: ✓ **PHASE 0 COMPLETE** - All 5 datasets show byte-for-byte identical WorldFlora CSV outputs.

**Match statistics** (from CSV files):
```
Duke:         17,341 total rows, 15,136 with valid taxonID (84.3% matched)
EIVE:         19,291 total rows, 18,597 with valid taxonID (95.3% matched)
Mabberly:     14,487 total rows, 14,418 with valid taxonID (99.5% matched)
TRY Enhanced: 53,852 total rows, 52,999 with valid taxonID (98.15% matched)
AusTraits:    35,974 total rows, 34,186 with valid taxonID (94.6% matched)
```

These match rates align with the canonical pipeline documentation (see `1.2_WFO_Normalisation_Verification.md`).

**Conclusion**: The WorldFlora taxonomy normalization is 100% reproducible. Bill's R scripts produce byte-for-byte identical outputs to the canonical process.

---

## Phase 1: Data Integrity Check

### Purpose

Independently build WFO-enriched parquets, then reconstruct the master taxa union and trait-rich shortlist. Verify results match the Python-generated versions.

### System Requirements

```r
# Install required packages (run once)
install.packages("arrow")      # Fast parquet I/O
install.packages("dplyr")      # Data manipulation
install.packages("digest")     # MD5 checksums
install.packages("data.table") # Fast joins and aggregation
```

### Step 1: Build WFO-Enriched Parquets

After Phase 0 WorldFlora CSV verification passes, Bill needs to merge the WorldFlora results back into the original parquets to create enriched versions.

**Run the enriched parquet builder:**

```bash
cd /home/olier/ellenberg
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/build_bill_enriched_parquets.R
```

**Expected runtime**: ~30 seconds

This script will create Bill's WFO-enriched parquets:

```
data/shipley_checks/wfo_verification/duke_worldflora_enriched_bill.parquet          # 14,030 species
data/shipley_checks/wfo_verification/eive_worldflora_enriched_bill.parquet          # 14,835 species
data/shipley_checks/wfo_verification/mabberly_worldflora_enriched_bill.parquet      # 13,489 genera
data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched_bill.parquet   # 46,047 species
data/shipley_checks/wfo_verification/austraits_worldflora_enriched_bill.parquet     # 33,370 taxa
```

All files will be WorldFlora-enriched (WFO taxonomy backbone) with standardized `wfo_taxon_id` identifiers.

### Step 2: Verify Data Integrity

Bill will reconstruct:
- `master_taxa_union.parquet` (86,815 unique WFO taxa from 5 sources)
- `stage1_shortlist_candidates.parquet` (24,542 trait-rich species)

And verify these match the Python-generated versions using MD5 checksums.

**Run Bill's integrity verification script:**

```bash
cd /home/olier/ellenberg
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_stage1_integrity_bill.R | tee logs/bill_phase1_verification.log
```

**Expected runtime**: ~15-20 seconds

The Bill-specific verification script reads enriched parquets from `data/shipley_checks/wfo_verification/` and compares results against the canonical Python-generated outputs.

**What the script does:**
1. Builds master taxa union from Bill's 5 WFO-enriched parquets
2. Applies trait-richness filters to create shortlist candidates
3. Compares Bill's outputs against canonical versions via MD5 checksums
4. Writes verification results to `data/shipley_checks/`

**Expected console output:**
```
=== Stage 1 Data Integrity Check ===
Starting: 2025-11-06 11:30:00

PART 1: Building Master Taxa Union
Reading raw parquet files...
  Duke: 10640 records
  EIVE: 12879 records
  Mabberly: 12664 records
  TRY Enhanced: 44286 records
  AusTraits: 28072 records

Unique WFO taxa: 86,815
Expected: 86,815

PART 2: Building Shortlist Candidates
Shortlisted species: 24,542
Expected: 24,542

=== CHECKSUM VERIFICATION ===
  ✓ PASS: Master union checksums match
  ✓ PASS: Shortlist checksums match

=== Integrity Check Complete ===
```

### Phase 1 Success Criteria

- ✓ Enriched parquets created successfully from Bill's WorldFlora CSVs
- ✓ Master taxa union: 86,815 unique WFO taxa
- ✓ Shortlist candidates: 24,542 trait-rich species
- ✓ CSV checksums match canonical versions exactly
- ✓ All column values show 100% match in verification output

**If all checksums match**, Phase 1 is COMPLETE and the entire Stage 1 pipeline has been independently verified.

---

## Data Sanity Checks (Optional)

After running the verification script, Bill can perform optional ecological sanity checks in R:

```r
# Load Bill's generated shortlist
shortlist <- read_parquet("data/shipley_checks/master_taxa_union_R.parquet")

# 1. Check EIVE index ranges (should be 1-9 or 1-12 depending on indicator)
eive <- read_parquet("data/shipley_checks/wfo_verification/eive_worldflora_enriched_bill.parquet")
summary(as.numeric(eive$`EIVEres-M`))  # Moisture: expect 1-12
summary(as.numeric(eive$`EIVEres-N`))  # Nitrogen: expect 1-9
summary(as.numeric(eive$`EIVEres-L`))  # Light: expect 1-9

# 2. Check TRY trait value ranges
try_data <- read_parquet("data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched_bill.parquet")
summary(as.numeric(try_data$`Plant height (m)`))        # Expect: 0.01-100 m
summary(as.numeric(try_data$`Leaf area (mm2)`))         # Expect: 1-500,000 mm²
summary(as.numeric(try_data$`LMA (g/m2)`))              # Expect: 20-500 g/m²

# 3. Check for duplicates
sum(duplicated(shortlist$wfo_taxon_id))  # Should be 0

# 4. Check taxonomic distribution
head(sort(table(gsub(" .*", "", shortlist$wfo_scientific_name)), decreasing = TRUE), 20)
# Should see common genera: Carex, Solanum, Eucalyptus, Acacia, etc.
```

---

## Methodological Notes

### Data Structure
All datasets use WFO (World Flora Online) taxonomic backbone. The `wfo_taxon_id` field provides the authoritative link across all sources. WorldFlora matching was performed using the R `WorldFlora` package with zero fuzzy tolerance.

### Trait Richness Criteria
A species qualifies for the shortlist if it meets ANY of:
1. ≥3 numeric EIVE indices (M, N, R, L, T)
2. ≥3 numeric TRY Enhanced traits (leaf area, Nmass, LMA, height, diaspore mass, wood density, LDMC, leaf thickness)
3. ≥3 numeric AusTraits overlap traits (same as TRY but from Australian flora)

### Deduplication Strategy
When a species appears in multiple sources (e.g., both EIVE and TRY), the union retains:
- First non-null scientific name
- Comma-separated list of all contributing sources
- Binary flags for each source's presence

This preserves full provenance without double-counting species.

## Round 1: Initial Verification Results (Local Testing)

**Verification stage**: Round 1 (script development and local testing)
**Date**: 2025-11-06
**System**: Local workstation (Ubuntu 22.04, R 4.x with .Rlib, system R at /usr/bin/Rscript)
**Runtime**: 15 seconds

### Execution Summary

The R-based integrity check completed successfully with the following results:

#### Part 1: Master Taxa Union
- **R-generated unique WFO taxa**: 86,815 ✓
- **Python-generated unique WFO taxa**: 86,815 ✓
- **Row count match**: PASS
- **All column values match**: PASS

Source coverage verification:
```
Duke:         10,640 species
EIVE:         12,879 species
Mabberly:     12,664 genera
TRY Enhanced: 44,286 species
AusTraits:    28,072 taxa
```

All source counts match expected values from documentation.

#### Part 2: Shortlist Candidates
- **R-generated shortlist**: 24,542 species ✓
- **Python-generated shortlist**: 24,542 species ✓
- **Row count match**: PASS
- **All column values match**: PASS

Qualification breakdown:
```
Via EIVE (≥3 indices):     12,610 species
Via TRY (≥3 traits):       12,658 species
Via AusTraits (≥3 traits):  3,849 species
```

All qualification counts match documentation.

### Data Integrity Assessment

**Column-by-column verification**: PASS ✓
```
Master Taxa Union (9 columns):
  ✓ wfo_taxon_id: 100% match
  ✓ wfo_scientific_name: 100% match
  ✓ sources: 100% match
  ✓ source_count: 100% match
  ✓ in_duke: 100% match
  ✓ in_eive: 100% match
  ✓ in_mabberly: 100% match
  ✓ in_try_enhanced: 100% match
  ✓ in_austraits: 100% match

Shortlist Candidates (14 columns):
  ✓ wfo_taxon_id: 100% match
  ✓ canonical_name: 100% match
  ✓ legacy_wfo_ids: 100% match
  ✓ in_eive: 100% match
  ✓ in_try_enhanced: 100% match
  ✓ in_duke: 100% match
  ✓ in_austraits: 100% match
  ✓ eive_numeric_count: 100% match
  ✓ try_numeric_count: 100% match
  ✓ austraits_numeric_count: 100% match
  ✓ qualifies_via_eive: 100% match
  ✓ qualifies_via_try: 100% match
  ✓ qualifies_via_austraits: 100% match
  ✓ shortlist_flag: 100% match
```

**CSV checksum verification**: PASS ✓
```
Master Taxa Union:
  R CSV MD5:      99791672086b9248902da19b53978e93
  Python CSV MD5: 99791672086b9248902da19b53978e93
  Status: IDENTICAL ✓

Shortlist Candidates:
  R CSV MD5:      c82881a07184905f66bad44568e0c60e
  Python CSV MD5: c82881a07184905f66bad44568e0c60e
  Status: IDENTICAL ✓
```

**Parquet binary checksum**: Different (expected, non-critical)
- Parquet files contain metadata (creation timestamp, Arrow library version)
- This metadata differs between R and Python Arrow implementations
- **Important**: CSV exports are byte-for-byte identical, confirming data integrity

### Performance Notes

R implementation using `arrow` package achieved:
- **15 seconds** total runtime for full pipeline
- Comparable efficiency to DuckDB-based Python approach
- Memory-efficient parquet reading via Apache Arrow C++ library
- Suitable for independent verification by R-only users

### Round 1 Conclusion

✓ **ROUND 1 VERIFICATION PASSED**: The R-based reconstruction achieved 100% data identity with the Python pipeline.

Evidence:
1. All 86,815 master union rows match exactly across all 9 columns
2. All 24,542 shortlist rows match exactly across all 14 columns
3. CSV file MD5 checksums are byte-for-byte identical
4. All trait counts and qualification logic replicated correctly

The pipeline is fully reproducible across R and Python environments. Parquet metadata differences are cosmetic and do not affect data integrity.

**Round 1 assessment**: The R script successfully replicates the Python pipeline on the development machine.

## Round 2: Independent Verification (Bill Shipley)

**Purpose**: Confirm the complete Stage 1 pipeline is reproducible on Bill's machine after cloning the repository.

### Phase 0 Tasks (WFO Normalization)

1. **Clone repository** and verify original parquet files:
   ```bash
   git clone <repository-url>
   cd ellenberg
   ls data/stage1/*_original.parquet  # Should see 4 files
   ls data/stage1/austraits/taxa.parquet  # AusTraits original
   ```

2. **Run WorldFlora matching scripts** (5 datasets, ~1-2 hours total):
   ```bash
   R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_duke_match.R
   R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_eive_match.R
   R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_mabberly_match.R
   R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_tryenhanced_match.R
   R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_austraits_match.R
   ```

3. **Verify WFO normalization CSV outputs**:
   ```bash
   # Check all 5 CSV checksums
   md5sum data/stage1/duke_wfo_worldflora.csv \
          data/stage1/eive_wfo_worldflora.csv \
          data/stage1/mabberly_wfo_worldflora.csv \
          data/stage1/tryenhanced_wfo_worldflora.csv \
          data/stage1/austraits/austraits_wfo_worldflora.csv

   # Expected checksums:
   # Duke:         481806e6c81ebb826475f23273eca17e
   # EIVE:         fae234cfd05150f4efefc66837d1a1d4
   # Mabberly:     0c82b665f9c66716c2f1ec9eafc4431d
   # TRY Enhanced: ce0f457c56120c8070f34d65f53af4b1
   # AusTraits:    ebed20d3f33427b1f29f060309f5959d
   ```
   Expected: All 5 checksums match exactly

### Phase 1 Tasks (Data Integrity)

4. **Run main integrity verification script**:
   ```bash
   R_LIBS_USER=.Rlib Rscript src/Stage_1/verify_stage1_integrity.R | tee logs/bill_shipley_round2.log
   ```

5. **Check key results** in the log output:
   - Master union: 86,815 taxa ✓
   - Shortlist: 24,542 species ✓
   - CSV checksums match ✓
   - Look for: "✓ PASS" messages in "DETAILED VERIFICATION" section

6. **Verify CSV checksums** (gold standard):
   ```bash
   md5sum data/shipley_checks/master_taxa_union_R.csv
   md5sum data/shipley_checks/master_taxa_union_PY.csv
   # Should both show: 99791672086b9248902da19b53978e93

   md5sum data/shipley_checks/stage1_shortlist_candidates_R.csv
   md5sum data/shipley_checks/stage1_shortlist_candidates_PY.csv
   # Should both show: c82881a07184905f66bad44568e0c60e
   ```

7. **Perform ecological sanity checks** (optional):
   ```r
   library(arrow)

   # Load R-generated shortlist
   shortlist <- read_parquet("data/shipley_checks/stage1_shortlist_candidates_R.parquet")

   # Check EIVE index ranges (should be 1-9 or 1-12)
   eive <- read_parquet("data/stage1/eive_worldflora_enriched.parquet")
   summary(as.numeric(eive$`EIVEres-N`))  # Nitrogen: expect 1-9

   # Check TRY trait value ranges
   try_data <- read_parquet("data/stage1/tryenhanced_worldflora_enriched.parquet")
   summary(as.numeric(try_data$`Plant height (m)`))  # Expect: 0.01-100 m

   # Check for duplicates (should be 0)
   sum(duplicated(shortlist$wfo_taxon_id))

   # Check taxonomic distribution
   head(sort(table(gsub(" .*", "", shortlist$canonical_name)), decreasing = TRUE), 20)
   # Should see: Carex, Solanum, Eucalyptus, Acacia, etc.
   ```

### Round 2 Success Criteria

**Phase 0 (WFO Normalization)**:
- ✓ All 5 WorldFlora matching scripts complete without errors
- ✓ All 5 WorldFlora CSV files have checksums matching the canonical versions
- ✓ Verification takes ~5 seconds (simple checksum computation)

**Phase 1 (Data Integrity)**:
- ✓ Main verification script completes in 15-20 seconds
- ✓ Row counts match exactly (86,815 and 24,542)
- ✓ CSV MD5 checksums are identical
- ✓ All column values show 100% match in verification output
- ✓ Ecological sanity checks pass (trait value ranges are plausible)

### Expected Round 2 Deliverable

Bill should report:
- **Phase 0 results**:
  - ✓/✗ WorldFlora script execution status (all 5 datasets)
  - ✓/✗ WorldFlora CSV checksum matches (all 5 files)
  - Runtime for each dataset (~5-25 minutes per dataset)
- **Phase 1 results**:
  - ✓/✗ Main integrity script execution status
  - ✓/✗ CSV checksum verification results
  - ✓/✗ Any data quality concerns from ecological sanity checks
- **System info**:
  - Platform details (OS, R version) for reproducibility documentation

**Note**: If Round 2 verification passes both phases, this confirms:
1. The WorldFlora taxonomy normalization is reproducible (Phase 0)
2. The complete Stage 1 pipeline is independently reproducible (Phase 1)
3. Ecologists can verify the pipeline using only R, without Python or SQL expertise


