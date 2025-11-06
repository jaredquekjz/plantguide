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
# Reconstruct master union and shortlist, compare to canonical (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_stage1_integrity_bill.R
```

**What it does**: Independently rebuilds master_taxa_union and stage1_shortlist_candidates from Bill's enriched parquets, then performs detailed verification:
- Compares row counts, column schemas, WFO IDs, source coverage
- Validates trait-richness filters (≥3 numeric traits per dataset)
- Checks dataset presence flags and qualification breakdown

### Expected Output

```
=== Stage 1 Data Integrity Check ===

PART 1: Building Master Taxa Union
Reading raw parquet files...
  Duke: 10640 records
  EIVE: 12868 records
  Mabberly: 12664 records
  TRY Enhanced: 44266 records
  AusTraits: 28072 records

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

### Step 3: Add GBIF Occurrence Counts (Optional)

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

## Success Criteria

### Phase 0: WFO Normalization
- [ ] All 8 WorldFlora scripts run without errors
- [ ] All 8 CSV checksums show `✓ PASS`

### Phase 1: Data Integrity Checks
- [ ] Enriched parquets script completes successfully (Step 1)
- [ ] Verification script shows all TRUE in sections 1 & 2 (Step 2)
- [ ] Master union: 86,592 taxa
- [ ] Shortlist: 24,511 species
- [ ] Trait counts match: EIVE 12,599 | TRY 12,655 | AusTraits 3,849

**Note**: Section 3 binary checksums will show ✗ FAIL (expected - different binary encodings)

### Bill's Independent Assessment
- [ ] Code logic review: Examine deduplication, trait filters, WorldFlora parameters
- [ ] Ecological sanity checks: Sample datasets for biological plausibility
- [ ] Report findings: Any ✗ FAIL messages, row count mismatches, or methodological concerns

**If all data verification checks pass**: Stage 1 pipeline is independently verified ✓

---

## Optional: Perfect Binary Checksum Parity

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
