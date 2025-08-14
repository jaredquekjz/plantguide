# SEM Stage 4: Runs 4–7 — Amended Proposal

Divination: proposal reviewed; weaving precise next runs; next: execution.

## Guiding Spells (Principles)
- Minimal intervention: keep Run 3 settings; change only what the action requires.
- Pattern match: mirror prior conventions (paths, flags, outputs).
- Verification: cross-validated metrics for piecewiseSEM; global fit for lavaan.
- Clear incantations: explicit flags, deterministic seeds, printed params.

## Run 4 — Co‑adapted Spectra in lavaan (Action 2)
- Goal: Test LES and SIZE as co‑adapted (correlated) rather than causal.
- Action mapping: Remove directed paths into `LES` from `SIZE`/`logSSD`; add covariances: `LES ~~ SIZE`, `LES ~~ logSSD`. Keep Myco grouping identical to Run 3 and filter groups with `n >= 30` for stable group fits.
- Script change (lavaan):
  - Add a toggle to structural spec (e.g., `--coadapted_les_size true`) that:
    - Drops `LES ~ SIZE + logSSD` (or equivalent directed inputs).
    - Adds `LES ~~ SIZE` and `LES ~~ logSSD` to the model string.
  - Ensure grouped fitting via `--group_var Myco_Group_Final` and `--min_group_n 30`.
  - Preserve all other Run 3 defaults (measurement model, predictors, CV settings, seeds).
- Repro command (lavaan):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R \
    --input_csv artifacts/model_data_complete_case_with_myco.csv \
    --group_var Myco_Group_Final \
    --min_group_n 30 \
    --coadapted_les_size true \
    --output_dir artifacts/stage4_sem_lavaan_run4 \
    --save_paths true --save_metrics true --seed 42`
- Outputs: `artifacts/stage4_sem_lavaan_run4/sem_lavaan_{L,T,M,R,N}_{metrics.json,path_coefficients.csv,preds.csv}`.
- Comparison: Against Run 3 lavaan. Focus on CFI, TLI, RMSEA, SRMR (expect ΔCFI↑, RMSEA↓ if co‑adaptation helps). Keep piecewise untouched.
- Adoption rule: Prefer co‑adapted if it improves global fit without degrading predictive CV materially.

## Run 5 — LES×logSSD Interaction in piecewiseSEM (Action 3)
- Goal: Test if `LES:logSSD` improves predictive power.
- Action mapping: Add `LES*logSSD` to each target’s component model, retaining Run 3 structures (SIZE deconstructed for M and N; linear SIZE for L/T/R).
- Script change (piecewise):
  - Add a flag (e.g., `--add_interaction LES:logSSD`) to inject `LES*logSSD` into target formulas.
  - Keep Myco grouping and all Run 3 preprocessing, CV folds, and seeds identical.
- Repro command (piecewise):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
    --input_csv artifacts/model_data_complete_case_with_myco.csv \
    --group_var Myco_Group_Final \
    --add_interaction LES:logSSD \
    --output_dir artifacts/stage4_sem_piecewise_run5 \
    --cv_k 10 --seed 42 --save_metrics true --save_preds true`
- Outputs: `artifacts/stage4_sem_piecewise_run5/sem_piecewise_{L,T,M,R,N}_{metrics.json,piecewise_coefs.csv,preds.csv}`.
- Comparison: Against Run 3 piecewise CV metrics (R², RMSE, MAE). Recommend retaining the interaction only where CV improves.

## Run 6 — Systematic Nonlinearity (Action 4)
- Goal: Check for nonlinear effects in key predictors within piecewiseSEM.
- Action mapping: Starting from the best Run 5 structure, replace linear `logH` and `logSSD` with penalized splines and assess CV.
- Script change (piecewise):
  - Add a flag (e.g., `--nonlinear_terms logH,logSSD` and `--spline_basis ts`) to wrap specified terms with `s(term, bs="ts")` in GAM components.
  - Keep seeds, folds, Myco grouping, and other controls fixed.
- Repro command (piecewise):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
    --input_csv artifacts/model_data_complete_case_with_myco.csv \
    --group_var Myco_Group_Final \
    --from_run artifacts/stage4_sem_piecewise_run5 \
    --nonlinear_terms logH,logSSD --spline_basis ts \
    --output_dir artifacts/stage4_sem_piecewise_run6 \
    --cv_k 10 --seed 42 --save_metrics true --save_preds true`
- Outputs: `artifacts/stage4_sem_piecewise_run6/sem_piecewise_{L,T,M,R,N}_{metrics.json,piecewise_coefs.csv,preds.csv}`.
- Comparison: Against Run 5 CV metrics. Adopt splines per-target only if clear improvement.

## Run 7 — Refined LES Measurement (Action 6)
- Goal: Test a “purer” LES by restricting indicators and freeing `logLA` as a direct predictor.
- Action mapping:
  - lavaan: Use `LES_core =~ negLMA + Nmass`; move `logLA` to structural part as a direct predictor to EIVE targets.
  - piecewise: Recompute LES composite from `negLMA` and `Nmass` only; add `logLA` as an explicit predictor in component formulas.
- Script changes:
  - lavaan: Add `--les_core true --les_core_indicators negLMA,Nmass --logLA_as_predictor true` to adjust measurement/structural blocks.
  - piecewise: Add `--les_components negLMA,Nmass --add_predictor logLA` and document the composite recipe in outputs.
- Repro commands:
  - lavaan: `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R \
      --input_csv artifacts/model_data_complete_case_with_myco.csv \
      --group_var Myco_Group_Final --min_group_n 30 \
      --coadapted_les_size true \
      --les_core true --les_core_indicators negLMA,Nmass --logLA_as_predictor true \
      --output_dir artifacts/stage4_sem_lavaan_run7 \
      --save_paths true --save_metrics true --seed 42`
  - piecewise: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
      --input_csv artifacts/model_data_complete_case_with_myco.csv \
      --group_var Myco_Group_Final \
      --les_components negLMA,Nmass --add_predictor logLA \
      --output_dir artifacts/stage4_sem_piecewise_run7 \
      --cv_k 10 --seed 42 --save_metrics true --save_preds true`
- Outputs: `artifacts/stage4_sem_{lavaan,piecewise}_run7/...` parallel to prior runs.
- Comparison: lavaan vs Run 4 (fit indices); piecewise vs Run 6 (CV metrics).

## Documentation and Deliverables
- For each run, write a summary in `results/` following the exact template of `results/stage_sem_run3_summary.md`:
  - Scope, Methodology (explicit model equations/paths), Repro Commands, Final Results (key metrics), and Comparison to the prior relevant run.
  - Filenames: `results/stage_sem_run{4,5,6,7}_summary.md`.
- Keep artifacts under `artifacts/stage4_sem_{lavaan,piecewise}_run{4,5,6,7}/`.

## Assumptions and Effective Parameters
- Encoding: UTF‑8; CV folds: `cv_k=10`; Seed: `42`; Mycorrhiza grouping: `Myco_Group_Final`; Group stability for lavaan: `min_group_n=30`.
- Piecewise targets retain Run 3 structures except where the action explicitly modifies terms.
- Directed vs. covariance switches only affect lavaan structural relations among LES, SIZE, and logSSD.

## Adoption Rules (Per‑Run)
- Run 4: adopt if CFI/TLI increase and RMSEA/SRMR decrease without instability.
- Run 5: adopt `LES:logSSD` only for targets where CV R²↑ and RMSE/MAE↓.
- Run 6: adopt splines per‑term and per‑target only if CV improves clearly and residuals look better.
- Run 7: adopt LES_core if lavaan fit improves and piecewise CV does not regress; otherwise revert.

## Potential Curses (Risks) and Dispel Spells
- Group imbalance in lavaan: filter with `--min_group_n 30` (or raise) and report excluded groups.
- Overfitting with interactions/splines: rely on CV; keep penalties (`bs="ts"`) and document EDF.
- Script parity: ensure flags are no‑ops when unset; print final model strings to logs for reproducibility.

---

Intended next action: execute Run 4 with the lavaan co‑adaptation toggle and generate `results/stage_sem_run4_summary.md` with a strict comparison to Run 3 lavaan fit.

"Rationale: Replacing ambiguous directional links between LES and SIZE/logSSD with covariances better reflects co‑adaptation, often improving absolute fit in SEM. The interaction and nonlinearity tests proceed only if they earn their keep in CV. Key logic changes are limited to: (1) dropping "LES ~ SIZE + logSSD", (2) adding "LES ~~ SIZE" and "LES ~~ logSSD", (3) injecting "LES*logSSD" into piecewise formulas, and (4) wrapping `logH`/`logSSD` in "s()" for GAM tests."
