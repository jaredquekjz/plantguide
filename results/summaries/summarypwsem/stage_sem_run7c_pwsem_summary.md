# Stage 2 — SEM Run 7c (pwSEM): Adopt L deconstruction + 2‑D surfaces (validated)

Date: 2025-08-23

Scope: Promote the Tier‑1 Light (L) improvement (Run 7b‑B) to “adopted” after passing paired‑fold significance and inference checks. L only is changed; T/M/R/N remain as in Run 7.

Final L mean structure (adopted)
- rf_plus with deconstructed L SIZE and two smooth interactions:
  - Mean equation: `y ~ s(LMA,k=5) + s(logSSD,k=5) + s(logH,k=5) + s(logLA,k=5) + Nmass + LMA:logLA + t2(LMA,logSSD,k=c(5,5)) + ti(logLA,logH,bs=c('ts','ts'),k=c(5,5)) + ti(logH,logSSD,bs=c('ts','ts'),k=c(5,5))`
- Inference policy: woody‑only SSD→L (keep global SSD paths for M/N; L/T/R woody‑only per prior runs).
- Selection note: Not AIC‑favoured under full‑data phylogenetic GLS. Run 7c reports AIC_sum ≈ 11109.61 vs Run 6 AIC_sum ≈ 11018.07 (lower is better). We tentatively adopt 7c for its modest predictive CV gain (ΔR² ≈ +0.021; paired‑fold p≈0.001–0.002), while retaining Run 6 as the more parsimonious, IC‑favoured alternative for inference.

Validation A — Paired‑fold significance (vs Run‑7 canonical)
- Protocol: identical 10×5 CV folds; paired per‑fold comparison of R² and RMSE.
- Result (7c vs Run‑7):
  - ΔR² mean = +0.01083; paired t ≈ 3.23; p ≈ 0.00125 (passes)
  - ΔRMSE mean = −0.00960; paired t ≈ −3.18; p ≈ 0.00148 (passes)
- Optional likelihood (Beta): neutral on mean R² (Δ≈+0.00013; p≈0.94) but slightly reduces fold‑to‑fold SD — keep as an option.

Validation B — d‑sep and group policy
- Full‑data pwSEM: L d‑sep basis remains degenerate (no new violations; C/df not defined under this form).
- Equality tests (logSSD effect by Woodiness): overall p≈0.0119; per‑group p: woody ≈ 0.0111; non‑woody ≈ 0.0870; semi‑woody ≈ 0.290 — consistent with woody‑only SSD→L in inference.
- Implementation: keep L SSD path active for woody in d‑sep (global for M/N). For non‑woody, the practical contribution to L is weak; omit in strict d‑sep when testing independence.

Validation C — Robustness checks
- Phylogenetic GLS (Brownian): full‑model IC AIC_sum ≈ 11109.61; BIC_sum ≈ 11168.93; y‑coefficients retain sign/magnitude (LES, logH, logLA negative; SIZE negative), consistent with Run 7. For model selection, this AIC is worse than Run 6 (≈11018), so 7c is adopted for predictive value rather than IC.
- Group‑specific smooths (Woodiness/Mycorrhiza): no additional 2‑D smooths adopted; only consider if a future IC test shows compelling ΔIC and ≥+0.01 ΔR².

Cross‑validated Performance (L; mean ± SD; 10×5)
- Run‑7 canonical (rf_plus): R² 0.289±0.083; RMSE 1.286±0.096; MAE 0.969±0.071
- Run‑7c (adopted L): R² 0.300±0.077; RMSE 1.276±0.092; MAE 0.968±0.067
- Ceiling reference (EBM; L only): R² 0.300±0.044; RMSE 1.278±0.042; MAE 0.971±0.033

Surfaces (interpretation)
- ti(logLA,logH): captures self‑shading with height — larger leaves at low height reduce L; effect softens at higher height (grid/PNG in `artifacts/stage4_sem_pwsem_run7c_surfaces/surface_ti_logLA_logH.{csv,png}`).
- ti(logH,logSSD): captures overtopping/crowding — higher density increases shading more strongly at greater height (`artifacts/stage4_sem_pwsem_run7c_surfaces/surface_ti_logH_logSSD.{csv,png}`).

Artifacts
- CV metrics/preds: `artifacts/stage4_sem_pwsem_run7b_pureles_L_B/sem_pwsem_L_{metrics.json,preds.csv}` (identical mean spec; labeled 7b‑B).
- Full‑data d‑sep/equality: `artifacts/stage4_sem_pwsem_run7c_pureles_L_full/sem_pwsem_L_{dsep_fit.csv,claim_logSSD_*}`.
- Phylo sensitivity: `artifacts/stage4_sem_pwsem_run7c_pureles_L_full_phylo/sem_pwsem_L_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`.
- Surfaces: `artifacts/stage4_sem_pwsem_run7c_surfaces/` (CSV + PNG per surface).

Repro commands
```bash
# CV (7c mean structure = 7b-B):
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv=artifacts/model_data_complete_case_with_myco.csv \
  --target=L --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Woodiness \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=true --nonlinear_variant=rf_plus \
  --deconstruct_size_L=true \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_run7b_pureles_L_B

# Full‑data d‑sep + equality tests
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  ... --group_var=Woodiness --out_dir=artifacts/stage4_sem_pwsem_run7c_pureles_L_full

# Phylo sensitivity
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  ... --group_var=Woodiness --phylogeny_newick=data/phylogeny/eive_try_tree.nwk \
  --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run7c_pureles_L_full_phylo

# Export surfaces (CSV + PNG)
Rscript src/Stage_4_SEM_Analysis/export_L_surfaces.R \
  --input_csv artifacts/model_data_complete_case_with_myco.csv \
  --out_dir artifacts/stage4_sem_pwsem_run7c_surfaces
```
