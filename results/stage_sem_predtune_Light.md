# Pre‑Run 8 — Light (L) Predictive Focus

Goal — Improve out‑of‑sample prediction for Light (L) with small, testable tweaks while keeping the model interpretable and consistent with the MAG recommendation. 🌞

## Baseline (Run 7 piecewise, 10×5 CV)
- L: R² 0.237±0.060; RMSE 1.333±0.064; MAE 1.001±0.039 (n=1065)
- Current form: `L ~ LES + SIZE + logSSD + logLA`
- Composites/logs: `LES_core = PC1(-LMA, Nmass)`; `SIZE = PC1(logH, logSM)`; logs use natural log with stored offsets.

## Hypotheses and Tweaks (L only)
1) SIZE deconstruction
- Replace `SIZE` with `logH + logSM`:
  - Form: `L ~ LES + logH + logSM + logSSD + logLA`
  - Rationale: deconstruction helped M/N; may expose differential effects of height vs seed mass on L.
  - Adoption: keep whichever (SIZE vs logH+logSM) improves CV R²/MAE.

2) Interaction candidates (guarded)
- `LES:logSSD` — test if LES moderates SSD’s effect on L (kept for N; not previously for L).
- `LES:logLA` — test only if signs remain plausible and multicollinearity acceptable.
- Adoption: include only if ΔR² ≥ +0.02 or ΔMAE ≤ −0.03 with stable signs across folds.

3) Prune/confirm weak terms
- Single‑term ablations: drop `logSSD` or `logLA` individually and compare.
- Adoption: drop only if both R² and MAE improve (ΔR² ≥ +0.01 and ΔMAE ≤ −0.02).

4) Robustness knobs
- Winsorize predictors at 1%/99% (flag `--winsorize true`) and re‑evaluate.
- Verify log offsets for `LeafArea`, `PlantHeight`, `DiasporeMass`, `SSD` to avoid mass at zero (keep offsets minimal).

## Guardrails
- Keep LES in all variants (anchor predictor).
- No broad feature hunts; only the tweaks above.
- Prefer the simpler form when ties occur (fewer interactions, composite SIZE if equivalent).

## Repro Commands (L only; illustrative)
- Baseline reference:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
      --input_csv artifacts/model_data_complete_case_with_myco.csv \
      --target=L --repeats 5 --folds 10 --stratify true --standardize true \
      --winsorize false --les_components negLMA,Nmass --add_predictor logLA \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_baseline`

- SIZE deconstruction (B1):
  - `... --target=L --deconstruct_size true \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_B1_desize`

- Interaction tests (A):
  - `... --target=L --add_interaction LES:logSSD \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_A1_les_ssd`
  - `... --target=L --add_interaction LES:logLA \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_A2_les_la`

- Ablations (C1):
  - `... --target=L --drop_predictor logSSD \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_C1_drop_ssd`
  - `... --target=L --drop_predictor logLA \
      --out_dir artifacts/stage4_sem_piecewise_predtune/L_C1_drop_la`

- Winsorization (D1):
  - add `--winsorize true` to each variant above and re‑run for comparison.

Notes
- Use the same seeds/stratification as Run 7 for comparability (seed=42; 10×5 CV).
- Record per‑fold metrics; compute mean±SD for R², RMSE, MAE.

## Evaluation & Adoption (L)
- Adopt the best‑performing variant by primary threshold (ΔR² ≥ +0.02 or ΔMAE ≤ −0.03) without RMSE degradation.
- Coefficients should have consistent, ecologically plausible signs.
- Document final choice succinctly (to flow into Run 8 proposal’s mean structure).

## Expected Outcomes (L)
- Likely small but meaningful gains from SIZE deconstruction; interaction effects are possible but adopt conservatively.
- Target improvement: R² +0.02–0.03 or MAE −0.03–0.05 if a tweak helps.

## Deliverables
- `results/stage_sem_predtune_summary.md` — include a dedicated L section with Baseline vs Best Variant and the chosen specification.
- Update `results/stage_sem_run8_proposal.md` — mean‑structure line for L reflecting the adopted tweak (if any).
