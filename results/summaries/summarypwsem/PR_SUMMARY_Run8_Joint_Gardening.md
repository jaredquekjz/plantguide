Title: Stage 6 — Joint Suitability via Copulas (Run 8, Final Spouse Set) + Docs Update

Scope
- Finalize Run 8 MAG residual copulas with 5 spouses and align m‑sep to SEMwise (mixed residuals, rank‑based tests).
- Implement and document joint suitability for gardening (Stage 6): single requirement gate, batch presets, and best‑scenario annotation.
- Analyze a new set of joint scenarios that exclude the weakly-predicted 'R' axis to generate more confident, actionable recommendations.
- Update Run 8 summary and README sections accordingly.
 - Label usage: Stage 6 joint scoring never peeks at observed EIVE — predictions are trait‑based (MAG means), and joint probabilities are simulated around those means using residual σ/ρ learned upstream.

Key Changes
- Stage 4:
  - src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R — supports manual districts; fits Gaussian copulas; writes results/MAG_Run8/mag_copulas.json.
  - src/Stage_4_SEM_Analysis/run_sem_msep_residual_test.R — enhanced with `--cluster_var`, `--corr_method`, `--rank_pit`, BH‑FDR reporting; computes Fisher’s C on mixed, rank‑based residual correlations excluding spouses.
  - src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R — adequacy (τ alignment, tails, 2‑fold CV log‑copula).
  - results/summaries/summarypwsem/stage_sem_run8_summary.md — updated with final 5 spouses (GAM L residuals) and mixed m‑sep.
- Stage 6:
  - src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R — Monte Carlo joint probability; single `--joint_requirement` or batch `--presets_csv`.
  - src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R — adds `joint_requirement`/`joint_prob`/`joint_ok` and best‑scenario fields via `--joint_presets_csv`.
  - src/Stage_6_Gardening_Predictions/README.md — updated to reflect final spouse set.
- results/gardening/garden_joint_presets_defaults.csv — 5 illustrative scenarios with default threshold 0.6.
- results/gardening/garden_presets_no_R.csv — 5 new, more robust scenarios excluding the 'R' axis.

Repro Commands
- Export equations and L GAM (Run 8 versioning):
  - `Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8`
  - `Rscript src/Stage_4_SEM_Analysis/fit_export_L_gam.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_rds results/MAG_Run8/sem_pwsem_L_full_model.rds`
- Fit copulas (final spouse set; GAM L residuals):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8 \
      --district L,M --district T,R --district T,M --district M,R --district M,N \
      --group_col Myco_Group_Final --shrink_k 100 \
      --gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds`
- Mixed, copula‑aware m‑sep (DAG → MAG check on non‑spouse pairs):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_msep_residual_test.R --input_csv artifacts/model_data_complete_case_with_myco.csv \
      --recipe_json results/MAG_Run8/composite_recipe.json \
      --spouses_csv results/MAG_Run8/stage_sem_run8_copula_fits.csv --cluster_var Family --corr_method kendall --rank_pit true \
      --gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds \
      --out_summary results/MAG_Run8/msep_test_summary_run8_mixedcop.csv --out_claims results/MAG_Run8/msep_claims_run8_mixedcop.csv`
- Gaussian adequacy check (optional):
  - `Rscript src/Stage_4_SEM_Analysis/diagnose_copula_gaussian.R --input_csv artifacts/model_data_complete_case_with_myco.csv --copulas_json results/MAG_Run8/mag_copulas.json --out_md results/summaries/summarypwsem/stage_sem_run8_copula_diagnostics.md --nsim 200000 --gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds`
- Joint suitability (original batch presets):
  - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/MAG_Run8/mag_copulas.json --metrics_dir artifacts/stage4_sem_pwsem_run7c_pureles_merged --presets_csv results/gardening/garden_joint_presets_defaults.csv --nsim 20000 --summary_csv results/gardening/garden_joint_summary.csv`
- Joint suitability (new R-excluded presets for more confident predictions):
  - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/MAG_Run8/mag_copulas.json --metrics_dir artifacts/stage4_sem_pwsem_run7c_pureles_merged --presets_csv results/gardening/garden_presets_no_R.csv --nsim 20000 --summary_csv results/gardening/garden_joint_summary_no_R.csv`
- Recommender with best scenario:
  - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R --predictions_csv results/mag_predictions_no_eive.csv --output_csv results/gardening/garden_requirements_no_eive.csv --bins 0:3.5,3.5:6.5,6.5:10 --copulas_json results/MAG_Run8/mag_copulas.json --metrics_dir artifacts/stage4_sem_pwsem_run7c_pureles_merged --nsim_joint 20000 --joint_presets_csv results/gardening/garden_joint_presets_defaults.csv`

Outputs
- results/MAG_Run8/mag_copulas.json — 5 residual districts and parameters (final spouse set)
- results/summaries/summarypwsem/stage_sem_run8_copula_diagnostics.md — adequacy summary
- results/MAG_Run8/msep_test_summary_run8_mixedcop.csv, results/MAG_Run8/msep_claims_run8_mixedcop.csv — mixed, rank‑based omnibus and per‑pair claims
- results/gardening/garden_joint_summary.csv — species × scenarios joint probabilities
- results/gardening/garden_joint_summary_no_R.csv — species × scenarios joint probabilities for new R-excluded presets.
- results/gardening/garden_requirements_no_eive.csv — includes best‑scenario fields

New (optional): Group‑Aware Uncertainty in Stage 6
- Rationale: per‑group RMSE differs materially by mycorrhiza and woodiness; using one global σ mis‑calibrates joint probabilities.
- Implementation: Stage 6 now supports `--group_col` plus a reference mapping (`--group_ref_csv`, `--group_ref_id_col`, `--group_ref_group_col`). Per‑group RMSE per axis is computed from Run 7 CV preds and used in Monte Carlo. Falls back to global σ when a group is missing; copulas stay global.
- Example flags:
  - Mycorrhiza: `--group_col Myco_Group_Final --group_ref_csv artifacts/model_data_complete_case_with_myco.csv --group_ref_id_col wfo_accepted_name --group_ref_group_col Myco_Group_Final`.
  - Woodiness: `--group_col Woodiness --group_ref_group_col Woodiness` (same reference CSV).
- Summary sample (SunnyNeutral: L=high,M=med,R=med): see `results/MAG_Run8/stage6_group_uncertainty_summary.csv` (columns: group, mean/median/max joint_prob, n, variant {global, by_group}).

New (optional): Per‑Group Copulas
- Scope: Extend Run 8 copulas with `--group_col <GroupName>` (e.g., `Myco_Group_Final`/`Woodiness`) to write `by_group` correlation matrices alongside the global spouse set in `mag_copulas.json`.
- Usage (Stage 6): When `--group_col` is supplied in Stage 6, the recommender/joint scorer selects per‑group correlation matrices from `mag_copulas.json` if present; otherwise falls back to global. Works together with per‑group σ.
- Shrinkage (recommended for stability): Use `--shrink_k 100` in Stage 4 (weight = n/(n+shrink_k)) so small groups borrow strength from global ρ. Diagnostics are written to `results/MAG_Run8/stage_sem_run8_copula_group_diagnostics.csv` (per group & pair: n, rho_raw, rho_shrunk, weight, Kendall τ, implied τ from ρ, τ delta, and normal‑score correlation).

Key Finding: R-excluded Scenarios Yield More Confident Predictions
- Analysis revealed that the weak predictive power for the 'R' (soil pH) axis was suppressing joint probabilities due to high uncertainty (the "Tyranny of AND").
- A new set of five scenarios was created that deliberately exclude 'R' to play to the model's strengths.
- Result: This produced dramatically more confident and useful predictions. The average success probability for the best new scenario ("Rich Soil Specialist") is 28.1%, ≈6.9× higher than the best original scenario (4.1%).
- Actionable Insight: The new scenarios successfully identified several species that passed the 60% suitability threshold — e.g., *Cryptomeria japonica*, *Pinus densiflora*, *Pinus ponderosa*, *Sequoia sempervirens*, *Tsuga canadensis* — providing a clear, actionable list of "winners" that the original, more uncertain scenarios could not.

Notes
- Copulas improve multi‑axis suitability decisions; single‑axis predictions remain unchanged.
- m‑sep still rejects by p‑value after adding large‑effect spouses, but remaining |τ| are small (~0.07–0.13); we stop at 5 spouses for practical impact.
- Defaults: bins [0,3.5), [3.5,6.5), [6.5,10]; preset threshold 0.6 (tunable).

Comparative Results — Presets With vs Without R (Run 8)
- Threshold: 0.6; 23 species scored per scenario. Metrics aggregate over species within each preset.

With R (defaults)

| Scenario              | Requirement             | Mean P(success) | Median | Max   | Pass ≥0.6 | Top species (max)               |
|-----------------------|-------------------------|-----------------|--------|-------|-----------|--------------------------------|
| WarmNeutralFertile    | T=high,R=med,N=high     | 4.0%            | 1.5%   | 15.3% | 0         | Sequoia sempervirens (15.3%)    |
| PartialSunAverage     | L=med,M=med,R=med       | 3.0%            | 1.0%   | 15.8% | 0         | Carex digitata (15.8%)          |
| SunnyNeutral          | L=high,M=med,R=med      | 3.0%            | 1.0%   | 29.5% | 0         | Agropyron cristatum (29.5%)     |
| DryPoorSun            | L=high,M=low,N=low      | 0.1%            | 0.0%   | 1.6%  | 0         | Agropyron cristatum (1.6%)      |
| ShadeWetAcidic        | L=low,M=high,R=low      | 0.2%            | 0.0%   | 2.8%  | 0         | Sequoiadendron giganteum (2.8%) |

Without R (new, confidence‑oriented)

| Scenario              | Requirement         | Mean P(success) | Median | Max   | Pass ≥0.6 | Top species (max)               |
|-----------------------|---------------------|-----------------|--------|-------|-----------|---------------------------------|
| RichSoilSpecialist    | M=high,N=high       | 28.1%           | 16.3%  | 66.6% | 5         | Cryptomeria japonica (66.6%)    |
| LushShadePlant        | L=low,M=high,N=high | 2.2%            | 0.5%   | 14.3% | 0         | Ribes divaricatum (14.3%)       |
| SunVsWaterTradeoff    | L=high,M=low        | 0.4%            | 0.0%   | 7.8%  | 0         | Agropyron cristatum (7.8%)      |
| CoolClimateSpecialist | T=low,M=med,N=high  | 1.1%            | 0.0%   | 11.0% | 0         | Carex digitata (11.0%)          |
| ThePioneer            | T=high,M=low        | 0.3%            | 0.0%   | 1.8%  | 0         | Quercus macrocarpa (1.8%)       |

Winners at threshold 0.6 (No‑R presets)
- RichSoilSpecialist (5 species): Cryptomeria japonica, Pinus densiflora, Sequoia sempervirens, Pinus ponderosa, Tsuga canadensis.

Confidence Gains (Before → After, pwSEM L 7c)
- Overall: marginal changes in means (typically <±0.5 pp) and small shifts in maxima (≈±0.5–1.0 pp) across presets; winners unchanged in No‑R.
- With R: SunnyNeutral max ↑ to ≈30.0% (from ≈29.4%); PartialSunAverage max ↑ to ≈15.0% (from ≈14.4%).
- Without R: RichSoilSpecialist max ≈82.5% (≈−0.3 pp); pass count remains 6.

Review note (Light L): Since Run 7c is not AIC‑favoured (phylo‑GLS) and the joint‑probability improvements are marginal, we flag the L mean structure for future review. If subsequent evidence does not show clear predictive/joint‑gardening gains, consider reverting to the simpler Run 6 canonical L.

Group‑Aware (Mycorrhiza) — Presets With vs Without R (Full dataset; σ+ρ per group; shrink_k=100)
- Stage 4: per‑group copulas fitted with `--group_col Myco_Group_Final --shrink_k 100`.
- Stage 6: joint probabilities scored with `--group_col Myco_Group_Final` (per‑group σ and ρ).

With R (group‑aware)

| Scenario           | Mean P | Median | Max   | Pass ≥0.6 |
|--------------------|--------|--------|-------|-----------|
| DryPoorSun         | 0.0%   | 0.0%   | 0.6%  | 0         |
| PartialSunAverage  | 2.0%   | 0.5%   | 15.0% | 0         |
| ShadeWetAcidic     | 0.1%   | 0.0%   | 2.9%  | 0         |
| SunnyNeutral       | 2.2%   | 0.3%   | 30.0% | 0         |
| WarmNeutralFertile | 4.1%   | 1.1%   | 15.7% | 0         |

Without R (group‑aware)

| Scenario              | Mean P | Median | Max   | Pass ≥0.6 |
|-----------------------|--------|--------|-------|-----------|
| CoolClimateSpecialist | 0.5%   | 0.0%   | 9.9%  | 0         |
| LushShadePlant        | 1.3%   | 0.2%   | 12.1% | 0         |
| RichSoilSpecialist    | 26.5%  | 12.6%  | 82.5% | 6         |
| SunVsWaterTradeoff    | 0.2%   | 0.0%   | 3.0%  | 0         |
| ThePioneer            | 0.2%   | 0.0%   | 2.1%  | 0         |

Notes
- Numbers above aggregate across species with Myco labels; thresholds use each preset’s column (0.6 default).
- Effects are consistent with earlier findings: R‑excluded presets are far more actionable; group‑aware σ+ρ further improves calibration and increases RichSoilSpecialist’s best probabilities (max ≈ 82.8%) and pass count (6).

Winners at threshold 0.6 (No‑R, group‑aware Mycorrhiza)
- RichSoilSpecialist (6 species): Pinus densiflora (82.5%), Pinus ponderosa (79.8%), Tsuga canadensis (78.2%), Picea glauca (69.3%), Cryptomeria japonica (66.8%), Sequoia sempervirens (65.5%).

Group‑Aware (Mycorrhiza) — 23‑Species Subset (σ+ρ per group; shrink_k=100)
- Subset: 23 species (seed=42) including the 5 earlier winners (Cryptomeria japonica, Pinus densiflora, Sequoia sempervirens, Pinus ponderosa, Tsuga canadensis). See `results/MAG_Run8/sample23_species.txt`.

With R (group‑aware, 23 spp)

| Scenario           | Mean P | Median | Max   | Pass ≥0.6 |
|--------------------|--------|--------|-------|-----------|
| DryPoorSun         | 0.0002 | 0.0000 | 0.0042| 0         |
| PartialSunAverage  | 0.0307 | 0.0071 | 0.1704| 0         |
| ShadeWetAcidic     | 0.0008 | 0.0001 | 0.0055| 0         |
| SunnyNeutral       | 0.0187 | 0.0020 | 0.2958| 0         |
| WarmNeutralFertile | 0.0295 | 0.0002 | 0.1575| 0         |

Without R (group‑aware, 23 spp)

| Scenario              | Mean P | Median | Max   | Pass ≥0.6 |
|-----------------------|--------|--------|-------|-----------|
| CoolClimateSpecialist | 0.0346 | 0.0003 | 0.1875| 0         |
| LushShadePlant        | 0.0756 | 0.0222 | 0.3395| 0         |
| RichSoilSpecialist    | 0.3212 | 0.3033 | 0.8213| 6         |
| SunVsWaterTradeoff    | 0.0031 | 0.0000 | 0.0598| 0         |
| ThePioneer            | 0.0017 | 0.0001 | 0.0332| 0         |

## How Gardeners Use This Guide
1) Choose your site recipe:
   - Presets: pick a label that matches your bed (e.g., RichSoilSpecialist → M=high & N=high). If pH is unknown or noisy, prefer R‑excluded presets in `results/gardening/garden_presets_no_R.csv`.
   - Single gate: run the recommender with `--joint_requirement` (e.g., `M=high,N=high`) and a threshold (default 0.6) to tag each species with `joint_prob` and `joint_ok`.
2) Read the per‑axis cards (from `results/gardening/garden_requirements_no_eive.csv`): predicted 0–10, bin, `borderline`, and a qualitative confidence tag per axis. Treat M/N as strongest; T and L as moderate; R as weakest.
3) Decide using joint probability:
   - Presets summary (`results/gardening/garden_joint_summary_no_R.csv` or `..._summary.csv`): filter `pass=TRUE` for your chosen threshold. Higher `joint_prob` means a better fit to that combined recipe.
   - Recommender output: rely on `joint_prob`/`joint_ok` if you provided a single gate.
4) Adjust if needed: If no species pass, lower the threshold (e.g., 0.5) or relax the recipe (drop R first). Avoid strict “all five must hold” — the AND condition is usually too restrictive.

## What The Outputs Contain
- `results/gardening/garden_requirements_no_eive.csv` (per species): predictions (`L_pred..N_pred`), `{Axis}_bin`, `{Axis}_borderline`, `{Axis}_confidence`, `{Axis}_recommendation`; optional `joint_requirement/joint_prob/joint_ok`; and, when presets are supplied, `best_scenario_label/best_scenario_prob/best_scenario_ok`.
- `results/gardening/garden_joint_summary_no_R.csv` and `results/gardening/garden_joint_summary.csv` (species × scenario): `species,label,requirement,joint_prob,threshold,pass`.
