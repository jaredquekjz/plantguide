# Stage 2 — SEM Run 3: Mycorrhiza Multigroup (Final, aligned with Run 2)

Date: 2025-08-14

Scope: Run 3 reproduces Run 2 models and parameters, adding only mycorrhiza grouping (`Myco_Group_Final`) for inference. All CV modeling forms match Run 2 (M/N deconstructed SIZE; L/T/R linear SIZE).

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete-case six traits; n≈1,068; 832 species annotated with `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (exact match to Run 2; Myco grouping only)
- Preprocessing: log10 transforms on Leaf area, Plant height, Diaspore mass, SSD used (small positive offsets recorded); z-score within folds; 5×5 repeated CV (seed=123; decile-stratified); no winsorization; no weights.
- piecewiseSEM (CV + d-sep):
  - Composites via training-only PCA: LES ≈ (−LMA, +Nmass, +logLA); SIZE ≈ (+logH, +logSM).
  - Forms (matching Run 2):
    - L/T/R: `y ~ LES + SIZE + logSSD` (linear_size)
    - M/N: `y ~ LES + logH + logSM + logSSD` (linear_deconstructed)
  - Random effects: `(1|Family)` when available.
  - Grouping for d-sep: `--group_var=Myco_Group_Final`.
  - Targeted myco-specific path (R only, based on power test): direct `SSD → R` for groups `Pure_NM` and `Low_Confidence`.
- lavaan (grouped inference; CV via composites):
  - Measurement: `LES =~ negLMA + Nmass + logLA`; `SIZE =~ logH + logSM`.
  - Structural: `y ~ LES + SIZE`; plus direct `SSD → {M,N,R}` (as in Run 2).
  - Residuals: `logH ~~ logSM`; `Nmass ~~ logLA`; allow `LES ~~ SIZE`.
  - Estimation: `MLR`, `std.lv=TRUE`, `missing='fiml'`; grouped by `Myco_Group_Final` (no group-specific paths in CV).

Repro Commands (Run 3)
- piecewise (CV + d-sep):
  - L/T/R (linear_size):
    - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target={L|T|R} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Myco_Group_Final --out_dir=artifacts/stage4_sem_piecewise_run3`
  - M/N (deconstructed SIZE):
    - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target={M|N} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Myco_Group_Final --deconstruct_size=true --out_dir=artifacts/stage4_sem_piecewise_run3`
  - Myco-specific (R d-sep only):
    - `... --target=R --psem_drop_logssd_y=true --group_ssd_to_y_for='pure_nm,low_confidence'`
- lavaan (grouped inference; CV via composites):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target={L|T|M|R|N} --transform=logit --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --group=Myco_Group_Final --out_dir=artifacts/stage4_sem_lavaan_run3 --add_direct_ssd_targets=M,N,R --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA'`

Final Results (Run 3; mean ± SD)
- piecewise CV (LES+SIZE/logs; forms as above):
  - L: R² 0.232±0.044; RMSE 1.339±0.052; MAE 1.004±0.034 (n=1065)
  - T: R² 0.227±0.043; RMSE 1.151±0.049; MAE 0.864±0.035 (n=1067)
  - R: R² 0.145±0.041; RMSE 1.438±0.042; MAE 1.082±0.035 (n=1049)
  - M (deconstructed): R² 0.399±0.050; RMSE 1.167±0.056; MAE 0.902±0.033 (n=1065)
  - N (deconstructed): R² 0.415±0.056; RMSE 1.435±0.063; MAE 1.156±0.053 (n=1047)
- lavaan CV (composite proxy):
  - L: R² 0.114±0.038; RMSE 1.438±0.050; MAE 1.065±0.032 (n=1065)
  - T: R² 0.106±0.046; RMSE 1.238±0.041; MAE 0.916±0.026 (n=1067)
  - M: R² 0.047±0.033; RMSE 1.470±0.046; MAE 1.142±0.033 (n=1065)
  - R: R² 0.023±0.024; RMSE 1.538±0.040; MAE 1.162±0.027 (n=1049)
  - N: R² 0.301±0.055; RMSE 1.568±0.057; MAE 1.286±0.041 (n=1047)
- d-sep (R, myco-specific SSD→R): Overall Fisher’s C p≈0.899 (df=8); `Pure_NM` and `Low_Confidence` groups saturated (df=0).

Artifacts (Run 3)
- lavaan: `artifacts/stage4_sem_lavaan_run3/sem_lavaan_{L,T,M,R,N}_{metrics.json,preds.csv,path_coefficients.csv}`
- piecewise: `artifacts/stage4_sem_piecewise_run3/sem_piecewise_{L,T,M,R,N}_{metrics.json,preds.csv,[piecewise_coefs.csv,dsep_fit.csv]}`
- Myco power test (supporting): `artifacts/stage4_sem_myco_run3/myco_power_summary.csv`, `myco_power_{R,N,L,T}_per_group.csv`

Comparison: Run 3 vs Run 2 (CV metrics)
- lavaan (composite proxy) — small gains except R slightly worse RMSE:
  - L: R² 0.110 → 0.114 (+0.004); RMSE 1.443 → 1.438 (−0.005)
  - T: R² 0.102 → 0.106 (+0.004); RMSE 1.250 → 1.238 (−0.011)
  - M: R² 0.043 → 0.047 (+0.004); RMSE 1.476 → 1.470 (−0.006)
  - R: R² 0.024 → 0.023 (≈); RMSE 1.535 → 1.538 (+0.003)
  - N: R² 0.299 → 0.301 (+0.002); RMSE 1.568 → 1.568 (≈)
- piecewise — equal or improved across all targets when using Run 2 forms:
  - L (linear_size): R² 0.231 → 0.232 (+0.001); RMSE 1.341 → 1.339 (−0.003)
  - T (linear_size): R² 0.218 → 0.227 (+0.009); RMSE 1.166 → 1.151 (−0.015)
  - R (linear_size): R² 0.143 → 0.145 (+0.002); RMSE 1.438 → 1.438 (≈)
  - M (deconstructed): R² 0.398 → 0.399 (+0.001); RMSE 1.171 → 1.167 (−0.004)
  - N (deconstructed): R² 0.409 → 0.415 (+0.006); RMSE 1.440 → 1.435 (−0.005)

Bottom line
- Run 3 faithfully reproduces Run 2 models and parameters, adding only mycorrhiza grouping. Predictive CV is equal or slightly better; causal d‑sep improves materially for R via targeted myco‑specific SSD→R.

- Myco moderation follow‑up (R):
  - Consider collapsing uncertain categories (e.g., exclude Low_Confidence from moderation or analyze sensitivity both with/without) to ensure robustness.
  - Export and inspect myco multigroup path coefficients (piecewise coefs) to confirm direction consistency across significant groups.
- Co‑adapted LES in lavaan (Action 2): enable `--coadapt_les=true` to replace “LES ~ SIZE + logSSD” with “LES ~~ SIZE; LES ~~ logSSD” and evaluate ΔCFI/RMSEA.
- Key interaction (Action 3): add `LES:logSSD` in piecewise local models; gate by CV improvements.
- Nonlinearity (Action 4): test `s(logH, bs="ts", select=TRUE)` and optionally `s(logSSD, bs="ts", select=TRUE)`; accept only if CV improves.
- Random effects (Action 5): keep `(1|Family)`; add `(1|Genus)` sensitivity if available; verify fixed‑effect stability.
- LES measurement (Action 6): test `LES_core =~ negLMA + Nmass` with `logLA` moved to structural side; compare fit and interpretability.
- MAG residuals: if lavaan absolute fit remains low after co‑adaptation, add minimal residual covariances (already using `logH ~~ logSM; Nmass ~~ logLA; LES ~~ SIZE`) and reassess.

Outcomes — Mycorrhiza Moderation (post‑power test)
- Power test (LM, focus on SSD:Myco): `src/Stage_4_SEM_Analysis/myco_power_test.R --targets=R,N,L,T --min_group_n=30 --out_dir=artifacts/stage4_sem_myco_run3`
  - R: choose_interaction=TRUE (AIC 2818.94→2811.95; LR p≈0.005); per‑group SSD significant in `Pure_NM` (p≈0.033) and `Low_Confidence` (p≈0.013).
  - N: choose_interaction=FALSE (LR p≈0.788) → keep pooled.
  - L/T: choose_interaction=FALSE → no myco‑specific paths warranted.
- Piecewise multigroup d‑sep (R) with myco‑specific SSD→R for `pure_nm,low_confidence`:
  - Overall Fisher’s C p≈0.899 (df=8) in `sem_piecewise_R_multigroup_dsep.csv`; selected groups saturated (df=0). This mirrors the Woodiness success: targeted direct SSD→R dispels misfit.
- lavaan by‑group (R) on filtered Myco (n≥30) with myco‑specific SSD→R:
  - Wrote `artifacts/stage4_sem_lavaan_run3/sem_lavaan_R_fit_indices_by_group.csv` (absolute fit remains modest for most groups; expected given strict measurement constraints). Use d‑sep improvement as primary causal evidence.

Phylogenetic robustness (Action 5)
- Random intercepts for `Family` were used when feasible in CV; full‑data phylogenetic GLS checks (Brownian, Pagel’s λ) maintain the signs and practical significance of core effects (LES, SIZE/logH/logSM, logSSD). This supports Run 3 model forms as non‑artifactual with respect to shared ancestry.
