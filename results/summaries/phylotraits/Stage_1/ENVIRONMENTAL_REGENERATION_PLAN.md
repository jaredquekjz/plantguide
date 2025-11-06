# Environmental Data Regeneration Plan

**Date**: 2025-11-06
**Reason**: Shortlist changed after GBIF case-sensitivity bug fix
**Impact**: 11,680 → 11,711 species (+31 net: 245 added, 214 removed)

---

## Current Status

### Affected Files (Currently Outdated)
All environmental data based on old shortlist (11,680 species from Oct 21):

**Occurrence samples** (31.3M rows each):
- `data/stage1/worldclim_occ_samples.parquet`
- `data/stage1/soilgrids_occ_samples.parquet`
- `data/stage1/agroclime_occ_samples.parquet`

**Species summaries** (11,680 taxa each):
- `data/stage1/worldclim_species_summary.parquet`
- `data/stage1/soilgrids_species_summary.parquet`
- `data/stage1/agroclime_species_summary.parquet`

**Species quantiles** (11,680 taxa each):
- `data/stage1/worldclim_species_quantiles.parquet`
- `data/stage1/soilgrids_species_quantiles.parquet`
- `data/stage1/agroclime_species_quantiles.parquet`

### Shortlist Changes (GBIF Case-Sensitivity Bug Fix)

**Old**: `data/stage1/archive_pre_gbif_case_fix/stage1_shortlist_with_gbif_ge30_case_bug.parquet`
- 11,680 species with ≥30 GBIF occurrences

**New**: `data/stage1/stage1_shortlist_with_gbif_ge30.parquet`
- 11,711 species with ≥30 GBIF occurrences
- +245 species (rose above 30 occurrences after GBIF WFO ID fix)
- -214 species (dropped below 30 occurrences after GBIF WFO ID fix)

**Why shortlist grew**: GBIF case bug was causing occurrences to aggregate under wrong WFO IDs. Fix redistributed counts to correct accepted taxa, resulting in more species crossing the ≥30 threshold.

### Modelling Shortlist Changes

**Current counts**:
- Full modelling shortlist: **1,249 species** (complete EIVE + ≥8 TRY traits)
- Modelling ≥30 GBIF: **1,068 species** (Stage 2 input)

**Documentation was incorrect**: Listed 1,273 but actual is 1,249 (pre-fix was 1,084, now 1,068 for ≥30 subset)

---

## Regeneration Steps

### Step 1: Archive Current Environmental Files

```bash
cd /home/olier/ellenberg

# Create archive directory
mkdir -p data/stage1/archive_pre_gbif_case_fix/environmental

# Archive occurrence samples
cp data/stage1/worldclim_occ_samples.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/soilgrids_occ_samples.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/agroclime_occ_samples.parquet data/stage1/archive_pre_gbif_case_fix/environmental/

# Archive summaries
cp data/stage1/worldclim_species_summary.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/soilgrids_species_summary.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/agroclime_species_summary.parquet data/stage1/archive_pre_gbif_case_fix/environmental/

# Archive quantiles
cp data/stage1/worldclim_species_quantiles.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/soilgrids_species_quantiles.parquet data/stage1/archive_pre_gbif_case_fix/environmental/
cp data/stage1/agroclime_species_quantiles.parquet data/stage1/archive_pre_gbif_case_fix/environmental/

echo "✓ Archived 9 environmental files (based on 11,680 species)"
```

### Step 2: Regenerate Environmental Sampling (6-9 hours total)

**Run in parallel using tmux for efficiency**

#### WorldClim Sampling (~2-3 hours, 63 chunks)
```bash
tmux new -s worldclim_sample
cd /home/olier/ellenberg
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Sampling/sample_env_terra.R \
  data/stage1/stage1_shortlist_with_gbif_ge30.parquet worldclim \
  |& tee logs/worldclim_sampling_20251106.log
# Ctrl+B D to detach
```

#### SoilGrids Sampling (~2-3 hours, 63 chunks)
```bash
tmux new -s soilgrids_sample
cd /home/olier/ellenberg
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Sampling/sample_env_terra.R \
  data/stage1/stage1_shortlist_with_gbif_ge30.parquet soilgrids \
  |& tee logs/soilgrids_sampling_20251106.log
# Ctrl+B D to detach
```

#### Agroclim Sampling (~2-3 hours, 63 chunks)
```bash
tmux new -s agroclim_sample
cd /home/olier/ellenberg
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/Sampling/sample_env_terra.R \
  data/stage1/stage1_shortlist_with_gbif_ge30.parquet agroclime \
  |& tee logs/agroclim_sampling_20251106.log
# Ctrl+B D to detach
```

**Monitor progress**:
```bash
tmux ls  # List sessions
tmux attach -t worldclim_sample  # Attach to check progress
# Look for "Chunk 63/63 ... 100.00%" completion message
```

**Expected outputs** (will show ~31.4M rows, 11,711 taxa):
- `data/stage1/worldclim_occ_samples.parquet`
- `data/stage1/soilgrids_occ_samples.parquet`
- `data/stage1/agroclime_occ_samples.parquet`

### Step 3: Regenerate Aggregations (~10-15 minutes)

```bash
cd /home/olier/ellenberg

# Generate means/summaries (avg, min, max, std)
conda run -n AI --no-capture-output python src/Stage_1/aggregate_stage1_env_summaries.py \
  worldclim soilgrids agroclime \
  |& tee logs/aggregate_summaries_20251106.log
```

**Expected outputs** (11,711 taxa each):
- `data/stage1/worldclim_species_summary.parquet`
- `data/stage1/soilgrids_species_summary.parquet`
- `data/stage1/agroclime_species_summary.parquet`

### Step 4: Regenerate Quantiles (~5-10 minutes)

**Use DuckDB as documented in Climate_Soil_Agroclim_Workflows.md**

```bash
cd /home/olier/ellenberg
conda run -n AI python - <<'PY'
import duckdb

con = duckdb.connect()

datasets = [
    ('worldclim', 'data/stage1/worldclim_occ_samples.parquet'),
    ('soilgrids', 'data/stage1/soilgrids_occ_samples.parquet'),
    ('agroclime', 'data/stage1/agroclime_occ_samples.parquet')
]

for ds_name, occ_path in datasets:
    print(f"Generating quantiles for {ds_name}...")

    # Get all columns except wfo_taxon_id, gbifID, lon, lat
    cols = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{occ_path}')").fetchall()
    value_cols = [c[0] for c in cols if c[0] not in ['wfo_taxon_id', 'gbifID', 'lon', 'lat']]

    # Build quantile aggregations
    agg_exprs = []
    for col in value_cols:
        agg_exprs.append(f'quantile("{col}", 0.05) AS "{col}_q05"')
        agg_exprs.append(f'median("{col}") AS "{col}_q50"')
        agg_exprs.append(f'quantile("{col}", 0.95) AS "{col}_q95"')

    sql = f"""
        COPY (
            SELECT wfo_taxon_id, {', '.join(agg_exprs)}
            FROM read_parquet('{occ_path}')
            GROUP BY wfo_taxon_id
            ORDER BY wfo_taxon_id
        ) TO 'data/stage1/{ds_name}_species_quantiles.parquet'
          (FORMAT PARQUET, COMPRESSION ZSTD)
    """

    con.execute(sql)
    print(f"  ✓ {ds_name}_species_quantiles.parquet")

con.close()
print("\n✓ All quantiles generated")
PY
```

**Expected outputs** (11,711 taxa each):
- `data/stage1/worldclim_species_quantiles.parquet`
- `data/stage1/soilgrids_species_quantiles.parquet`
- `data/stage1/agroclime_species_quantiles.parquet`

### Step 5: Verification (~5 minutes)

```bash
cd /home/olier/ellenberg

# Run automated verification
conda run -n AI --no-capture-output python src/Stage_1/verification/verify_environmental.py \
  |& tee logs/environmental_verification_20251106.log
```

**Expected results**:
- ✓ All files present
- ✓ 11,711 taxa in each dataset (up from 11,680)
- ✓ ~31.4M occurrence rows per dataset
- ✓ All null fractions <99%
- ✓ Quantile ordering constraints satisfied
- ✓ Cross-dataset species alignment perfect
- ✓ 1,068 modelling taxa (≥30 GBIF) have complete environmental coverage

### Step 6: Update Documentation

**File**: `results/summaries/phylotraits/Stage_1/1.6_Environmental_Verification.md`

**Count updates needed**:

```python
# Line 16: Total taxa
11,680 → 11,711

# Line 17: Modelling taxa (correct the error)
1,273 → 1,249  # Full modelling shortlist
# Note: 1,068 species meet ≥30 GBIF threshold (Stage 2 input)

# Line 126-127: Expected values
31,345,882 → ~31,400,000 (exact count from verification)
11,680 → 11,711

# Line 147: Shortlist alignment
11,680 → 11,711

# Lines 338-344: Cross-dataset consistency results
11,680 → 11,711 (all three)
1,273 → 1,068 (modelling shortlist ≥30 GBIF)

# Lines 383-398: Verification summary
Update all 11,680 → 11,711
Update 1,273 → 1,068 modelling taxa
```

**Add note about regeneration**:
```markdown
**Regeneration Note (2025-11-06)**: Environmental data regenerated after GBIF
case-sensitivity bug fix. Shortlist increased from 11,680 to 11,711 species
(+31 net). All occurrence samples, summaries, and quantiles reflect updated
shortlist. See GBIF_Case_Sensitivity_Bug_Fix.md for details.
```

### Step 7: Git Commit

```bash
cd /home/olier/ellenberg

git add results/summaries/phylotraits/Stage_1/1.6_Environmental_Verification.md
git commit -m "Update environmental verification docs after regeneration

Regenerated all environmental data (WorldClim, SoilGrids, Agroclim) after
GBIF case-sensitivity bug fix changed shortlist from 11,680 to 11,711 species.

Updates:
- Species count: 11,680 → 11,711 taxa
- Modelling count: Corrected from 1,273 to 1,068 (≥30 GBIF subset)
- Occurrence samples: ~31.4M rows per dataset
- All verification checks passed

Regeneration date: 2025-11-06
See GBIF_Case_Sensitivity_Bug_Fix.md for shortlist change details."

git push
```

---

## Verification Checklist

After regeneration, verify:

- [ ] All 3 occurrence sample files exist with ~31.4M rows, 11,711 taxa
- [ ] All 3 species summary files exist with 11,711 taxa
- [ ] All 3 species quantile files exist with 11,711 taxa
- [ ] Sampling logs show "Chunk 63/63 ... 100.00%" completion
- [ ] Null fractions all <99% (verify_environment_nulls.py)
- [ ] Quantile ordering: min ≤ q05 ≤ q50 ≤ q95 ≤ max (no violations)
- [ ] Cross-dataset species alignment: all 11,711 species in all 3 datasets
- [ ] Modelling shortlist integration: 1,068 species have complete environmental coverage
- [ ] verify_environmental.py shows ✅ ALL CHECKS PASSED

---

## Time Estimates

| Task | Duration | Can Run in Parallel? |
|------|----------|---------------------|
| Archive files | 2 min | No |
| WorldClim sampling | 2-3 hours | Yes (tmux) |
| SoilGrids sampling | 2-3 hours | Yes (tmux) |
| Agroclim sampling | 2-3 hours | Yes (tmux) |
| Aggregate summaries | 10-15 min | No |
| Generate quantiles | 5-10 min | No |
| Verification | 5 min | No |
| Update docs | 10 min | No |

**Total sequential**: ~10-12 hours
**Total parallel (3 tmux)**: ~3-4 hours

---

## Troubleshooting

### If sampling fails mid-way
Check log files for chunk number where it stopped. Sampling is resumable - it will skip completed chunks.

### If memory issues occur
Each tmux session samples in chunks (500K occurrences per chunk). Should not exceed available RAM.

### If verification fails
1. Check log files: `logs/*_sampling_20251106.log`
2. Verify chunk completion: `grep "Chunk 63/63" logs/*.log`
3. Check species counts: Run DuckDB queries from verification doc
4. Compare with archived files to identify issues

### If aggregation fails
Ensure all 3 occurrence sample files completed successfully before running aggregations.

---

## Files to Keep vs Archive

**Archive** (keep for rollback):
- 9 old environmental parquets (11,680 taxa)
- Old shortlist (11,680 species)

**Keep** (new production files):
- 9 new environmental parquets (11,711 taxa)
- New shortlist (11,711 species)
- All intermediate logs

**Location**: `data/stage1/archive_pre_gbif_case_fix/environmental/`

---

## References

- **GBIF bug fix details**: `results/summaries/phylotraits/Stage_1/GBIF_Case_Sensitivity_Bug_Fix.md`
- **Sampling workflow**: `results/summaries/phylotraits/Stage_1/Climate_Soil_Agroclim_Workflows.md`
- **Verification checklist**: `results/summaries/phylotraits/Stage_1/1.6_Environmental_Verification.md`
- **Verification script**: `src/Stage_1/verification/verify_environmental.py`

---

## Status Tracking

- [ ] Plan reviewed and approved
- [ ] Archive completed
- [ ] WorldClim sampling completed
- [ ] SoilGrids sampling completed
- [ ] Agroclim sampling completed
- [ ] Summaries aggregated
- [ ] Quantiles generated
- [ ] Verification passed
- [ ] Documentation updated
- [ ] Git committed and pushed
- [ ] Bill's verification docs updated (if needed)

---

**Estimated completion**: 3-4 hours (parallel tmux) or 10-12 hours (sequential)
**Risk level**: Low (straightforward regeneration, all scripts tested)
**Blocking Stage 2?**: Yes - modelling pipeline needs updated environmental data for correct 11,711 species
