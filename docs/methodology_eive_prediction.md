# Methodology: Predicting EIVE Indicators from Six Plant Traits

Author: Project “EIVE-from-TRY” — methodology v0.1

Purpose: Predict the Ecological Indicator Values for Europe (EIVE; niche positions on a 0–10 scale) from six widely available plant traits (TRY curated means), then extend to causal modeling. Grounded in EIVE 1.0 and the methods of Douma & Shipley (2021, 2022).

References
- Dengler et al. 2023/2024: EIVE 1.0 overview and performance (five niche dimensions; 0–10 scale; plus niche width variants).
- Shipley & Douma 2021: MAG/m-sep testing for DAGs with latent variables and correlated errors.
- Douma & Shipley 2022: Copula-based modeling of dependent errors in piecewise path models under non-normality, non-linearity, and hierarchical data.
- Shipley et al. 2017 (JVS): Trait-based prediction of Ellenberg indicator ranks (ordinal 1–9) from four traits; demonstrated plausibility and out-of-region validation with coarse habitat classes.

Anchoring To Prior Work (2017 JVS) — Relevance and Extensions
- What 2017 showed:
  - Four widely measured traits (SLA, LDMC, leaf area, seed mass) predict Ellenberg ranks (light, moisture, nutrients) via cumulative link (ordinal) models after log transforms.
  - Cross-validated errors mostly within ±2 ranks; independent validation on species outside Central Europe using coarse 3-level habitat classes confirmed broad generality.
  - Limitations: weaker discrimination at extreme ranks and lower light classes; gradients fitted independently; no pH/temperature; no niche width.
- Why relevant here:
  - Confirms feasibility of trait→indicator mapping with limited traits and modest sample sizes, including transfer beyond training geography.
  - Informs pre-processing (log transforms) and per-indicator modeling strategy.
- How we extend beyond 2017:
  - Targets: EIVE continuous 0–10 indicators for five dimensions (L, T, M, R, N), not ordinal Ellenberg 1–9; includes R (pH) and T (temperature), and provides niche-width variants (.nw3, .n).
  - Predictors: six curated TRY means (adds Nmass, LMA/SSD/height to the 2017 quartet), preserving LDMC and leaf area; LMA partly proxies SLA while retaining LDMC explicitly.
  - Models: robust continuous regression as primary (bounded/robust options), with an optional ordinal comparator (binning EIVE into 10 levels) to mirror 2017’s cumulative link framing.
  - Validation: repeated CV and tail calibration diagnostics to address bounded-scale bias observed in 2017; optional out-of-Europe validation via coarse habitat classes when ground truth is unavailable.
  - Structure: Stage 2 SEM quantifies trait interdependencies and paths to EIVE, unavailable in 2017’s purely predictive setup.

Assumptions
- Species are linked by WFO-accepted names using the exact mapping prepared in `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`.
- The curated TRY means file (TRY 30) provides six numeric traits per species after matching.
- EIVE main table contains five niche dimensions as columns (e.g., `EIVEres-L, -T, -M, -R, -N`) and their derivatives (e.g., `.nw3`, `.n`).

EIVE vs. Ellenberg (Conceptual Differences To Respect)
- Scale/type: EIVE uses continuous 0–10 niche positions (and niche widths), unifying multiple regional systems; Ellenberg uses ordinal classes (1–9, moisture to 12) from expert elicitation.
- Dimensions: EIVE provides five dimensions (L, T, M, R, N), with optional niche-width weighting; 2017 modeled only L/M/N.
- Coverage/transfer: EIVE aggregates Europe-wide sources (broader taxonomic/biogeographic coverage); transfer beyond Europe should be validated cautiously (e.g., coarse habitat classes) as in 2017.

Data Pipeline
1) EIVE table extraction
   - Convert Excel to CSV: `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv` (done).
   - WFO normalization (EXACT): `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv` (done).
2) TRY curated traits subset
   - Script: `src/Stage_1_Data_Extraction/match_trycurated_species_to_eive_wfo.R`
   - Outputs: `artifacts/traits_matched.{csv,rds}` — species matched to EIVE, with six core trait means.
3) Modeling dataset assembly (done)
   - Join `artifacts/traits_matched.rds` to EIVE indicators by WFO accepted name (normalized species name), one record per species.
   - Select five EIVE targets (`EIVEres-{L,T,M,R,N}`) and six traits, using `SSD used (mg/mm3)` that prefers observed over combined; include `ssd_imputed_used` flag and `min_records_6traits`.
   - Outputs: `artifacts/model_data_full.csv`, `artifacts/model_data_complete_case.csv`, `artifacts/model_data_complete_case_observed_ssd.csv`.
   - Datasets:
     - Complete-case: species with all six traits present via SSD combined (≈1,068 species).
     - Full set: allow missing traits; reserved for FIML/MI later.

Empirical Coverage Snapshot (current repository state)
- Matched species with curated traits: 5,750 (artifacts/traits_matched.{csv,rds}).
- Complete-case (six traits present using SSD combined): 1,068 species.
  - SSD provenance within complete-case: 382 observed; 676 imputed via LDMC (combined = imputed).
  - If requiring observed SSD strictly: 389 species remain complete-case.
  - Implication: baseline models will use SSD combined; we will run an observed-only sensitivity analysis and report deltas.

TRY Curation Principles (from Enhanced Species-Level Trait Dataset)
- Species means: mature, healthy plants in natural conditions; aggregated from ~1M trait records (2,500+ sources) via TRY.
- QC workflow: probabilistic outlier detection + expert/external validation; harmonized units and protocols (Pérez‑Harguindeguy 2013; LEDA).
- Replicates metadata: curated tables include per-trait record counts (e.g., “(n.o.)” columns); many species have few records, some have many.
- SSD gaps: non‑woody SSD imputed from LDMC; curated files expose “SSD observed / imputed / combined”.
- Categorical context: woodiness, growth form, succulence, aquatic/terrestrial, nutrition type, leaf type; useful as covariates/random effects.

Modeling Implications We Will Apply
- Prefer observed over imputed: use “SSD observed” when present; else “SSD combined”; add `ssd_imputed_used` flag for transparency.
- Replicate-aware analysis: offer weights by min(n.o.) across used traits or include `log1p(n.o.)` covariates; report sensitivity with/without weights.
- Evidence thresholds: optional filters (e.g., require ≥2 records for a trait) to assess robustness vs. coverage.
- Transform and scale: log-transform heavy-tailed traits (LA, SM, H, SSD) and standardize; retain LDMC as auxiliary where helpful.
- Categorical adjustments: evaluate woodiness/growth-form as factors or random effects in piecewise SEM; check interactions.
- Provenance tracking: carry record counts and imputation flags into `model_data` for diagnostics and reproducibility.

Reporting Conventions (additions)
- Always report counts for: total matched species, complete-case, observed-only subset, and SSD provenance breakdown within complete-case.
- For each model, include sensitivity metrics on observed-only SSD subset and with/without replicate-aware weights.

Targets and Predictors
- Targets: five EIVE niche-position indicators (0–10), one at a time.
- Predictors (six traits):
  - Leaf area (mm2)
  - Nmass (mg/g)
  - LMA (g/m2)
  - Plant height (m)
  - Diaspore mass (mg)
  - SSD combined (mg/mm3)

Stage 1 — Multiple Regression (Established Libraries)
- Goal: Strong baseline; transparent diagnostics; reproducible CV.
- R packages: `stats` (lm), `sandwich` + `lmtest` (robust SE), optional `glmnet` (ridge/lasso).
- Preprocessing:
  - Log-transform right-skewed traits (e.g., area, mass, height, SSD) with small offset; standardize predictors.
  - Winsorize extreme outliers (e.g., 0.5–99.5th pct) in sensitivity analyses.
- Model: `EIVEres-X ~ six standardized traits` for X ∈ {L,T,M,R,N}.
- Validation:
  - 5×5 repeated CV (stratify across target deciles if needed).
  - Metrics: R², RMSE, MAE; retain per-fold and overall means/SDs.
  - Report coefficient stability and VIFs.
- Outputs:
  - Coefficients, robust SEs, partial R², residual diagnostics (QQ, scale–location), CV metrics JSON.
  - Predictions for holdout folds.
- Optional 2017-style comparator (for continuity and sanity checks):
  - Discretize EIVE to 10 levels (0–10 → 1–10) and fit a cumulative link model (proportional odds) on transformed traits.
  - Compare confusion matrices on coarse low/medium/high groupings; document tail bias as in 2017.

Implementation Details — Stage 1
- Data assembly (src/Stage_2_Data_Processing/assemble_model_data.R)
  - Join key: normalized `wfo_accepted_name` (from `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`) to TRY species (`artifacts/traits_matched.{rds,csv}`).
  - Targets: select primary `EIVEres-{L,T,M,R,N}` from `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv`.
  - SSD handling: `SSD used (mg/mm3)` prefers observed; otherwise uses combined; flag `ssd_imputed_used` = 0 (observed) / 1 (imputed).
  - Evidence: carry per-trait record counts; compute `min_records_6traits` = min across the six traits when available.
  - Outputs: `artifacts/model_data_full.csv`, `artifacts/model_data_complete_case.csv`, `artifacts/model_data_complete_case_observed_ssd.csv`.

- Modeling (src/Stage_3_Multi_Regression/run_multi_regression.R)
  - Predictors (six): Leaf area (mm2), Nmass (mg/g), LMA (g/m2), Plant height (m), Diaspore mass (mg), SSD used (mg/mm3).
  - Transforms: log10 for Leaf area, Plant height, Diaspore mass, SSD used; each with small positive offset `offset = max(1e-6, 1e-3 * median(x[x>0]))` to avoid log(0). Predictors then standardized (z-scores). Offsets recorded in metrics JSON.
  - CV: 5×5 repeated, stratified by target deciles. Train-test hygiene: fit all transforms (winsor thresholds, means/SDs) on train folds; apply to held-out test folds.
  - Diagnostics: robust HC3 standard errors if `sandwich` + `lmtest` available; VIFs from auxiliary regressions `VIF_j = 1/(1 - R²_j)`.
  - Metrics: per-fold R², RMSE, MAE; report mean±SD. Save out-of-fold predictions, coefficients, VIFs, and metrics JSON to `artifacts/stage3_multi_regression/`.
  - Options: winsorization and replicate-aware weights (`min_records_6traits` or `log1p` thereof) are supported but off in baseline.

Rationale and Justification
- Transforms: Heavy-tailed traits benefit from log transforms; small offsets handle zeros without distorting scale. Standardization lets coefficients represent per-SD effects and stabilizes estimation.
- CV design: Repeated K-fold reduces variance of estimates relative to single split; stratifying by target deciles balances response distribution and stabilizes error estimates.
- Leakage control: Train-only fitting of transforms prevents optimistic bias in CV metrics.
- Robust SEs: HC3 provides heteroskedasticity-robust uncertainty for coefficient tables without altering CV predictions.
- Collinearity: Empirically low VIFs (≈1–2.4) indicate stable coefficient estimation with these six predictors.
- Limitations: Linear models on a bounded (0–10) outcome may underpredict extremes; later stages can add calibration or bounded links. pH (R) is weakly captured by these six traits; root chemistry/physiology predictors may be required.

Stage 1 Outputs — Snapshot
- Data: 5,750 matched species; complete-case (six traits, SSD combined) n=1,068; observed-only SSD complete-case n=389. SSD provenance within complete-case: observed=389, imputed=679.
- CV Performance (complete-case; mean±SD):
  - L: R²=0.155±0.024, RMSE=1.406±0.034, MAE=1.044±0.026
  - T: R²=0.101±0.032, RMSE=1.250±0.037, MAE=0.918±0.027
  - M: R²=0.132±0.047, RMSE=1.406±0.057, MAE=1.068±0.033
  - R: R²=0.035±0.027, RMSE=1.526±0.035, MAE=1.169±0.019
  - N: R²=0.349±0.053, RMSE=1.512±0.068, MAE=1.228±0.051

Reproducibility
- Assemble data:
  - `Rscript src/Stage_2_Data_Processing/assemble_model_data.R --emit_observed_ssd_complete=true`
- Run baseline regressions:
  - `Rscript src/Stage_3_Multi_Regression/run_multi_regression.R --input_csv artifacts/model_data_complete_case.csv --targets=all --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --min_records_threshold=0 --out_dir artifacts/stage3_multi_regression`

Ordinal Comparator (for alignment to 2017)
- Script: `src/Stage_3_Multi_Regression/run_ordinal_comparator.R`
- Purpose: Discretize EIVE (0–10) to ordered ranks and fit proportional-odds models (`ordinal::clm` preferred; falls back to `MASS::polr`). Uses the same transforms and repeated, stratified CV to mirror the OLS baseline without leakage.
- Key flags:
  - `--targets=L,T,M` (subset) or any of `L,T,M,R,N`
  - `--levels=10` (default; 1–10) or `--levels=9` (Ellenberg-like 1–9)
  - `--seed`, `--repeats`, `--folds`, `--stratify`, `--standardize`, `--winsorize`, `--winsor_p`, `--out_dir`
- Example:
  - `Rscript src/Stage_3_Multi_Regression/run_ordinal_comparator.R --input_csv artifacts/model_data_complete_case.csv --targets=L,T,M --levels=9 --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --out_dir artifacts/stage3_multi_regression`

Stage 1 — Alignment With Shipley et al. (2017)
- Sanity check: We compared our cross-validated results to the 2017 JVS study (ordinal Ellenberg). Using both continuous OLS and an ordinal comparator (EIVE binned to 10 and 9 levels), we found:
  - Qualitative alignment: same trait–environment patterns (acquisitive strategies for rich/wet sites; tougher leaves and lower stature for high light; weak seed mass effects).
  - Performance alignment: OLS RMSE competitive/better for Moisture and Nutrients vs 2017’s MPE; Light slightly worse—as noted in 2017 for low-light classes.
  - Hit-rates: 9-level ordinal framing narrows the gap toward 2017’s 70–90% (±1) and ≥90% (±2), especially for T; residual gap is consistent with EIVE vs Ellenberg target differences and trait panels.
- Conclusion: Results are consistent with the original study and pass a broad reality check; proceed to SEM with confidence.


Stage 2 — Structural Equation Modeling (Established Libraries)
- Two complementary approaches:
  1) Global SEM (lavaan): specify a priori causal paths among traits and the EIVE indicator; allow correlated residuals only if theoretically justified; use robust MLR; inspect fit (χ², CFI/TLI, RMSEA, SRMR) and modification indices cautiously.
  2) Piecewise SEM (piecewiseSEM): specify a DAG without bidirected errors; fit local models (possibly GLMs/GAMs, mixed models with random effects for Family/Genus) and apply d-sep test (Fisher’s C) to judge global fit; enables hierarchical structure and non-normality.
- Data usage:
  - Start on complete-case set (n≈1,068) for stable estimation.
  - Extend to full set with missing traits via FIML in lavaan or multiple imputation (mice/missForest) with pooling.
- Outputs:
  - Path coefficients with SEs/CIs, standardized effects, global fit indices, d-sep basis set and p-values, residual plots.

Frontier Extensions (Later Discussion)
- MAG/m-sep (Shipley & Douma 2021): For hypothesized DAGs involving latent variables or correlated errors, convert to a MAG and test implied m-separations; use as a model-checking layer before/alongside estimation.
- Copula-based dependent errors (Douma & Shipley 2022): In piecewise estimation, model dependent errors (bidirected edges) via copulas to handle non-normal residual dependence and obtain a coherent likelihood-based test framework.

Generalization Strategy (Informed by 2017)
- When validating beyond Europe (no direct EIVE ground truth), map predictions to coarse habitat classes (e.g., wetland vs non-wetland; forest vs open/steppe) compiled from independent sources, and test rank/ordering consistency rather than absolute values.
- Calibrate tails explicitly (near 0 and 10) using calibration plots and, if needed, monotone calibration (isotonic) on out-of-fold predictions.

Bias and Dependence Considerations
- Representativeness: The complete-case subset may over-represent well-studied taxa. Compare families/growth forms/regions vs. the matched set (n≈5,750).
- Phylogenetic non-independence: Evaluate with PGLS or random effects for taxonomic ranks; consider `phyloSEM` or piecewise models with taxonomic random effects.
- Distributional issues: Consider monotone transforms for skewed traits; use robust estimators (MLR) and validate residual assumptions.

Evaluation and Reporting
- Cross-validated metrics per target and overall (R², RMSE, MAE) using fixed seeds.
- Calibration plots (observed vs. predicted), residual diagnostics, and feature importance (standardized betas/elastic net coefficients).
- Reproducible scripts and command lines recorded alongside outputs under `artifacts/run_*`.

Reproducibility — Example Commands (Existing)
- Convert Excel → CSV:
  ```
  python src/Stage_1_Data_Extraction/convert_excel_to_csv.py \
    --input_xlsx data/EIVE_Paper_1.0_SM_08.xlsx \
    --sheet mainTable \
    --output_csv data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv
  ```
- Normalize EIVE to WFO (default WFO at `data/classification.csv`):
  ```
  Rscript src/Stage_1_Data_Extraction/normalize_eive_to_wfo_EXACT.R \
    --eive_csv=data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv \
    --out=data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv
  ```
- Match curated TRY ↔ EIVE and save traits:
  ```
  Rscript src/Stage_1_Data_Extraction/match_trycurated_species_to_eive_wfo.R \
    --try_xlsx=data/Tryenhanced/Dataset/Species_mean_traits.xlsx \
    --eive_csv=data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv \
    --traits_out_csv=artifacts/traits_matched.csv \
    --traits_out_rds=artifacts/traits_matched.rds
  ```

Next Steps (To Implement)
- Build `src/Stage_2_Modeling/assemble_model_data.R`: join `traits_matched.rds` with EIVE indicators by WFO name; emit `artifacts/model_data/full.rds` and `complete_cases.rds`.
- Build `src/Stage_2_Modeling/train_baseline_lm.R`: fit/cross-validate multiple regressions per EIVE target; write metrics and diagnostics under `artifacts/run_*`.
- Build `src/Stage_2_Modeling/sem_piecewise.R` and/or `sem_lavaan.R`: fit DAG-based SEMs; export path coefficients and fit indices.

Stage 2 — SEM (Piecewise) Update (2025-08-13)
- Composite axes (training-only PCA):
  - LES ≈ from (−LMA, +Nmass, +logLA)
  - SIZE ≈ from (+logH, +logSM)
- CV component model (unchanged):
  - y ~ LES + SIZE + logSSD (5×5 repeated CV; transforms trained on folds; no leakage)
- psem structure for d-sep (full-data only; to create testable independence):
  - Drop the direct logSSD → y edge in the psem while keeping it in CV
  - Add SIZE submodel: SIZE ~ logSSD (+ optional (1|Family))
  - Keep LES submodel: LES ~ SIZE + logSSD (+ optional (1|Family))
  - Tested independence claim: y ⟂ logSSD | {LES, SIZE}
- Commands:
  - Rerun per target: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case.csv --target={L|T|M|R|N} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_piecewise --psem_drop_logssd_y=true --psem_include_size_eq=true`
  - Summarize: `Rscript src/Stage_4_SEM_Analysis/summarize_piecewise_dsep.R --in_dir=artifacts/stage4_sem_piecewise --out_csv=artifacts/stage4_sem_summary/piecewise_dsep_summary.csv`
- Outputs:
  - Per-target: `artifacts/stage4_sem_piecewise/sem_piecewise_{X}_{piecewise_coefs.csv,dsep_fit.csv}`
  - Summary: `artifacts/stage4_sem_summary/piecewise_dsep_summary.csv`
- Results (Fisher’s C):
  - Mediated SSD→y (baseline psem): L fits (C≈0.95, df=2, p≈0.62); T fits (C≈1.31, df=2, p≈0.52); R borderline (C≈4.61, df=2, p≈0.10); M and N rejected (large C, p<0.001).
  - With direct SSD→y for M/N and SIZE~SSD: M, N become saturated (df=0; no testable independencies); L, T remain good fits under mediation; R remains borderline under mediation.
- Interpretation: SSD has a likely direct pathway to Moisture and Nutrients beyond mediation via LES/SIZE. For L/T, mediation suffices. For R, consider either a small direct SSD→R or refined measurement/residual structure.

Stage 2 — SEM (lavaan) Refinement (theory from d-sep)
- Measurement (unchanged):
  - LES =~ negLMA + Nmass + logLA (negLMA fixes loading sign)
  - SIZE =~ logH + logSM
- Structural by indicator:
  - L, T: y ~ LES + SIZE (SSD effect mediated)
  - M, N: y ~ LES + SIZE + logSSD (add direct SSD path)
  - R: y ~ LES + SIZE + logSSD (direct SSD enabled after d-sep/lavaan check)
  - LES ~ SIZE + logSSD (SSD reduces acquisitiveness; SIZE influences LES)
- Covariances (relax independence minimally):
  - LES ~~ SIZE (axes not strictly orthogonal)
  - Residuals: logH ~~ logSM; Nmass ~~ logLA
- Estimation: lavaan with MLR, std.lv=TRUE, missing='fiml'; optionally cluster='Family' and group='Woodiness'.
- Repro command:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case.csv --target={L|T|M|R|N} --transform=logit --seed=123 --repeats=1 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_lavaan --add_direct_ssd_targets=M,N,R --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA'`

Notes
- Enabling SSD→R led to coherent negative SSD→R paths and slight fit improvements (see results/stage2_sem_summary.md and artifacts/stage4_sem_summary/lavaan_fit_summary.csv).
- Expected effect: improves absolute fit where d-sep indicated missing SSD paths (especially M/N) and captures shared measurement noise with minimal, theory-backed residual covariances.

Stage 2 — Multigroup DAG → MAG Sequence (2025-08-13)
- Rationale and order of spells
  - First exhaust multigroup DAG (d-sep) to detect missing directed links or group-specific slopes with minimal added flexibility.
  - Upgrade to MAG (m-sep and/or residual covariances) only if misfit persists and appears residual-covariance-shaped rather than directional.
- Groups (initial): `Woodiness` (woody vs herbaceous). Later candidates: growth form, broad climate zone.
- Multigroup DAG d-sep (Ecosphere 2021)
  - Topology: keep the same DAG for all groups initially (y ~ LES + SIZE [+ logSSD per target]; LES ~ SIZE + logSSD; SIZE ~ logSSD).
  - Test: compute per-group Fisher’s C on the same union basis set and sum C and df across groups for a global test.
  - Command (per target X ∈ {L,T,M,R,N}):
    ```
    Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
      --input_csv=artifacts/model_data_complete_case.csv \
      --target={L|T|M|R|N} \
      --seed=123 --repeats=5 --folds=5 --stratify=true \
      --standardize=true --winsorize=false --weights=none \
      --out_dir=artifacts/stage4_sem_piecewise \
      --psem_drop_logssd_y=true --psem_include_size_eq=true \
      --group_var=Woodiness
    ```
  - Outputs:
    - Per-target CV: `artifacts/stage4_sem_piecewise/sem_piecewise_{X}_{preds.csv,metrics.json}` (unchanged).
    - Per-target single-group d-sep (if enabled): `sem_piecewise_{X}_dsep_fit.csv`.
    - Per-target multigroup d-sep summary: `sem_piecewise_{X}_multigroup_dsep.csv` (rows per group plus an Overall row with C=sum C_g, df=sum df_g, p from χ²(df)).
- Equality constraints across groups (roadmap)
  - Per-claim slope equality can be tested via interactions in local regressions (e.g., `Y ~ X + Z + group + X:group + Z:group`) and AIC selection per claim (as in Douma 2021). This will be added after the baseline multigroup C aggregation.
- MAG upgrade (SEM 2022)
  - If multigroup DAG misfit persists (e.g., poor lavaan absolute fit or structured residuals), add minimal bidirected edges (e.g., `LES ~~ SIZE`, `logH ~~ logSM`, `Nmass ~~ logLA`) and test via m-sep (MAG) or saturated-model LR.
  - Proxy in lavaan: allow the same residual covariances and refit with MLR + FIML; record ΔCFI/RMSEA/SRMR.
  - Piecewise MAG with copulas is possible but requires additional R packages and careful setup; keep to minimal, theory-backed residuals.

Repro Parameters and Hygiene
- CV: 5×5 repeated; transforms fitted on train folds only; seed=123 (or `--seed` recorded in metrics JSON).
- Standardization: z-scores on predictors within fold; log10 transforms with recorded positive offsets.
- Determinism: always print effective flags in metrics JSON and d-sep CSV.
- Assumptions: UTF-8; CSV comma; no network; R packages `piecewiseSEM`, `lme4` required for d-sep.

Multigroup Results and Minimal Tweaks (2025-08-13)
- Group: `Woodiness` (woody, non-woody, semi-woody).
- Equality tests (claim: `y ⟂ logSSD | {LES, SIZE}`): compared pooled vs by-group slopes for logSSD with AIC.
- Findings and adopted tweaks:
  - L: woody shows significant residual SSD effect (p≈0.0094); added `SSD → L` for woody only in d-sep. Overall Fisher’s C improved from p≈0.151 to p≈0.721 (woody saturated).
  - T: woody significant (p≈0.0035); added `SSD → T` for woody only. Overall Fisher’s C improved from p≈0.069 to p≈0.238 (woody saturated).
  - R: woody group misfit (p≈0.008); added `SSD → R` for woody only; Overall Fisher’s C improved from p≈0.047 to p≈0.528 (woody saturated).
  - M, N: forcing mediation-only was rejected; enabled direct `SSD → M` and `SSD → N` globally; psem becomes saturated (df=0), consistent with required direct effects.
- Predictive CV remained stable (e.g., L≈0.235, T≈0.222, M≈0.341, R≈0.139, N≈0.371 R² with 5× folds, seed=123), as expected for causal-fit-focused adjustments.
- Repro (examples):
  - `... --group_var=Woodiness --psem_drop_logssd_y=true --group_ssd_to_y_for=woody` (L/T/R runs)
  - `... --group_var=Woodiness --psem_drop_logssd_y=false` (M/N runs)

Multigroup lavaan (Woodiness) — group-specific SSD→{L,T,R}
- Rationale: mirror d-sep tweaks in a latent SEM to assess absolute fit shifts by group while retaining minimal residual covariances.
- Implementation: woody-only SSD→L/T/R via `--group=Woodiness --group_ssd_to_y_for=woody`, global SSD→M/N via `--add_direct_ssd_targets=M,N`.
- Fit deltas (CFI/RMSEA/SRMR):
  - L: woody ~ (0.763/0.205/0.106), non-woody ~ (0.733/0.185/0.087); baseline global ~ (0.716/0.174/0.101).
  - T: woody ~ (0.748/0.201/0.106), non-woody ~ (0.829/0.137/0.069); baseline ~ (0.709/0.164/0.096).
  - M: woody ~ (0.765/0.221/0.104), non-woody ~ (0.794/0.160/0.073), semi-woody ~ (0.704/0.424/0.181).
  - R: woody ~ (0.674/0.226/0.104), non-woody ~ (0.800/0.153/0.071), semi-woody ~ (0.681/0.429/0.182); baseline ~ (0.775/0.140/0.078).
- N: woody ~ (0.748/0.228/0.098), non-woody ~ (0.832/0.168/0.072), semi-woody ~ (0.712/0.432/0.161).
- Guidance:
  - Keep woody-only SSD→L/T/R in piecewise d-sep (causal tests), where it resolves group misfit decisively.
  - For lavaan absolute fit, woody-only vs global SSD→R produces similar woody fit and small shifts in non-woody; choose based on parsimony vs symmetry (no material difference here). Keep SSD→M/N global; SSD→L/T woody-only.

Why d-sep p-values improve while lavaan fit indices lag
- d-sep focuses on a small set of implied independencies; adding minimal directed edges resolves key violations with a large drop in Fisher’s C.
- lavaan’s fit is global (measurement + structural covariance). Diffuse residual misfit (missing residual covariances, nonlinearity) can keep CFI/TLI low and RMSEA/SRMR high even after d-sep passes.
- Composite vs latent representation: piecewise uses PCA-based composites aligned to regressions; lavaan uses latent constructs with strict loadings and sparse residual covariances—more constraints often mean worse absolute fit.

Decision: Move to MAG?
- Status: Multigroup d-sep now passes (Overall p>0.2 for L/T/R; M/N saturated), but lavaan absolute fit remains below conventional thresholds (CFI/TLI < 0.90; RMSEA > 0.08).
- Rationale to proceed to MAG:
  - Residual structure likely remains (shared measurement error or omitted common causes among indicators/traits), which d-sep does not model but MAG can via bidirected edges (dependent errors).
  - MAG/m-sep allows testing models with dependent errors without inflating directed topology; we can keep the minimal directed tweaks found via d-sep and add only a few theory-backed residual links.
- Planned minimal MAG edges (first pass): `LES ~~ SIZE`, `logH ~~ logSM`, `Nmass ~~ logLA` (already mirrored in lavaan). Consider group-invariant residuals initially; add group differences only if indicated.
- Verification path:
  1) Build MAG basis (CauseAndCorrelation::basiSet.mag) and test m-sep; confirm improved global fit vs DAG.
  2) Partition into district sets (CauseAndCorrelation::districtSet/Graph); fit with appropriate families; copulas for dependent errors if needed (Douma & Shipley 2022).
  3) Compare with saturated model via likelihood ratio; retain only residual edges that materially improve fit.
- Hygiene:
  - Keep number of bidirected edges minimal; prefer measurement-motivated pairs.
  - Maintain train/test hygiene for predictive components; m-sep testing uses full data.
Artifacts for review
- By-group fit CSV per target: `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,M,N,R}_fit_indices_by_group.csv`
- Aggregated by-group summary: `artifacts/stage4_sem_lavaan/lavaan_group_fit_summary.csv`

Compact table (key indices)

| Target | Group      | CFI  | RMSEA | SRMR |
|--------|------------|------|-------|------|
| L      | woody      | 0.763| 0.205 | 0.106|
| L      | non-woody  | 0.733| 0.185 | 0.087|
| T      | woody      | 0.748| 0.201 | 0.106|
| T      | non-woody  | 0.829| 0.137 | 0.069|
| M      | woody      | 0.765| 0.221 | 0.104|
| M      | non-woody  | 0.794| 0.160 | 0.073|
| M      | semi-woody | 0.704| 0.424 | 0.181|
| R      | woody      | 0.674| 0.226 | 0.104|
| R      | non-woody  | 0.800| 0.153 | 0.071|
| R      | semi-woody | 0.681| 0.429 | 0.182|
| N      | woody      | 0.748| 0.228 | 0.098|
| N      | non-woody  | 0.832| 0.168 | 0.072|
| N      | semi-woody | 0.712| 0.432 | 0.161|
