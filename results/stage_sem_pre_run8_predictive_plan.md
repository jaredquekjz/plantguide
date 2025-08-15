# Pre‑Run 8 — Predictive Improvements Plan (Targeted, Minimal Changes)

Purpose — Before Run 8 (MAG + copulas), squeeze extra out‑of‑sample predictive strength from the mean structure using small, testable tweaks with strict CV evaluation. 🌱

## Baseline (Run 7 piecewise, 10×5 CV)
- L: R² 0.237±0.060; RMSE 1.33±0.06; MAE 1.00±0.04
- T: R² 0.234±0.072; RMSE 1.15±0.08; MAE 0.86±0.05
- R: R² 0.155±0.071; RMSE 1.43±0.08; MAE 1.08±0.05
- M: R² 0.415±0.072; RMSE 1.15±0.08; MAE 0.89±0.05
- N: R² 0.424±0.071; RMSE 1.42±0.09; MAE 1.14±0.07

Priority: R (weakest), then L/T (modest), keep M/N stable (already best).

## Tweak Set A — Interactions (surgical)
- A1: Enable `LES:logSSD` for T (kept for N; optional for T in prior runs).
  - Rationale: SSD shows systematic effects; LES modifies SSD response for N — test if T benefits similarly.
- A2: Test `LES:logLA` for R only (guarded, adopt only if CV improves and signs are stable).

## Tweak Set B — SIZE handling in L/T/R
- B1: Deconstruct SIZE for L/T/R: replace `SIZE` with `logH + logSM` and compare vs composite.
  - Rationale: M/N improved with deconstruction; test if variance reduction helps L/T/R.
- Decision rule: keep per‑target variant (composite vs deconstructed) that improves CV R²/MAE.

## Tweak Set C — Prune or confirm weak terms
- C1: For R (and L/T if indicated), run ablations:
  - Drop `logSSD` or `logLA` individually; adopt drop only if both R² and MAE improve (ΔR² ≥ +0.01 and ΔMAE ≤ −0.02).
  - Keep LES always (anchor predictor).

## Tweak Set D — Robustness knobs (lightweight)
- D1: Winsorization on predictors at 1%/99% (flag: `--winsorize=true`) — adopt only if all targets do not degrade (no target worse by ΔR² < −0.01).
- D2: Check log offsets sanity for `LeafArea`, `PlantHeight`, `DiasporeMass`, `SSD` — ensure no mass at zero after transform; adjust offsets minimally if needed.

## Guardrails
- Avoid overfitting: no broad feature hunts; only A–D above.
- Adoption threshold (per target):
  - Primary: ΔR² ≥ +0.02 or ΔMAE ≤ −0.03 with consistent sign across folds.
  - Secondary: RMSE does not worsen; coefficients keep expected signs.

## Repro Commands (illustrative)
- Baseline (for reference):
  - L/T/R: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target={L|T|R} --input_csv artifacts/model_data_complete_case_with_myco.csv --repeats 5 --folds 10 --stratify true --standardize true --winsorize false --les_components negLMA,Nmass --add_predictor logLA --out_dir artifacts/stage4_sem_piecewise_predtune/baseline`
  - M/N: `... --target={M|N} --deconstruct_size true [--add_interaction LES:logSSD@N]`
- Tweak A1 (T interaction):
  - `... --target=T --add_interaction LES:logSSD --out_dir artifacts/.../T_A1_les_ssd`
- Tweak A2 (R interaction):
  - `... --target=R --add_interaction LES:logLA --out_dir artifacts/.../R_A2_les_la`
- Tweak B1 (deconstruct SIZE for L/T/R):
  - `... --target=L --deconstruct_size true --out_dir artifacts/.../L_B1_desize`
  - `... --target=T --deconstruct_size true --out_dir artifacts/.../T_B1_desize`
  - `... --target=R --deconstruct_size true --out_dir artifacts/.../R_B1_desize`
- Tweak C1 (ablations):
  - `... --target=R --drop_predictor logSSD --out_dir artifacts/.../R_C1_drop_ssd`
  - `... --target=R --drop_predictor logLA --out_dir artifacts/.../R_C1_drop_la`
- Tweak D1 (winsorization):
  - add `--winsorize true` to the above commands and re‑run to compare.

Notes
- Use the same seeds/stratification as Run 7 for comparability.
- Keep per‑target best variant; do not force a single global form if target‑wise CV disagrees.

## Evaluation & Adoption
- Report a compact table per target with Baseline vs Best Variant (R², RMSE, MAE ± SD).
- If multiple tweaks tie, prefer the simpler specification (fewer interactions, composite SIZE if equivalent).
- Record adopted forms into the Run 8 proposal as the finalized mean structure.

## Expected Outcomes
- R: +0.02–0.04 R² via SIZE deconstruction or a small interaction; modest MAE drop.
- T: +0.01–0.03 R² via `LES:logSSD` or deconstruction; small MAE drop.
- L: neutral to +0.02 R² via deconstruction; otherwise unchanged.
- M/N: unchanged (guard against regressions).

## Deliverables
- `results/stage_sem_predtune_summary.md` — per‑target deltas and the adopted choices.
- Updated `results/stage_sem_run8_proposal.md` mean structure lines reflecting adopted tweaks.

## After Adoption
- Proceed to Run 8: fit copulas on residuals of the adopted mean structure; update `mag_copulas.json`; re‑export MAG vNext and re‑apply Stage 5.
