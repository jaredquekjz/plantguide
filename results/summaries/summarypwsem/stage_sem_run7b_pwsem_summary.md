# Stage 2 — SEM Run 7b (pwSEM): L gains via deconstructed SIZE + 2‑D surfaces

Date: 2025-08-23

Scope: Tier‑1 Light (L) improvements with minimal churn. We kept the Run 7 canonical scaffolding and targeted three changes: (1) upgrade overtopping interaction to a smooth surface, (2) deconstruct SIZE for L to height, and (3) test a Beta likelihood for bounded L. All runs use the same 10×5 CV protocol.

Status: exploratory — not final. Results below are candidates pending Tier‑2 checks (gating, location–scale) and paired‑fold significance tests.

Changes
- Surfaces: ti(logLA,logH) and ti(logH,logSSD) (shrinkable, bs="ts", small k).
- SIZE deconstruction for L: replace s(SIZE) → s(logH) in the L node only.
- Likelihood: optional Beta (betar) with safe (0,1) scaling, predictions reported on 0–10 scale.

Data and settings
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}`; we modify L only here.
- CV: 10‑fold × 5 repeats; stratified by deciles; standardized predictors; no winsorization; cluster random intercept by `Family` where available.
- Composites: LES = PC1 on `{negLMA, Nmass}`; SIZE = PC1 on `{logH, logSM}` (training‑only); for L, a deconstructed option (`s(logH)` in place of `s(SIZE)`).
 - Ceiling reference (EBM, Light only): R² 0.300±0.044; RMSE 1.278±0.042; MAE 0.971±0.033 (10×5 CV; `artifacts/stage3ebm/eive_ebm_L_metrics.json`).

Experiments (all rf_plus)
- A: L with ti(logLA,logH) + ti(logH,logSSD) (SIZE intact)
  - Cmd: `--add_interaction='ti(logLA,logH),ti(logH,logSSD)'`
  - Out: `artifacts/stage4_sem_pwsem_run7b_pureles_L_A/`
- B: A + deconstruct SIZE for L → `s(logH)`
  - Cmd: `--deconstruct_size_L=true --add_interaction='ti(logLA,logH),ti(logH,logSSD)'`
  - Out: `artifacts/stage4_sem_pwsem_run7b_pureles_L_B/`
 - C: B + Beta likelihood (betar)
  - Cmd: `--deconstruct_size_L=true --likelihood=betar --add_interaction='ti(logLA,logH),ti(logH,logSSD)'`
  - Out: `artifacts/stage4_sem_pwsem_run7b_pureles_L_C/`
 - G1 (Tier‑2 gating): B + by‑smooth on logLA gated by train‑fold height threshold (80th pct)
   - Cmd: `--deconstruct_size_L=true --gate_height=true --gate_percentile=0.80 --add_interaction='ti(logLA,logH),ti(logH,logSSD)'`
   - Out: `artifacts/stage4_sem_pwsem_run7b_pureles_L_G1/`
 - S1 (Tier‑2 location–scale): B + gaulss with σ ~ s(logH) + s(logLA)
   - Cmd: `--deconstruct_size_L=true --likelihood=gaulss --add_interaction='ti(logLA,logH),ti(logH,logSSD)'`
   - Out: `artifacts/stage4_sem_pwsem_run7b_pureles_L_S1/`

Cross‑validated Performance (L; mean ± SD)
- Canonical Run 7 (rf_plus): R² 0.289±0.083; RMSE 1.286±0.096; MAE 0.969±0.071 (n=1065)
- 7b‑A (ti only): R² 0.290±0.079; RMSE 1.284±0.091; MAE 0.973±0.068 (n=1065)
- 7b‑B (ti + deconstructed SIZE): R² 0.300±0.077; RMSE 1.276±0.092; MAE 0.968±0.067 (n=1065)
- 7b‑C (7b‑B + Beta): R² 0.300±0.074; RMSE 1.276±0.088; MAE 0.967±0.064 (n=1065)
- 7b‑G1 (B + gating): R² 0.299±0.076; RMSE 1.277±0.092; MAE 0.968±0.065 (n=1065)
- 7b‑S1 (B + gaulss): R² 0.300±0.077; RMSE 1.276±0.092; MAE 0.968±0.067 (n=1065)

Interpretation
- ti(logLA,logH) alone holds the earlier +0.009 signal we observed; upgrading logH:logSSD → ti(logH,logSSD) keeps performance stable.
- Deconstructing SIZE for L (use s(logH)) is the main driver: +0.011 absolute R² vs canonical, matching the EBM ceiling (~0.300) with the SEM structure intact.
- Beta likelihood keeps the mean R² at ~0.300 while slightly tightening variance across folds (smaller SDs for R²/RMSE/MAE), consistent with bounded response behavior.
- Gating (7b‑G1) at 80th‑percentile height is neutral on mean R² (Δ≈−0.0006 vs 7b‑B; paired ΔR² mean −0.0006, sd 0.0064). We’ll revisit with tuned percentiles or alternative by‑smooths if needed.
- Location–scale (7b‑S1) matches 7b‑B on mean metrics; we’ll prefer 7b‑C if tighter CV variance is desired with fewer moving parts.

Provisional recommendation (not adopted yet)
- Candidate mean structure for L: rf_plus with `s(logH)` (in place of `s(SIZE)`) and `ti(logLA,logH) + ti(logH,logSSD)` (7b‑B). Hold until Tier‑2 confirms robustness.
- Beta likelihood (7b‑C) is optional; keep Gaussian as default unless Tier‑2 shows stable benefits without side effects.

Next steps — Tier‑2 checks (planned)
- Height gating (understory/canopy): add soft by‑smooths keyed to a train‑fold threshold `h*` (e.g., 75–85th percentile of logH). Keep bases shrinkable; limit added terms.
- Location–scale GAM (gaulss): model variance as `σ ~ s(logH) + s(logLA)` while keeping the mean spec from 7b‑B.
- Paired‑fold tests: run a paired test across the same 50 folds vs 7b‑B. Promote changes only if ΔR² ≥ +0.015 with p<0.05, or ΔR² ≥ +0.010 with lower RMSE and reduced fold variance.

Repro commands
```bash
# A — ti(logLA,logH) + ti(logH,logSSD)
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv=artifacts/model_data_complete_case_with_myco.csv \
  --target=L --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=true --nonlinear_variant=rf_plus \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_run7b_pureles_L_A

# B — A + deconstructed SIZE for L
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  ... --deconstruct_size_L=true \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_run7b_pureles_L_B

# C — B + Beta likelihood
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  ... --deconstruct_size_L=true --likelihood=betar \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_run7b_pureles_L_C
```

Artifacts
- 7b‑A: `artifacts/stage4_sem_pwsem_run7b_pureles_L_A/sem_pwsem_L_{metrics.json,preds.csv,...}`
- 7b‑B: `artifacts/stage4_sem_pwsem_run7b_pureles_L_B/sem_pwsem_L_{metrics.json,preds.csv,...}`
- 7b‑C: `artifacts/stage4_sem_pwsem_run7b_pureles_L_C/sem_pwsem_L_{metrics.json,preds.csv,...}`

Notes
- Shrinkage: new 2‑D surfaces use `bs='ts'` so unhelpful terms self‑shrink; `k` kept small (4–5) via defaults.
- Scaling for Beta: L scaled to (0,1) inside folds; predictions converted back to 0–10 for metrics.
- Other axes (T/M/R/N): unchanged from Run 7 canonical.
- Paired fold deltas (vs 7b‑B; 50 folds): G1 ΔR² mean −0.0006 (approx. p≈0.50); S1 ΔR² mean ≈ 0.0000.
 - Paired fold deltas (7b‑C vs 7b‑B; 50 folds): ΔR² mean +0.00013 (approx. p≈0.94) — Beta is neutral on mean R², slightly reduces CV SD.
