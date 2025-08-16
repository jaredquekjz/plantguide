Title: Stage 6 — Joint Suitability via Copulas (Run 8) + Docs update

Scope
- Add Gaussian copula diagnostics (Run 8) and a minimal piecewise copula runner (Stage 4).
- Implement joint suitability for gardening (Stage 6): single requirement gate, batch presets, and best-scenario annotation.
- Update gardening plan with a concise “Joint probability with copulas” section.

Key Changes
- Stage 4:
  - src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R — build residuals from final forms; auto-detect districts; fit Gaussian copulas; write results/mag_copulas.json
  - src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R — quick adequacy check (tau alignment, tails, 2-fold CV log-copula)
  - results/stage_sem_run8_copula_diagnostics.md, results/stage_sem_run8_summary.md, results/mag_copulas.json
- Stage 6:
  - src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R — Monte Carlo joint probability; single `--joint_requirement` or batch `--presets_csv`
  - src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R — adds `joint_requirement`/`joint_prob`/`joint_ok` and best-scenario fields via `--joint_presets_csv`
  - src/Stage_6_Gardening_Predictions/README.md — usage + joint explanation
  - results/garden_joint_presets_defaults.csv — 5 illustrative scenarios with default threshold 0.6
- Docs:
  - results/gardening_plan_Aplusplus.md — appended “Joint Probability with Copulas (Run 8)” section

Repro Commands
- Export equations (Run 8 versioning):
  - Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --version Run8
- Fit copulas (auto districts):
  - Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --auto_detect_districts true --rho_min 0.15 --fdr_q 0.05 --copulas gaussian --select_by AIC
- Gaussian adequacy check:
  - Rscript src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R --input_csv artifacts/model_data_complete_case_with_myco.csv --copulas_json results/mag_copulas.json --out_md results/stage_sem_run8_copula_diagnostics.md --nsim 200000
- Joint suitability (batch presets):
  - Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/mag_copulas.json --metrics_dir artifacts/stage4_sem_piecewise_run7 --presets_csv results/garden_joint_presets_defaults.csv --nsim 20000 --summary_csv results/garden_joint_summary.csv
- Recommender with best scenario:
  - Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R --predictions_csv results/mag_predictions_no_eive.csv --output_csv results/garden_requirements_no_eive.csv --bins 0:3.5,3.5:6.5,6.5:10 --copulas_json results/mag_copulas.json --metrics_dir artifacts/stage4_sem_piecewise_run7 --nsim_joint 20000 --joint_presets_csv results/garden_joint_presets_defaults.csv

Outputs
- results/mag_copulas.json — residual districts and parameters
- results/stage_sem_run8_copula_diagnostics.md — adequacy summary
- results/garden_joint_summary.csv — species × scenarios joint probabilities
- results/garden_requirements_no_eive.csv — now includes best scenario fields

Notes
- Copulas improve multi-axis suitability decisions; single-axis predictions remain unchanged.
- Defaults: bins [0,3.5), [3.5,6.5), [6.5,10]; preset threshold 0.6 (tunable).
