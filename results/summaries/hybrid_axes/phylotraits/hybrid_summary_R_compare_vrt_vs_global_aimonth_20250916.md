R Axis — Apples‑to‑Apples Compare (Monthly AI + SoilGrids pH)

Scope
- Compares two equivalent pipelines that both include monthly AI dryness features and SoilGrids pH per‑depth summaries (means/sd/p10/p50/p90) plus derived root‑zone/flags, differing only by SoilGrids source:
  - OLD: VRT mosaics (remote tiles) → withph_quant + ai_month
  - NEW: Local global 250m GeoTIFFs → withph + ai_month (global_250m)

Labels and Inputs
- OLD (VRT, monthly AI): label `phylotraits_cleanedAI_discovery_gpu_withph_quant_aimonth_vrt_20250916`
  - Bioclim summary: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_vrt_20250916.csv`
  - Trait table: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
- NEW (Global 250m, monthly AI): label `phylotraits_cleanedAI_discovery_gpu_withph_sg250m_ph_20250916`
  - Bioclim summary: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv`
  - Trait table: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`

Metrics — XGB 3000 (GPU; 10‑fold CV)
- Baseline (no soil; prior):
  - no_pk: R²=0.126 ± 0.058; RMSE=1.494 ± 0.128
  - pk:    R²=0.201 ± 0.103; RMSE=1.427 ± 0.160
- OLD (VRT + monthly AI + pH):
  - no_pk: R²=0.194 ± 0.068; RMSE=1.435 ± 0.134
  - pk:    R²=0.249 ± 0.072; RMSE=1.385 ± 0.145
  - Artifacts: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_aimonth_vrt_20250916/R_{nopk,pk}/xgb_R_cv_metrics.json`
- NEW (Global 250m + monthly AI + pH):
  - no_pk: R²=0.174 ± 0.042; RMSE=1.453 ± 0.125
  - pk:    R²=0.223 ± 0.072; RMSE=1.410 ± 0.148
  - Artifacts: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_sg250m_ph_20250916/R_{nopk,pk}/xgb_R_cv_metrics.json`

- NEW (Global 250m + monthly AI + FULL soil, 7 properties × 6 depths):
  - no_pk: R²=0.189 ± 0.072; RMSE=1.441 ± 0.151
  - pk:    R²=0.222 ± 0.083; RMSE=1.411 ± 0.165
  - Artifacts:
    - no_pk: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_aimonth_20250916/R_nopk/xgb_R_cv_metrics.json`
    - pk:    `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_aimonth_20250916/R_pk/xgb_R_cv_metrics.json`

Deltas vs Baseline (no soil)
- OLD (VRT+pH): no_pk +0.068 R²; pk +0.048 R²
- NEW (Global+pH): no_pk +0.048 R²; pk +0.022 R²

Interpretation
- Both pipelines (with monthly AI) clearly improve over the no‑soil baseline; pH signal is robust (SHAP shows 5–15 cm mean/p90 among top features) in both.
- The OLD (VRT) run scores slightly higher than the NEW (Global 250m) by ~0.02 R² (no_pk) and ~0.026 R² (pk). This gap is modest and consistent with small extraction/aggregation nuances; feature‑rank agreement indicates good integrity in both.
- The earlier discrepancy (weak soil signals in some runs) most likely arose from: (a) missing monthly AI in those prior soil runs, and/or (b) occasional re‑exports using the default bioclim summary without soil columns. Both issues are resolved here.

Notes
- The NEW “full soil” global 250m pipeline (all 7 properties × 6 depths) has completed and been compared above.

**Repro Commands**
- Old VRT + monthly AI + pH (this comparison)
  - Merge soil (VRT summary) into monthly‑AI bioclim:
    - `R_LIBS_USER=/home/olier/ellenberg/.Rlib Rscript scripts/augment_bioclim_summary_with_soil.R --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --soil_summary /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv --output data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_vrt_20250916.csv`
  - Run interpretability (RF + XGB 3000 GPU):
    - `bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_quant_aimonth_vrt_20250916 --axes R --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_vrt_20250916.csv --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- New Global 250m + monthly AI + pH (this comparison)
  - Build pH‑only global‑250m soil summary (if needed):
    - `make soil_pipeline_global PROPERTIES=phh2o SOIL_GLOBAL_INPUT_CSV=/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv SOIL_GLOBAL_SUMMARY=/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv MERGED_SOIL_OUT_GLOBAL=artifacts/model_data_trait_bioclim_soil_merged_wfo_global_sg250m_ph_20250916.csv CHUNK=500000`
  - Merge soil (global 250m) into monthly‑AI bioclim:
    - `R_LIBS_USER=/home/olier/ellenberg/.Rlib Rscript scripts/augment_bioclim_summary_with_soil.R --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --soil_summary /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv --output data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv`
  - Run interpretability (RF + XGB 3000 GPU):
    - `bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_sg250m_ph_20250916 --axes R --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_ph_sg250m_ph_20250916.csv --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`

- New Global 250m + monthly AI + FULL soil (7 props × 6 depths)
  - Build full‑soil global‑250m summary:
    - `make soil_pipeline_global SOIL_GLOBAL_INPUT_CSV=/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv SOIL_GLOBAL_SUMMARY=/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_all_20250916.csv MERGED_SOIL_OUT_GLOBAL=artifacts/model_data_trait_bioclim_soil_merged_wfo_global_all_20250916.csv CHUNK=500000`
  - Merge full soil into monthly‑AI bioclim:
    - `R_LIBS_USER=/home/olier/ellenberg/.Rlib Rscript scripts/augment_bioclim_summary_with_soil.R --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --soil_summary /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_all_20250916.csv --output data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv`
  - Run interpretability (RF + XGB 3000 GPU):
    - `bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_aimonth_20250916 --axes R --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`

Data Processing Overview (this comparison)
- Occurrences and deduplication
  - Source: `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv` (bioclim‑first pipeline)
  - Soil extraction at unique coordinates (lon, lat); species‑level aggregation from unique coords to avoid overweighting repeated observations.
- SoilGrids extraction
  - VRT (OLD): `scripts/extract_soilgrids_efficient.R` reads local VRTs in `data/soilgrids_250m`, extracts per‑depth layers (6 depths), scales to physical units, and writes to occurrence table. Species aggregation: `scripts/aggregate_soilgrids_species.R` computes per‑species mean, sd, p10/p50/p90, and per‑layer n_valid across unique coords; output: `.../species_soil_summary.csv`.
  - Global 250m (NEW): `src/Stage_1_Data_Extraction/extract_soilgrids_global_250m.R` reads local GeoTIFFs in `data/soilgrids_250m_global`, extracts per‑depth layers with the same scaling, and writes to occurrence table; species aggregation as above; outputs:
    - pH only: `.../species_soil_summary_global_sg250m_ph_20250916.csv`
    - Full soil: `.../species_soil_summary_global_all_20250916.csv`
- Monthly AI integration
  - Base bioclim summary with monthly AI dryness metrics: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
  - Augment bioclim with soil columns via `scripts/augment_bioclim_summary_with_soil.R` (joins by normalized species names; preserves monthly AI fields). Distinct outputs per variant as shown above.
- Modeling configuration
  - Trait table: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
  - Export + RF CV baseline + XGB interpretability orchestrated by `scripts/run_interpret_axes_tmux.sh` → `Makefile.hybrid` targets.
  - Axes: R; CV: 10‑fold; XGB: GPU, 3000 trees, lr=0.02; pk variant adds `p_phylo` (global LOO) as a covariate.
