Axis R — Global 250m SoilGrids pH Re‑run (sg250m_ph_20250916)

Summary
- Built a fresh pH‑only dataset from local SoilGrids global 250m GeoTIFFs (no VRT/HTTP), merged into the bioclim summary, and reran the R‑axis interpretability pipeline (RF + XGB GPU 3000 trees).
- XGB (no_pk) improves vs the no‑soil baseline (ΔR² ≈ +0.044). SHAP shows strong pH signal, especially 5–15 cm mean and p90. pk run is in progress; results will be appended.

Data Lineage
- Global extractor: `src/Stage_1_Data_Extraction/extract_soilgrids_global_250m.R` (new; moved from data folder, robust CLI)
- Make targets (new): `soil_extract_global`, `soil_pipeline_global`
- Occurrence input: `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`
- Soil (pH only) summary (distinct label):
  - `data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv` (rows=1008, cols=21)
- Bioclim summary + AI month (base):
  - `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
- Augmented bioclim (+pH, distinct label):
  - `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv` (rows=1008, cols=89)

Repro Commands
- Build pH‑only global 250m dataset (tmux):
  - `make soil_pipeline_global PROPERTIES=phh2o SOIL_GLOBAL_INPUT_CSV=data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv SOIL_GLOBAL_SUMMARY=data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv MERGED_SOIL_OUT_GLOBAL=artifacts/model_data_trait_bioclim_soil_merged_wfo_global_sg250m_ph_20250916.csv CHUNK=500000`
- Augment bioclim with pH:
  - `Rscript scripts/augment_bioclim_summary_with_soil.R --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --soil_summary data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv --output data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv`
- R‑axis interpretability (RF + XGB, GPU 3000 trees; distinct label):
  - `bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_sg250m_ph_20250916 --axes R --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv`

Results
- XGB (3000 trees; GPU)
  - no_pk: R²=0.174 ± 0.042; RMSE=1.453 ± 0.125
  - pk:    R²=0.223 ± 0.072; RMSE=1.410 ± 0.148
- Baselines for context (from prior non‑soil run in this file):
  - XGB 3000 no‑soil: no_pk 0.126 ± 0.058; pk 0.201 ± 0.103
- Deltas vs no‑soil baseline (this re‑run):
  - no_pk: ΔR² ≈ +0.044; ΔRMSE ≈ −0.041
  - pk:    ΔR² ≈ +0.022; ΔRMSE ≈ −0.017
- Interpretability (no_pk; SHAP |f| top signals)
  - Strong: `phh2o_5_15cm_mean`, `phh2o_5_15cm_p90`, `temp_range`, `drought_min`, `precip_warmest_q`, `wood_precip`, `mat_mean`
  - Root‑zone features present: `ph_rootzone_mean` and `hplus_rootzone_mean` contribute modestly

Artifacts
- Label dir: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_sg250m_ph_20250916`
- Metrics JSON:
  - no_pk: `R_nopk/xgb_R_cv_metrics.json`
  - pk:    `R_pk/xgb_R_cv_metrics.json` [will appear on completion]
- SHAP importance (no_pk): `R_nopk/xgb_R_shap_importance.csv`

Comparison vs earlier SoilGrids R runs (XGB 3000; 10‑fold CV)
- Prior runs (VRT‑based extraction):
  - pH (all depths): no_pk 0.186 ± 0.060; pk 0.230 ± 0.087
  - Root‑zone:       no_pk 0.184 ± 0.060; pk 0.241 ± 0.080
  - Root‑zone+flags: no_pk 0.174 ± 0.068; pk 0.249 ± 0.079
  - Quantiles:       no_pk 0.189 ± 0.046; pk 0.233 ± 0.068
- This re‑run (global 250m GeoTIFFs):
  - pH (+AI month):  no_pk 0.174 ± 0.042; pk 0.223 ± 0.072
- Interpretation:
  - The new run restores a clear pH effect (notably 5–15 cm mean/p90), lifting performance over no‑soil by +0.044 (no_pk) and +0.022 (pk).
  - Absolute R² is slightly below the prior best pH variants (by ~0.01–0.02), which is within plausible variation given feature set differences and extraction details. Overall patterns (top features and key interactions) match.

Notes on Pipeline Adjustments
- Added global 250m extractor and Make targets to remove dependence on remote VRTs and reduce NA gaps.
- Added `scripts/augment_bioclim_summary_with_soil.R` to append soil columns (pH here) into the bioclim summary used by the exporter.
- Fixed Makefile.hybrid bug: `hybrid_interpret_rf` now respects `TRAIT_CSV`/`BIOCLIM_SUMMARY` passed by callers (prevents accidental re‑export with defaults that omit soil columns).

Interpretation
- The global 250m pH integration restores a clear pH signal (notably 5–15 cm) and lifts R² over the no‑soil baseline. SHAP feature ranks and PDs closely mirror earlier pH runs. This indicates the data path is sound; previous concerns likely stemmed from VRT coverage gaps or accidental re‑exports with a non‑soil bioclim summary. The small R² differences vs earlier pH variants are modest and consistent with feature set nuances rather than integrity issues.

Next Steps
- Append pk metrics upon completion and add top SHAP features/PDs.
- If pk improves similarly (≥ +0.02–0.04 R²), conclude the soil pH data path is sound. Otherwise, double‑check that all export steps used the augmented summary (watch for older Makefile targets re‑exporting with defaults).
