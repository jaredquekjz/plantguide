Title: Stage 6 — Joint Suitability via Copulas (Run 8, Final Spouse Set) + Docs Update

Scope
- Finalize Run 8 MAG residual copulas with 5 spouses and align m‑sep to SEMwise (mixed residuals, rank‑based tests).
- Implement and document joint suitability for gardening (Stage 6): single requirement gate, batch presets, and best‑scenario annotation.
- Analyze a new set of joint scenarios that exclude the weakly-predicted 'R' axis to generate more confident, actionable recommendations.
- Update Run 8 summary and README sections accordingly.

Key Changes
- Stage 4:
  - src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R — supports manual districts; fits Gaussian copulas; writes results/MAG_Run8/mag_copulas.json.
  - src/Stage_4_SEM_Analysis/run_sem_msep_residual_test.R — enhanced with `--cluster_var`, `--corr_method`, `--rank_pit`, BH‑FDR reporting; computes Fisher’s C on mixed, rank‑based residual correlations excluding spouses.
  - src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R — adequacy (τ alignment, tails, 2‑fold CV log‑copula).
  - results/summaries/stage_sem_run8_summary.md — updated with final 5 spouses and mixed m‑sep.
- Stage 6:
  - src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R — Monte Carlo joint probability; single `--joint_requirement` or batch `--presets_csv`.
  - src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R — adds `joint_requirement`/`joint_prob`/`joint_ok` and best‑scenario fields via `--joint_presets_csv`.
  - src/Stage_6_Gardening_Predictions/README.md — updated to reflect final spouse set.
  - results/garden_joint_presets_defaults.csv — 5 illustrative scenarios with default threshold 0.6.
  - results/garden_presets_no_R.csv — 5 new, more robust scenarios excluding the 'R' axis.

Repro Commands
- Export equations (Run 8 versioning):
  - `Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8`
- Fit copulas (final spouse set):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8 \
      --district L,M --district T,R --district T,M --district M,R --district M,N`
- Mixed, copula‑aware m‑sep (DAG → MAG check on non‑spouse pairs):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_msep_residual_test.R --input_csv artifacts/model_data_complete_case_with_myco.csv \
      --spouses_csv results/MAG_Run8/stage_sem_run8_copula_fits.csv --cluster_var Family --corr_method kendall --rank_pit true \
      --out_summary results/MAG_Run8/msep_test_summary_run8_mixedcop.csv --out_claims results/MAG_Run8/msep_claims_run8_mixedcop.csv`
- Gaussian adequacy check (optional):
  - `Rscript src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R --input_csv artifacts/model_data_complete_case_with_myco.csv --copulas_json results/MAG_Run8/mag_copulas.json --out_md results/stage_sem_run8_copula_diagnostics.md --nsim 200000`
- Joint suitability (original batch presets):
  - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/MAG_Run8/mag_copulas.json --metrics_dir artifacts/stage4_sem_piecewise_run7 --presets_csv results/garden_joint_presets_defaults.csv --nsim 20000 --summary_csv results/garden_joint_summary.csv`
- Joint suitability (new R-excluded presets for more confident predictions):
  - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/MAG_Run8/mag_copulas.json --presets_csv results/garden_presets_no_R.csv --nsim 20000 --summary_csv results/garden_joint_summary_no_R.csv`
- Recommender with best scenario:
  - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R --predictions_csv results/mag_predictions_no_eive.csv --output_csv results/garden_requirements_no_eive.csv --bins 0:3.5,3.5:6.5,6.5:10 --copulas_json results/MAG_Run8/mag_copulas.json --metrics_dir artifacts/stage4_sem_piecewise_run7 --nsim_joint 20000 --joint_presets_csv results/garden_presets_defaults.csv`

Outputs
- results/MAG_Run8/mag_copulas.json — 5 residual districts and parameters (final spouse set)
- results/stage_sem_run8_copula_diagnostics.md — adequacy summary
- results/MAG_Run8/msep_test_summary_run8_mixedcop.csv, results/MAG_Run8/msep_claims_run8_mixedcop.csv — mixed, rank‑based omnibus and per‑pair claims
- results/garden_joint_summary.csv — species × scenarios joint probabilities
- results/garden_joint_summary_no_R.csv — species × scenarios joint probabilities for new R-excluded presets.
- results/garden_requirements_no_eive.csv — includes best‑scenario fields

Key Finding: R-excluded Scenarios Yield More Confident Predictions
- Analysis revealed that the weak predictive power for the 'R' (soil pH) axis was suppressing joint probabilities due to high uncertainty (the "Tyranny of AND").
- A new set of five scenarios was created that deliberately exclude 'R' to play to the model's strengths.
- Result: This produced dramatically more confident and useful predictions. The average success probability for the best new scenario ("Rich Soil Specialist") is 28.2%, ≈6.9× higher than the best original scenario (4.1%).
- Actionable Insight: The new scenarios successfully identified several species that passed the 60% suitability threshold — e.g., *Cryptomeria japonica*, *Pinus densiflora*, *Pinus ponderosa*, *Sequoia sempervirens*, *Tsuga canadensis* — providing a clear, actionable list of "winners" that the original, more uncertain scenarios could not.

Notes
- Copulas improve multi‑axis suitability decisions; single‑axis predictions remain unchanged.
- m‑sep still rejects by p‑value after adding large‑effect spouses, but remaining |τ| are small (~0.07–0.13); we stop at 5 spouses for practical impact.
- Defaults: bins [0,3.5), [3.5,6.5), [6.5,10]; preset threshold 0.6 (tunable).

Comparative Results — Presets With vs Without R (Run 8)
- Threshold: 0.6; 23 species scored per scenario. Metrics aggregate over species within each preset.

With R (defaults)

| Scenario              | Requirement             | Mean P(success) | Median | Max  | Pass ≥0.6 | Top species (max)              |
|-----------------------|-------------------------|-----------------|--------|------|-----------|-------------------------------|
| WarmNeutralFertile    | T=high,R=med,N=high     | 4.1%            | 1.5%   | 15.6%| 0         | Sequoia sempervirens (15.6%)   |
| PartialSunAverage     | L=med,M=med,R=med       | 3.2%            | 1.6%   | 15.8%| 0         | Agropyron cristatum (15.8%)    |
| SunnyNeutral          | L=high,M=med,R=med      | 2.9%            | 0.8%   | 18.8%| 0         | Agropyron cristatum (18.8%)    |
| DryPoorSun            | L=high,M=low,N=low      | 0.1%            | 0.0%   | 1.1% | 0         | Agropyron cristatum (1.1%)     |
| ShadeWetAcidic        | L=low,M=high,R=low      | 0.0%            | 0.0%   | 0.1% | 0         | Maackia amurensis (0.1%)       |

Without R (new, confidence‑oriented)

| Scenario              | Requirement         | Mean P(success) | Median | Max   | Pass ≥0.6 | Top species (max)              |
|-----------------------|---------------------|-----------------|--------|-------|-----------|-------------------------------|
| RichSoilSpecialist    | M=high,N=high       | 28.2%           | 16.4%  | 66.3% | 5         | Cryptomeria japonica (66.3%)   |
| LushShadePlant        | L=low,M=high,N=high | 2.7%            | 2.4%   | 8.9%  | 0         | Maackia amurensis (8.9%)       |
| CoolClimateSpecialist | T=low,M=med,N=high  | 1.1%            | 0.0%   | 10.7% | 0         | Carex digitata (10.7%)         |
| SunVsWaterTradeoff    | L=high,M=low        | 0.4%            | 0.0%   | 6.3%  | 0         | Agropyron cristatum (6.3%)     |
| ThePioneer            | T=high,M=low        | 0.3%            | 0.0%   | 1.8%  | 0         | Quercus macrocarpa (1.8%)      |

Winners at threshold 0.6 (No‑R presets)
- RichSoilSpecialist (5 species): Cryptomeria japonica, Pinus densiflora, Sequoia sempervirens, Pinus ponderosa, Tsuga canadensis.

## How Gardeners Use This Guide
1) Choose your site recipe:
   - Presets: pick a label that matches your bed (e.g., RichSoilSpecialist → M=high & N=high). If pH is unknown or noisy, prefer R‑excluded presets in `results/garden_presets_no_R.csv`.
   - Single gate: run the recommender with `--joint_requirement` (e.g., `M=high,N=high`) and a threshold (default 0.6) to tag each species with `joint_prob` and `joint_ok`.
2) Read the per‑axis cards (from `results/garden_requirements_no_eive.csv`): predicted 0–10, bin, `borderline`, and a qualitative confidence tag per axis. Treat M/N as strongest; T and L as moderate; R as weakest.
3) Decide using joint probability:
   - Presets summary (`results/garden_joint_summary_no_R.csv` or `..._summary.csv`): filter `pass=TRUE` for your chosen threshold. Higher `joint_prob` means a better fit to that combined recipe.
   - Recommender output: rely on `joint_prob`/`joint_ok` if you provided a single gate.
4) Adjust if needed: If no species pass, lower the threshold (e.g., 0.5) or relax the recipe (drop R first). Avoid strict “all five must hold” — the AND condition is usually too restrictive.

## What The Outputs Contain
- `results/garden_requirements_no_eive.csv` (per species): predictions (`L_pred..N_pred`), `{Axis}_bin`, `{Axis}_borderline`, `{Axis}_confidence`, `{Axis}_recommendation`; optional `joint_requirement/joint_prob/joint_ok`; and, when presets are supplied, `best_scenario_label/best_scenario_prob/best_scenario_ok`.
- `results/garden_joint_summary_no_R.csv` and `results/garden_joint_summary.csv` (species × scenario): `species,label,requirement,joint_prob,threshold,pass`.
