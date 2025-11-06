# Stage 1 Data Integrity Check for Bill Shipley

**Purpose**: Independent R-based verification of Stage 1 pipeline integrity
**Date**: 2025-11-06
**Environment**: Pure R, no Python/SQL required

---

## Workflow Overview

**Phase 0**: Run WorldFlora normalization (5 scripts) → Verify CSV checksums
**Phase 1**: Build enriched parquets → Verify data integrity → Compare checksums

---

## Phase 0: WFO Normalization

### Commands

```bash
cd /home/olier/ellenberg

# Run 5 WorldFlora matching scripts (~1-2 hours total)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_duke_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_eive_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_mabberly_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_tryenhanced_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_austraits_match_bill.R

# Verify checksums (~5 seconds)
md5sum data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv \
       data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv
```

### Expected Checksums

| Dataset | Expected MD5 |
|---------|--------------|
| Duke | `481806e6c81ebb826475f23273eca17e` |
| EIVE | `fae234cfd05150f4efefc66837d1a1d4` |
| Mabberly | `0c82b665f9c66716c2f1ec9eafc4431d` |
| TRY Enhanced | `ce0f457c56120c8070f34d65f53af4b1` |
| AusTraits | `ebed20d3f33427b1f29f060309f5959d` |

**Success**: All 5 checksums match exactly → Proceed to Phase 1

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

## Round 1 Results (Development Testing)

**Date**: 2025-11-06
**System**: Ubuntu 22.04, R 4.x

| Phase | Component | Status | Details |
|-------|-----------|--------|---------|
| **Phase 0** | WorldFlora CSVs | ✓ PASS | All 5 datasets: byte-for-byte identical |
| **Phase 1** | Enriched parquets | ✓ PASS | Match counts: 11,822 / 14,141 / 13,420 / 45,194 / 31,580 |
| **Phase 1** | Master union | ✓ PASS | 86,815 taxa, CSV checksum identical |
| **Phase 1** | Shortlist | ✓ PASS | 24,542 species, CSV checksum identical |

**Conclusion**: Pipeline 100% reproducible in R. All checksums match.

---

## Round 2 Success Criteria (Bill's Independent Run)

### Phase 0: WFO Normalization
- [ ] All 5 WorldFlora scripts run without errors
- [ ] All 5 CSV checksums match expected values

### Phase 1: Data Integrity
- [ ] Enriched parquets script completes successfully
- [ ] Master union: 86,815 taxa
- [ ] Shortlist: 24,542 species
- [ ] Both verification checksums show **✓ PASS**

### Deliverable
- [ ] Log file: `logs/bill_phase1_verification.log`
- [ ] Report any ✗ FAIL messages or row count mismatches
- [ ] Confirm system info (OS, R version)

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
