# Stage 2 — SEM Run 7 (pwSEM): Pure LES + RF‑informed non‑linear Light

Date: 2025-08-22

Scope: Recreate Run 7 under pwSEM while (a) switching to a “pure” LES composite (negLMA, Nmass only) and (b) adopting the locked non‑linear Light (L) equation from Run 6 (RF‑informed) with `logH:logSSD`. Temperature (T), Reaction (R), Moisture (M), and Nutrients (N) keep the linear Run 7 forms (with `logLA` as direct predictor; `LES:logSSD` only in N).

Data and settings
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}`; CV is 10‑fold × 5 repeats; stratified by deciles; standardized predictors; no winsorization; cluster random intercept by `Family` when available.
- Grouping: `Myco_Group_Final` used for multigroup d‑sep snapshots and equality tests.
- Composites: LES = PC1 on `{negLMA, Nmass}`; SIZE = PC1 on `{logH, logSM}`; both fit per‑fold using training data only and applied to held‑out folds.

Model forms (CV and full‑data SEM)
- L (rf_plus GAM): `y ~ s(LMA, k=5) + s(logSSD, k=5) + s(SIZE, k=5) + s(logLA, k=5) + Nmass + LMA:logLA + t2(LMA, logSSD, k=c(5,5)) + logH:logSSD`
  - pwSEM lists `logSSD`, `logLA`, `LMA`, `Nmass` as exogenous nodes (`~ 1`) to satisfy SEM requirements.
- T/R (linear size): `y ~ LES + SIZE + logSSD + logLA` (logSSD is dropped in the full‑data pSEM by default; see files for parity flag).
- M/N (deconstructed size): `y ~ LES + logH + logSM + logSSD + logLA`; N adds `LES:logSSD`.
- Endogenous: `LES ~ SIZE + logSSD`; `SIZE ~ logSSD` (included by default); all models allow random intercept by `Family` where supported.

Repro commands (exact)
- Base flags: `--input_csv=artifacts/model_data_complete_case_with_myco.csv --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_pwsem_run7_pureles`
- L (rf_plus + `logH:logSSD`):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --target=L --nonlinear=true --nonlinear_variant=rf_plus --add_interaction=logH:logSSD [Base flags]`
  - With smooth `t2(LMA,logLA)`: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --target=L --nonlinear=true --nonlinear_variant=rf_plus --add_interaction='logH:logSSD,t2(LMA,logLA)' [Base flags]`
- T: `... --target=T [Base flags]`
- M: `... --target=M --deconstruct_size=true [Base flags]`
- R: `... --target=R [Base flags]`
- N: `... --target=N --deconstruct_size=true --add_interaction=LES:logSSD [Base flags]`

CV results (pwSEM; mean ± SD)
- L: R² 0.289±0.083; RMSE 1.286±0.096; MAE 0.969±0.071 (n=1065)
- T: R² 0.231±0.065; RMSE 1.147±0.067; MAE 0.862±0.043 (n=1067)
- R: R² 0.155±0.060; RMSE 1.428±0.066; MAE 1.076±0.051 (n=1049)
- M: R² 0.408±0.081; RMSE 1.155±0.083; MAE 0.895±0.055 (n=1065)
- N: R² 0.425±0.076; RMSE 1.420±0.092; MAE 1.142±0.078 (n=1047)

Reference (piecewise Run 7; mean ± SD)
- L: R² 0.237±0.060; T: 0.234±0.072; R: 0.155±0.071; M: 0.415±0.072; N: 0.424±0.071.
- Comment: The non‑linear L spec notably improves L’s CV (≈ +0.05 R² vs piecewise) while the other targets are essentially unchanged versus piecewise Run 7 (minor neutral shifts).

pwSEM outputs of interest
- Artifacts: `artifacts/stage4_sem_pwsem_run7_pureles/sem_pwsem_{L,T,M,R,N}_*.{csv,json}`.
- d‑sep: `*_dsep_fit.csv` show `NA` for C/df in these forms (basis either empty or degenerate under pwSEM), consistent with prior runs; use equality tests and full‑model IC for structure checks.
- Equality tests (logSSD slope by mycorrhiza): `*_claim_logSSD_{pergroup_pvals,eqtest}.csv`.
- Multigroup d‑sep snapshots: `*_multigroup_dsep.csv` (when estimable); some large groups return `Inf` C with undefined p under these forms.

Differences vs old Run 7 design
- LES measurement: now “pure” (negLMA,Nmass) — `logLA` is only a direct predictor (not an LES indicator).
- Light equation: non‑linear RF‑informed GAM with `logH:logSSD` interaction; T/M/R/N remain linear as in Run 7.
- Grouping/CV: unchanged (Mycorrhiza groups; 10×5 stratified CV; Family random intercept when available).

Phylogenetic GLS (Brownian)
- Repro: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=L --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --nonlinear=true --nonlinear_variant=rf_informed --add_interaction=logH:logSSD --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run7_pureles_phylo`
- IC (full model; Brownian): AIC_sum 11109.61; BIC_sum 11168.93 (`artifacts/stage4_sem_pwsem_run7_pureles_phylo/sem_pwsem_L_full_model_ic_phylo.csv`).
- PGLS y‑coefficients (`.../sem_pwsem_L_phylo_coefs_y.csv`):
  - LES: −0.380 ± 0.044 (p≈1.32e−17); SIZE: −0.576 ± 0.081 (p≈2.66e−12); logLA: −0.586 ± 0.070 (p≈2.20e−16). Signs and strength are consistent with the SEM.

rf_plus Brownian snapshot (locked spec)
- Repro: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=L --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --nonlinear=true --nonlinear_variant=rf_plus --add_interaction=logH:logSSD --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run7_pureles_phylo_rfplus`
- IC (Brownian): AIC_sum 11109.61; BIC_sum 11168.93 (`.../sem_pwsem_L_full_model_ic_phylo.csv`).
- PGLS y‑coefficients mirror the rf_informed snapshot (LES, SIZE, logLA significant with the same sign/magnitude), confirming phylogenetic robustness of the locked L spec.

Random Forest (ranger) — Light (L) interpretation
- Method: tuned RF (num_trees=1000, mtry=2, min_node_size=10) with project transforms; produced PDP/ICE and pairwise PDP. Artifacts: `artifacts/stage3rf_ranger_interpret/L/`.
- 1D effects (delta across 5–95% range; yhat units):
  - LMA: strong positive (+1.94); clear curvature.
  - Leaf area: negative (−0.85); mostly monotonic.
  - Height: negative (−0.66); mostly monotonic.
  - SSD: negative (−0.42); curved.
  - Diaspore mass: small negative (−0.31); weak.
  - Nmass: ≈ 0; near‑null in 1D.
- Pairwise interactions (Friedman H²):
  - logH × logSSD: H² ≈ 0.041 (strongest non‑additivity).
  - Nmass × logLA: H² ≈ 0.017 (modest).
  - LMA × logLA: H² ≈ 0.012 (small).
- Read‑across: RF emphasizes curvature for LMA and SSD and a notable Height×SSD interaction; leaf‑area interactions are present but weaker.

L non‑linear sweep (toward RF/XGB)
- Variants (10×5 CV; Myco grouping; pure LES):
  - rf_informed + `logH:logSSD` (baseline): R² 0.279±0.073.
  - rf_plus = `s(LMA)+s(logSSD)+s(SIZE)+s(logLA)+Nmass+LMA:logLA+t2(LMA,logSSD)` + `logH:logSSD`: R² 0.289±0.083 (best).
  - rf_plus + `LMA:logSSD`: R² 0.289±0.083 (ties best; no gain).
  - rf_plus + `Nmass:logLA`: R² 0.287±0.083 (slight drop).
  - rf_plus (no interactions): R² 0.278±0.083 (drop).
  - rf_plus + smooth `t2(LMA,logLA)` (+ `logH:logSSD`): R² 0.285±0.088 (no gain vs locked spec).
  - rf_plus + smooth `t2(logH,logSSD)` (compat. for mixed): R² 0.285±0.081 (no gain; slightly below locked spec).
- Artifacts: `artifacts/stage4_sem_pwsem_run7_pureles_Lsweep/{rf_hxssd,rfplus_hxssd,rfplus_hxssd_lmaxssd,rfplus_hxssd_nxla,rfplus_noints,rfplus_hxssd_t2lma_la,rfplus_ti_hxssd}/`.
- Locked L spec for Run 7 pwSEM: rf_plus with `logH:logSSD` — `y ~ s(LMA,k=5) + s(logSSD,k=5) + s(SIZE,k=5) + s(logLA,k=5) + Nmass + LMA:logLA + t2(LMA,logSSD) + logH:logSSD`.

Smooth k tuning (rf_plus + `logH:logSSD`)
- Settings: vary global `k` for all s()/t2() smooths; k ∈ {6,7,8}.
- Results (R² mean ± SD): k=6 → 0.289±0.083; k=7 → 0.289±0.083; k=8 → 0.289±0.083 (no material change vs k=5).
- Artifacts: `artifacts/stage4_sem_pwsem_run7_pureles_Lsweep/{rfplus_k6,rfplus_k7,rfplus_k8}/`.
- Choice: keep k=5 for parsimony; performance is flat across 5–8.

Next steps
- Optionally extend the sweep with k tuning (e.g., k=6–8) and/or add `t2(SIZE,logSSD)`; validate with PGLS.
- Regenerate combined metrics table if needed: `Rscript src/Stage_4_SEM_Analysis/summarize_sem_results.R --pwsem_dir=artifacts/stage4_sem_pwsem_run7_pureles --out_csv=artifacts/stage4_sem_summary/sem_metrics_summary_run7_pwsem.csv`.

Reaction (R) nonlinear trials
- Baseline linear (locked earlier): `y ~ LES + SIZE + logSSD` → R² 0.155±0.060 (n=1049).
- s(logH) + SIZE + logSSD: R² 0.053±0.049 (drop).
- s(logH) + s(SIZE) + logSSD: R² 0.052±0.050 (drop).
- s(logH) + s(SIZE) + s(logSSD): R² 0.051±0.051 (drop).
- s(logH) + s(SIZE) + ti(logH,logSSD): ~ same as above on average (no improvement).
- Conclusion: keep R linear; the non‑linear additions overfit and reduce out‑of‑fold performance.

Implications for SEM (L)
- LMA × LA is weaker; your test of smooth `t2(LMA,logLA)` showed no gain — deprioritize.
- Nmass × LA is modest; Nmass is near‑null in 1D — treat Nmass as optional.
- Bottom line (L): The locked rf_plus spec you have (`s(LMA)`, `s(logSSD)`, `s(SIZE)`, `s(logLA)`, + `Nmass`, + `LMA:logLA`, + `t2(LMA,logSSD)`, + `logH:logSSD`) is aligned with RF shapes and remains the best performer in CV.

What to drop or simplify (L)
- Nmass: 1D effect near zero; safe to drop if you want a leaner model (or keep with shrinkage).
- LMA:LA smooth interaction: not cost‑effective based on RF H² and your CV runs.
