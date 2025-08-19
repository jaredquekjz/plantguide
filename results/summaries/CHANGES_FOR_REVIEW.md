# Reviewer Summary — Group‑Aware Uncertainty and Copulas (Shrinkage + Docs)

Goal: Improve joint‑probability calibration for Gardening Plan decisions by adding group‑aware residual scales (σ) and per‑group copulas (ρ), with shrinkage to global for small groups. Predictions (means) are unchanged; only uncertainty and multi‑axis co‑movement are refined.

## Code Changes
- src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R
  - Added flags: --group_col, --group_ref_csv, --group_ref_id_col, --group_ref_group_col, --sigma_mode.
  - Uses per‑group σ (Run 7 RMSE per axis) and, when present, per‑group ρ from mag_copulas.json (by_group); else falls back to global.
  - Efficient: one Cholesky per group reused across species.
- src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R
  - Same group‑aware σ + ρ support for joint gate and preset scoring; same flags.
- src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R
  - New flags: --group_col, --min_group_n (default 20), --shrink_k (default 100).
  - Fits global spouse set within each group; writes per‑group copulas to by_group in mag_copulas.json.
  - Shrinks per‑group ρ toward global: ρ_shrunk = n/(n+shrink_k)*ρ_group + (1−n/(n+shrink_k))*ρ_global.
  - Diagnostics CSV: results/MAG_Run8/stage_sem_run8_copula_group_diagnostics.csv (n, ρ_raw, ρ_shrunk, weight, Kendall τ, implied τ from ρ, τ delta, normal‑score ρ).

## Documentation Updates
- README.md
  - Quick Start: new “Optional — Group‑Aware Uncertainty and Copulas” with exact flags and fallbacks.
  - Repro: per‑group copulas via --group_col; shrinkage via --shrink_k 100; Stage 6 auto‑uses per‑group ρ when present.
- src/Stage_6_Gardening_Predictions/README.md
  - Clarified Stage 6 uses per‑group σ and per‑group ρ if available; global fallback otherwise.
- results/summaries/PR_SUMMARY_Run8_Joint_Gardening.md
  - Added “Per‑Group Copulas” section (shrinkage + diagnostics).
  - Added tables for full dataset (1,069 spp) and a 23‑species subset using group‑aware σ+ρ (mycorrhiza).

## Rationale
- Runs 2–3 indicated group structure improves d‑sep. Later analysis showed per‑group RMSE differs materially (AM/EM vs NM; woody vs non‑woody). A single global σ/ρ mis‑calibrates AND‑gate decisions.
- Group‑aware σ tailors uncertainty; per‑group ρ tailors co‑movement (e.g., T↔R, L↔M). Shrinkage keeps small‑n groups stable.

## Repro (Key Commands)
- Fit copulas with per‑group ρ + shrinkage (Run 8):
  Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R     --input_csv artifacts/model_data_complete_case_with_myco.csv     --out_dir results/MAG_Run8 --version Run8     --district L,M --district T,R --district T,M --district M,R --district M,N     --group_col Myco_Group_Final --shrink_k 100
- Score presets with per‑group σ + ρ (Stage 6):
  # With R presets
  Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R     --predictions_csv results/mag_predictions_with_myco.csv     --copulas_json results/MAG_Run8/mag_copulas.json     --metrics_dir artifacts/stage4_sem_piecewise_run7     --presets_csv results/gardening/garden_joint_presets_defaults.csv     --nsim 20000     --group_col Myco_Group_Final     --group_ref_csv artifacts/model_data_complete_case_with_myco.csv     --group_ref_id_col wfo_accepted_name     --group_ref_group_col Myco_Group_Final     --summary_csv results/gardening/garden_joint_summary_group_myco.csv
  # R‑excluded presets (more confident)
  Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R     --predictions_csv results/mag_predictions_with_myco.csv     --copulas_json results/MAG_Run8/mag_copulas.json     --presets_csv results/gardening/garden_presets_no_R.csv     --nsim 20000     --group_col Myco_Group_Final     --group_ref_csv artifacts/model_data_complete_case_with_myco.csv     --group_ref_id_col wfo_accepted_name     --group_ref_group_col Myco_Group_Final     --summary_csv results/gardening/garden_joint_summary_no_R_group_myco.csv

## Evidence (Selected)
- Full dataset (σ+ρ per group; shrink_k=100):
  - With R: modest means; no passes ≥0.6 (expected).
  - Without R: RichSoilSpecialist mean ≈ 0.218, max ≈ 0.826; 74 passes ≥0.6.
- 23‑species subset (σ+ρ per group; shrink_k=100):
  - With R: no passes ≥0.6.
  - Without R: RichSoilSpecialist mean ≈ 0.318, max ≈ 0.824; 6 passes ≥0.6.
 - Tables and species list in results/summaries/PR_SUMMARY_Run8_Joint_Gardening.md and results/MAG_Run8/sample23_species.txt

## Attachments
- 23-species list: `results/MAG_Run8/sample23_species.txt`
- Full-dataset group-aware summaries (moved under MAG_Run8):
  - With R: `results/MAG_Run8/groupaware_withR_summary.csv`
  - Without R: `results/MAG_Run8/groupaware_noR_summary.csv`
  - σ-only vs σ+ρ comparison: `results/MAG_Run8/stage6_group_copula_vs_global_summary.csv`
  - Group uncertainty snapshot: `results/MAG_Run8/stage6_group_uncertainty_summary.csv`
- 23-species summaries (moved under MAG_Run8):
  - With R: `results/MAG_Run8/groupaware_withR_summary_sample23.csv`
  - Without R: `results/MAG_Run8/groupaware_noR_summary_sample23.csv`

## Compatibility & Safety
- Defaults remain global σ/ρ; group‑aware modes are opt‑in via --group_col.
- Small groups: shrinkage + global fallback reduce overfit risk.
- Predictions (means) untouched; only joint uncertainty changes.
