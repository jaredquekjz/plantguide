# Stage 2 — Run-by-Run Summaries (for cross-check)

Date: 2025-08-15

Purpose: Summarize each Run 2–7 (+6P) exactly as reported to double-check the final recommendation. Emphasis on model forms (linear vs. deconstructed vs. nonlinear), grouping (Woodiness/Mycorrhiza), CV metrics, d-sep/SEM fit, and adoption notes.

## Run 2 — WES-backed SSD paths; baseline vs. deconstructed
- Focus: Add direct `SSD → {M,N,R}` in lavaan; in piecewise, keep direct `SSD → {M,N}`; probe woody-only SSD→{L,T,R} in multigroup d-sep.
- Grouping: Woodiness for inference; CV uses pooled data with train-only composites.
- Forms (piecewise): L/T/R linear_size (`y ~ LES + SIZE + logSSD`), M/N deconstructed (`y ~ LES + logH + logSM + logSSD`).
- CV (piecewise R² mean): L 0.231; T 0.218; M 0.398; R 0.143; N 0.409. Lavaan CV markedly lower by design (composite proxy).
- d-sep/lavaan fit: Allowing SSD paths reduces key violations; lavaan absolute fit remains suboptimal (CFI ~0.67–0.83 by group; RMSEA ~0.14–0.23), consistent with missing residual structure.
- Adoption note: Use deconstructed for M and N; keep linear_size for R; proceed to test nonlinearity and co-adaptation next.

## Run 3 — Mycorrhiza multigroup (reproduce Run 2 forms)
- Focus: Reproduce Run 2, adding mycorrhiza grouping (`Myco_Group_Final`) for inference only; CV forms unchanged.
- Grouping: Myco multigroup for d-sep/lavaan; CV pooled.
- Forms (piecewise): L/T/R linear_size; M/N deconstructed.
- CV (piecewise R² mean ± SD): L 0.232±0.044; T 0.227±0.043; R 0.145±0.041; M 0.399±0.050; N 0.415±0.056. Small gains vs. Run 2.
- d-sep: For R, targeted myco-specific SSD→R (Pure_NM, Low_Confidence) yields Fisher’s C p≈0.899.
- Adoption note: Keep forms; use myco-specific SSD→R in d-sep; no myco moderation needed for L/T/N.

## Run 4 — Co-adapted LES in lavaan (LES↔SIZE; LES↔logSSD)
- Focus: Replace directed inputs into LES with covariances in lavaan; piecewise unchanged. Myco grouping retained.
- Forms: CV still via composites; lavaan structural keeps `y ~ LES + SIZE` (+ SSD for M/N) with co-adaptation covariances.
- CV (lavaan proxy): Similar to Run 3. Global IC: large AIC/BIC decreases favor co-adaptation across L/M/R/N (T baseline unavailable).
- Fit indices: Mixed small shifts (CFI/TLI modest up/down; RMSEA/SRMR mixed), outweighed by IC deltas.
- Adoption note: Adopt co-adaptation in lavaan.

## Run 5 — LES×logSSD interaction in piecewise (+ full-model AIC/BIC)
- Focus: Add `LES:logSSD` to y-equations; compute full-model AIC/BIC (sum of submodels) per Douma & Shipley (2020).
- Forms (piecewise):
  - L/T/R: `y ~ LES + SIZE + logSSD + LES:logSSD`.
  - M/N: `y ~ LES + logH + logSM + logSSD + LES:logSSD` (deconstructed).
- CV (piecewise R² mean): L 0.235; T 0.235; M 0.405; R 0.149; N 0.420 (small gains across targets vs. Run 3).
- Full-model IC (Δ vs. no-interaction baseline): AIC_sum small penalties for L/T/M/R (|Δ| ≲ 4), modest support for N (−2.52). BIC_sum penalizes interaction except N (~+2.4).
- Adoption note: Keep `LES:logSSD` for N; optional for T (CV + Pagel λ support reported later); omit for L/M/R for parsimony.

## Run 6 — Systematic nonlinearity (spline on logH in y)
- Focus: Test `s(logH)` for R, M, N (L/T remain linear). Continue reporting full-model AIC/BIC sums (linear submodels).
- Forms (piecewise CV): R semi-nonlinear; M/N deconstructed with `s(logH)`; L/T unchanged linear.
- CV impact: Large degradations for M (R² ~0.128) and R (~0.054); moderate drop for N (~0.379). L/T ~unchanged.
- IC deltas: Favor simpler (reflect removal of interaction penalty for L/T/M/R; N unaffected since interaction retained).
- Adoption note: Reject splines; retain linear forms; keep `LES:logSSD` only for N.

## Run 6P — Phylogenetic sensitivity (GLS, Brownian; coefficients + IC)
- Focus: Full-data GLS with Brownian correlation; report submodel AIC/BIC sums and y-equation GLS coefficients.
- Results: Core directions stable (LES, SIZE/logH/logSM, logSSD). Magnitudes differ (GLS likelihood), but interpretations unchanged.
- Optional: Pagel’s λ GLS (reported alongside) supports `LES:logSSD` for T (ΔAIC_sum ≈ −7.15; p≈0.0025); others ns.
- Adoption note: Keep prior decisions; consider T-interaction optional based on tolerance for added complexity.

## Run 7 — LES_core + logLA as predictor (both runners)
- Focus: Refine LES measurement (two indicators: `negLMA`, `Nmass`) and include `logLA` directly in y; piecewise composites rebuilt accordingly.
- Forms (piecewise CV):
  - L/T/R: `y ~ LES + SIZE + logSSD + logLA` (linear_size; adds logLA, keeps logSSD).
  - M/N: `y ~ LES + logH + logSM + logSSD + logLA` (deconstructed; N keeps `+ LES:logSSD`).
- CV (piecewise R² mean ± SD): L 0.237±0.060; T 0.234±0.072; R 0.155±0.071; M 0.415±0.072; N 0.424±0.071 (rerun, deconstructed M/N reflected).
- Full-model IC (Δ vs. Run 6): Strongly lower sums for M (−16.4) and N (−19.0); small increases for L/T; mixed for R (AIC_sum −0.75, BIC_sum +4.21).
- Lavaan (single-group): N improves; L/T/M/R slightly worse; still acceptable given CV-first policy.
- Adoption note: Adopt LES_core and direct `logLA` in y; retain N interaction; keep linear forms elsewhere.

---

Consolidated takeaways across runs
- Deconstructed SIZE clearly improves M and N (Run 2/3/5/7), and remains the chosen form for those targets in CV-oriented modeling.
- Grouping: Mycorrhiza used for inference/d-sep and lavaan fits from Run 3 onward; CV forms remain pooled and unchanged.
- Interactions: Keep `LES:logSSD` only for N by default; optional for T (phylo support). Omit for L/M/R.
- Nonlinearity: Splines on logH degrade CV; reject.
- Lavaan co-adaptation: Improves information criteria; adopted for latent SEM inference pathway; not a driver for CV predictions.

References to source summaries
- results/stage_sem_run2_summary.md
- results/stage_sem_run3_summary.md
- results/stage_sem_run4_summary.md
- results/stage_sem_run5_summary.md
- results/stage_sem_run6_summary.md
- results/stage_sem_run6P_summary.md
- results/stage_sem_run7_summary.md

---

## Diff vs Final Recommendation

Below, “Final” refers to the adopted Run 7 piecewise forms with LES_core and direct `logLA`, linear models only, and `LES:logSSD` kept for N only.

Per-target diffs (forms):
- L: Run 2/3/5/6 used `L ~ LES + SIZE + logSSD`. Final: `L ~ LES + SIZE + logSSD + logLA` — keeps `logSSD`; adds `logLA`.
- T: Run 2/3/5/6 used `T ~ LES + SIZE + logSSD` (Run 5 optionally added `LES:logSSD`). Final: `T ~ LES + SIZE + logSSD + logLA` — keeps `logSSD`; no interaction by default.
- R: Run 2/3/5/6 used `R ~ LES + SIZE + logSSD` (Run 6 briefly tested spline). Final: `R ~ LES + SIZE + logSSD + logLA` — keeps `logSSD`; stays linear.
- M: Run 2/3/5/6 used deconstructed `M ~ LES + logH + logSM + logSSD`. Final (after rerun): `M ~ LES + logH + logSM + logSSD + logLA` — coefficients now reflect the deconstructed form in the full‑data PSEM output.
- N: Run 2/3 baseline deconstructed; Run 5 added `LES:logSSD`; Run 6 rejected splines. Final: `N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD` (deconstructed + interaction), matching Runs 5/7 policy.

Per-run diffs (policies):
- Grouping: Runs 2 used Woodiness; Runs 3–7 used Mycorrhiza grouping for inference (d‑sep/lavaan). Final predictive equations are pooled (no group terms). Causal checks stay grouped.
- Interaction: Run 5 tentatively across targets; final keeps it for N only; T remains optional (phylo support) but excluded by default.
- Nonlinearity: Run 6 splines on logH were rejected; final uses linear models only.
- Co‑adaptation (lavaan only): Adopted in Run 4; not relevant to piecewise predictive forms.

Actionable check:
- If strict deconstructed SIZE for M is required to mirror Runs 2/3/5, update the final M equation accordingly (see note above). Otherwise, accept Run 7 coefficients as the current source of truth.

## What Mycorrhiza Grouping Is For

- Purpose: Grouping (Myco_Group_Final) is used for causal diagnostics and inference — not for the pooled predictive equations used in CV and MAG. Specifically:
  - Multigroup d‑sep: tests whether key paths (e.g., `SSD → R`) differ by mycorrhiza; in Run 3 this resolved misfit for R by allowing group‑specific direct SSD→R in targeted groups.
  - Grouped lavaan fits: quantify absolute SEM fit and path stability by group; inform whether moderation is plausible, even if not carried into the pooled predictive model.
- Why not in the final equations: Cross‑validated performance and full‑model IC did not support broad inclusion of myco‑specific interaction terms in the pooled predictive equations. Adding them would increase complexity with minimal or no CV gains outside of the targeted R d‑sep fix. For MAG, we prioritize a single robust global predictor while retaining the grouped evidence for interpretation.
- How it’s used going forward: Keep the myco multigroup outputs alongside predictions to qualify causal statements and to report where effects are stronger/weaker (e.g., SSD→R in specific myco groups). If future CV/AIC show predictive gains from explicit myco interactions, we can elevate them into the predictive equations.
