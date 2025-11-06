# GBIF Case-Sensitivity Bug Fix

**Date**: 2025-11-06
**Related**: EIVE/TRY case-sensitivity bug fix (same issue)

## Issue Discovered

The GBIF WorldFlora enrichment SQL (1.1_Raw_Data_Preparation.md, line 1177) had the same case-sensitivity bug as EIVE/TRY datasets:

```sql
-- BUGGY (case-sensitive):
CASE WHEN taxonomicStatus = 'accepted' THEN 0 ELSE 1 END

-- FIXED (case-insensitive):
CASE WHEN lower(taxonomicStatus) = 'accepted' THEN 0 ELSE 1 END
```

**Root cause**: WorldFlora R package returns `taxonomicStatus = "Accepted"` (capital A), but the deduplication SQL used case-sensitive comparison. This caused "Accepted" records to be ranked identically to "Unchecked" records in the ROW_NUMBER() OVER window function.

**WorldFlora taxonomicStatus distribution** (GBIF):
- Accepted: 158,515 records
- Unchecked: 7,938 records

## Fix Applied

**Date**: 2025-11-06 21:28

1. Updated GBIF enrichment SQL to use `lower(taxonomicStatus) = 'accepted'`
2. Regenerated `data/gbif/occurrence_plantae_wfo.parquet` (70M occurrences, 33.9s)
3. Regenerated all shortlists via `rebuild_shortlists.py`

**Archived files**: `data/stage1/archive_pre_gbif_case_fix/`

## Impact Analysis

### 1. Base Shortlist (Trait-Rich Species)

**File**: `stage1_shortlist_with_gbif.parquet`

- Old: 24,542 species
- New: 24,511 species
- **Impact: -31 species** (matches EIVE/TRY fix)

**Taxa churn**:
- Removed: 466 taxa
- Added: 435 taxa
- Net: -31 taxa

This aligns with the EIVE/TRY fix which also resulted in -31 species in the base shortlist due to better deduplication.

### 2. Bill Shipley Reference Shortlist (≥30 GBIF Occurrences)

**File**: `stage1_shortlist_with_gbif_ge30.parquet`

- Old: 11,680 species
- New: 11,711 species
- **Impact: +31 species** ✓ IMPROVEMENT

**Taxa churn**:
- Dropped below 30: 214 taxa (e.g., Leucadendron salignum, Malus prunifolia)
- Rose above 30: 245 taxa (e.g., Pachygone ovata, Potentilla argentea)
- Net: +31 taxa

**Interpretation**: The buggy ranking was assigning GBIF occurrences to incorrect WFO IDs in some cases. When fixed, occurrence counts redistributed to the correct accepted taxa, resulting in:
- Some species losing occurrences (dropped below 30)
- More species gaining occurrences (rose above 30)
- **Net positive effect**: More trait-rich species now meet the ≥30 GBIF threshold

### 3. Modelling Shortlist (Complete EIVE + TRY Rich, ≥30 GBIF)

**File**: `stage1_modelling_shortlist_with_gbif_ge30.parquet`

- Old: 1,084 species
- New: 1,068 species
- **Impact: -16 species**

**Taxa churn**:
- Removed: 38 species
- Added: 22 species
- Net: -16 species

**Stage 2 impact**: Modelling pipeline affected. 16 fewer species meet the strict criteria (all 5 EIVE indices + ≥8 TRY traits + ≥30 GBIF occurrences).

## Key Findings

1. **GBIF bug had opposite effect on ≥30 subset**: Unlike EIVE/TRY fix which reduced counts, GBIF fix **increased** the ≥30 reference shortlist by 31 species. This is a quality improvement - more trait-rich species now have sufficient occurrence data.

2. **Higher churn than EIVE/TRY**: GBIF affected 466+435=901 taxa moves vs EIVE/TRY's 223+435=658. This is expected since GBIF has 70M records across 161K species (much larger scale).

3. **Correct WFO aggregation critical**: The bug was causing occurrence counts to aggregate under wrong accepted taxa. Fixing ensures GBIF occurrence tallies reflect the correct taxonomic concepts.

## Verification

Bill Shipley's R-based independent verification correctly implements case-insensitive comparison for all datasets (including GBIF via canonical `occurrence_plantae_wfo.parquet`). No changes needed to Bill's scripts.

## Related Documents

- **EIVE/TRY fix**: `data/stage1/archive_pre_case_fix/README.md`
- **Impact**: Same -31 species in base shortlist, but different mechanism (trait deduplication vs occurrence redistribution)
- **Bill verification**: `Bill_Shipley_Data_Integrity_Check_Concise.md` (Phase 0-1 unaffected, GBIF integration is optional future work)

## Updated Canonical Counts (Post Both Fixes)

- Master taxa union: 86,592 taxa
- Base shortlist (≥3 traits): 24,511 species
- **Bill's reference (≥30 GBIF): 11,711 species** ← Updated
- Modelling shortlist (complete EIVE + TRY rich): 1,273 species
- Modelling with ≥30 GBIF: 1,068 species ← Updated

## Reproducibility

```bash
# Regenerate GBIF enrichment (with fix)
cd /home/olier/ellenberg
conda run -n AI python - <<'PY'
import duckdb
conn = duckdb.connect()
# ... (SQL with lower(taxonomicStatus) fix)
PY

# Rebuild all shortlists
conda run -n AI python src/Stage_1/Data_Extraction/rebuild_shortlists.py

# Compare old vs new
python /tmp/compare_gbif_shortlists.py
```

## Conclusion

The GBIF case-sensitivity fix **improves data quality** by correctly redistributing occurrence counts to accepted taxa. The net +31 species in Bill's reference shortlist (11,680 → 11,711) means more trait-rich species now have robust occurrence data for downstream modeling.

**Action**: Update Stage 2+ documentation to reflect new counts. The 1,068-species modelling shortlist is the correct input for SEM/copula workflows.
