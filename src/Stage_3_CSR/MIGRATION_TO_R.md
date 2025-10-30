# Migration to R Implementation (2025-10-30)

## Summary

Stage 3 CSR calculation has been migrated from Python to **R as the canonical implementation**.

## Rationale

1. **R is native to plant ecology community** - Prof Shipley and most plant ecologists work in R
2. **Based on canonical reference** - commonreed/StrateFy R implementation is the community standard
3. **Verified equivalence** - R and Python implementations produce IDENTICAL CSR scores
4. **Better for review** - Easier for Prof Shipley to verify and provide feedback

## Changes

### Files Archived (Python Implementation)
Moved to `src/Stage_3_CSR/archive_python_20251030/`:
- `calculate_stratefy_csr.py` - Core CSR calculation
- `compute_ecoservices_shipley.py` - Ecosystem services
- `validate_shipley_part2.py` - Validation tests

### Canonical Files (R Implementation)
- `calculate_csr_ecoservices_shipley.R` - **Single R script for complete pipeline**
- `run_full_csr_pipeline.sh` - Updated to use R

### Kept for Reference
- `verify_stratefy_implementation.py` - Verification against Pierce et al. (2016)
- `compare_r_vs_python_results.R` - Verification of R vs Python equivalence
- `compare_r_vs_python_results.py` - Python comparison (for reference)

### Repository Structure
- Original reference: `repos/StrateFy/` (cloned from GitHub)
- Documentation: `src/Stage_3_CSR/R_IMPLEMENTATION_SUMMARY.md`

## Verification

**CSR Scores:** PERFECTLY IDENTICAL
- Max difference: 0.0000000000 (machine precision)
- Both implementations: 11,650 valid / 30 NaN (99.74% coverage)
- All valid CSR sum to 100%

**Edge Cases:** IDENTICAL
- Same 30 species fail in both implementations
- 21 conifers + 8 halophytes + 1 other
- Root cause: hit all 3 boundaries simultaneously (minC, minS, maxR)

## Usage

### Before (Python)
```bash
conda activate AI
bash src/Stage_3_CSR/run_full_csr_pipeline.sh
# Used 3 Python scripts: calculate → compute → validate
```

### Now (R - Canonical)
```bash
bash src/Stage_3_CSR/run_full_csr_pipeline.sh
# Uses single R script: calculate_csr_ecoservices_shipley.R
# No conda required, uses system R with custom .Rlib
```

## Output

**Same final output file:**
```
model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
```

**Columns (772 total):**
- C, S, R (CSR scores)
- 10 ecosystem service ratings
- 10 confidence levels
- All original trait/taxonomy columns

## For Prof Shipley

**R implementation advantages:**
1. Native R environment (no Python/conda needed)
2. Based on canonical StrateFy code (easy to verify)
3. Single script = simpler to review
4. Easier to extend/modify for R users

**Files for review:**
- Implementation: `src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R`
- Verification: `src/Stage_3_CSR/R_IMPLEMENTATION_SUMMARY.md`
- Edge cases: `results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_edge_case_analysis.md`
- Methodology: `results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_methodology_and_ecosystem_services.md`

## Backward Compatibility

Python implementation archived but still functional if needed:
```bash
# To use archived Python version (for comparison only):
conda run -n AI python src/Stage_3_CSR/archive_python_20251030/calculate_stratefy_csr.py ...
```

## Date: 2025-10-30
**Status:** ✓ Migration complete and verified
