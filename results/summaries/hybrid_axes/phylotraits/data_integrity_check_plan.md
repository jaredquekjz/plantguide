# Canonical Data Integrity Check Plan (2025-09-21)

This note captures the guardrails we will enforce to verify the integrity of
the canonical phylotraits datasets before running Stage 1 (RF/XGB) and Stage 2
(pwSEM/GAM) pipelines.

## 1. Automated Audit (`make data_integrity_audit`)
- Runs `scripts/data_integrity/check_data_integrity.py`.
- Produces a JSON report at
  `results/summaries/hybrid_axes/phylotraits/data_integrity_report.json` and the
  console summary.
- Current checks (PASS/WARN/FAIL) cover:
  1. Trait base table (unique species, 654 rows).
  2. Imputed trait table (species alignment, missing-value scan for the three
     BHPMF-imputed fields).
  3. Climate + AI summaries (species set consistency, AI column presence).
  4. Soil join (species set consistency, soil column completeness).
  5. Stage 1 feature exports (per-axis row counts, species coverage, empty
     columns limited to expected soil placeholders).
  6. Stage 2 SEM-ready tables (species alignment between `_stage2.csv` and
     `_stage2_pcs.csv`, PC scaling sanity checks).

Run the audit:

```bash
make data_integrity_audit
```

If a check downgrades to WARN/FAIL, investigate immediately before continuing
with modelling runs.

## 2. Additional Spot Checks (Manual / Ad-hoc)

| Area | Suggested Action |
|------|------------------|
| Trait coverage | Compare pre/post imputation histograms for `Leaf_thickness_mm`, `Frost_tolerance_score`, `Leaf_N_per_area`. |
| Climate join | Verify 5 random species: original occurrences, climate summary, AI monthly stats agree. |
| Soil join | Use `gdal_translate` on two random coordinates to confirm SoilGrids values match `*_phq_sg250m_20250916.csv`. |
| Feature exports | Inspect `xgb_*_cv_metrics*.json` to ensure the script dropped empty soil columns (log line: “Dropping 6 feature(s) with no finite data …”). |
| SEM-ready scaling | Confirm `pc_trait_*` mean≈0, sd≈1 per fold; examine `prepare_sem_ready_dataset.R` logs for recalc details. |

Document any manual spot checks in the weekly modelling log.

## 3. Future Enhancements

- **Hash manifest:** capture SHA256 hashes of canonical datasets to spot silent
  drift (store in `data_integrity_report.json`).
- **CI integration:** wire `make data_integrity_audit` into the modelling
  checklist so it runs before Stage 1/Stage 2 launches.
- **Spatial sanity:** add lightweight maps comparing occurrence centroids with
  extracted climate/soil values for random species.

Revision history: created 2025‑09‑21 after the Stage 1/Stage 2 canonical refresh.
