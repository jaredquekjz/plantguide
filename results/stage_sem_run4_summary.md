# Stage 2 — SEM Run 4: Co‑adapted LES↔SIZE in lavaan (Myco grouped)

Date: 2025-08-14

Scope: Run 4 implements Action 2 (Co‑adapted Spectra) by replacing directed inputs into LES from SIZE/logSSD with non‑directed covariances in lavaan while keeping all other settings identical to Run 3, including mycorrhiza grouping (`Myco_Group_Final`) and CV via composite proxies. Piecewise models are unchanged in this run.

Data
- Input: `artifacts/model_data_complete_case_with_myco_n30.csv` (complete‑case six traits; Mycorrhiza groups filtered to n≥30 for stable grouped fits).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (lavaan co‑adaptation; grouping as in Run 3)
- Preprocessing: log10 transforms for Leaf area, Plant height, Diaspore mass, SSD used (small positive offsets recorded); z‑score within folds; 10‑fold CV × 5 repeats (seed=42; decile‑stratified); no winsorization; no weights.
- lavaan (grouped inference; CV via composites):
  - Measurement: `LES =~ negLMA + Nmass + logLA`; `SIZE =~ logH + logSM`.
  - Structural (co‑adapted): drop directed inputs into LES; add covariances: `LES ~~ SIZE`, `LES ~~ logSSD`; outcomes keep `y ~ LES + SIZE` with direct `SSD → {M,N}` as in Run 3.
  - Residuals: `logH ~~ logSM`; `Nmass ~~ logLA`; (optional) `LES ~~ SIZE` already included by co‑adaptation.
  - Estimation: `MLR`, `std.lv=TRUE`, `missing='fiml'`; grouped by `Myco_Group_Final`.

Repro Commands (Run 4)
- lavaan (grouped inference; CV via composites; co‑adapted LES):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case_with_myco_n30.csv --target={L|T|M|R|N} --transform=logit --seed=42 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --group=Myco_Group_Final --out_dir=artifacts/stage4_sem_lavaan_run4 --add_direct_ssd_targets=M,N --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA' --coadapt_les=true`

Final Results (Run 4; mean ± SD)
- lavaan CV (composite proxy):
  - L: R² 0.113±0.063; RMSE 1.439±0.068; MAE 1.066±0.049 (n=1059)
  - T: R² 0.106±0.049; RMSE 1.237±0.066; MAE 0.916±0.044 (n=1061)
  - M: R² 0.048±0.050; RMSE 1.469±0.058; MAE 1.141±0.046 (n=1059)
  - R: R² 0.017±0.032; RMSE 1.523±0.063; MAE 1.151±0.040 (n=1043)
  - N: R² 0.296±0.081; RMSE 1.568±0.095; MAE 1.287±0.076 (n=1041)
- lavaan global fit (multi‑group):
  - L: CFI 0.558; TLI 0.204; RMSEA 0.268; SRMR 0.198
  - T: CFI 0.534; TLI 0.161; RMSEA 0.282; SRMR 0.171
  - M: CFI 0.561; TLI 0.198; RMSEA 0.268; SRMR 0.165
  - R: CFI 0.598; TLI 0.276; RMSEA 0.246; SRMR 0.196
  - N: CFI 0.654; TLI 0.368; RMSEA 0.255; SRMR 0.223

Artifacts (Run 4)
- lavaan: `artifacts/stage4_sem_lavaan_run4/sem_lavaan_{L,T,M,R,N}_{metrics.json,preds.csv,path_coefficients.csv,fit_indices.csv}`

Comparison: Run 4 (co‑adapted) vs Run 3 (directed LES) — lavaan fit indices (Myco grouped; n≥30)
- L: ΔCFI +0.028 (0.530→0.558); ΔTLI +0.005 (0.199→0.204); ΔRMSEA −0.001 (0.269→0.268); ΔSRMR +0.028 (0.170→0.198)
- T: baseline fit indices unavailable under Run 3 settings (lavaan failed to report); Run 4 shown above for reference.
- M: ΔCFI +0.047 (0.514→0.561); ΔTLI +0.037 (0.161→0.198); ΔRMSEA −0.006 (0.274→0.268); ΔSRMR −0.008 (0.173→0.165)
- R: ΔCFI +0.007 (0.591→0.598); ΔTLI −0.018 (0.294→0.276); ΔRMSEA +0.003 (0.244→0.246); ΔSRMR +0.005 (0.191→0.196)
- N: ΔCFI +0.005 (0.649→0.654); ΔTLI −0.026 (0.394→0.368); ΔRMSEA +0.005 (0.250→0.255); ΔSRMR −0.005 (0.228→0.223)

Information criteria (Run 4 − Run 3; lower is better)
- L: ΔAIC −468.0; ΔBIC −392.6 (strongly favors Run 4)
- M: ΔAIC −497.9; ΔBIC −422.5 (strongly favors Run 4)
- R: ΔAIC −442.5; ΔBIC −372.0 (strongly favors Run 4)
- N: ΔAIC −436.3; ΔBIC −361.2 (strongly favors Run 4)
- T: baseline grouped indices not available; IC deltas not computed

Note on selection criteria (Douma & Shipley 2020)
- For DAG‑consistent path models, generalized full‑model AIC (sum of submodel AICs) provides a coherent selection criterion beyond d‑sep topology fit; analogously, in latent SEM the global AIC/BIC compare non‑nested structural formulations by expected K–L divergence. Thus, large ΔAIC/ΔBIC in favor of Run 4 constitute stronger evidence than small, mixed shifts in single fit indices.

Methodology note (AIC variants)
- d‑sep AIC (Shipley 2013): based on the C‑statistic; compares DAG topologies only.
- Full‑model AIC for piecewise SEM (Douma & Shipley 2020): sum of submodel AICs from ML‑fit components; compares parameterizations and link/distribution choices beyond topology. We did not compute this here since Run 4 focuses on lavaan latent SEM; for lavaan, global AIC/BIC are the appropriate analogues and are reported above.
- Action: In Runs 5–6 (piecewise), we will add full‑model AIC alongside CV metrics to align with the paper’s guidance.

Bottom line and adoption
- Overall: Strong IC support (large AIC/BIC decreases) favors the co‑adapted formulation across targets. Adopt co‑adaptation for L, M, R, and N; re‑report T once a comparable Run 3 grouped baseline is produced.
- Interpretation: Despite mixed TLI/SRMR for some targets, CFI/RMSEA do not degrade materially, and IC improvements are decisive, aligning with the generalized AIC rationale.

Next
- Proceed to Run 5 (Action 3): add `LES*logSSD` interaction in piecewiseSEM and evaluate CV improvements per target.
