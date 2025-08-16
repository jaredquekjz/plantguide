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
   - Convert Excel to CSV: `src/Stage_1_Data_Extraction/convert_excel_to_csv.py`
   - WFO normalization (EXACT): `src/Stage_1_Data_Extraction/normalize_eive_to_wfo_EXACT.R`
2) TRY curated traits subset
   - Script: `src/Stage_1_Data_Extraction/match_trycurated_species_to_eive_wfo.R`
   - Outputs: `artifacts/traits_matched.{csv,rds}` — species matched to EIVE, with six core trait means.
3) Modeling dataset assembly (done)
  - Script: `src/Stage_2_Data_Processing/assemble_model_data.R`
   - Join `artifacts/traits_matched.rds` to EIVE indicators by WFO accepted name (normalized species name), one record per species.
   - Define `SSD used (mg/mm3)` for modeling as: observed SSD when available; otherwise the LDMC‑based imputed value from `SSD combined (mg/mm3)`. For the complete‑case filter, we require non‑missing `SSD combined (mg/mm3)` to maximize coverage. We also emit an observed‑SSD‑only complete‑case file for sensitivity.
   - Include provenance columns: `ssd_imputed_used` flag and `min_records_6traits`.
   - Outputs: `artifacts/model_data_full.csv`, `artifacts/model_data_complete_case.csv`, `artifacts/model_data_complete_case_observed_ssd.csv`.
   - Datasets:
     - Complete-case (baseline): species with all six traits present using SSD combined (≈1,069 species).
     - Observed‑SSD‑only (sensitivity): species with all six traits present using SSD observed only (≈389 species).
     - Full set: allow missing traits; reserved for FIML/MI later.

Empirical Coverage Snapshot (current repository state)
- Matched species with curated traits: 5,799 unique-name matches (artifacts/traits_matched: 5,800 rows).
- Complete-case (six traits present using SSD combined): 1,069 species.
  - SSD provenance within complete-case: 389 observed; 680 imputed via LDMC (combined = imputed).
  - If requiring observed SSD strictly: 389 species remain complete-case.
  - Implication: baseline models will use SSD combined; we will run an observed-only sensitivity analysis and report deltas.

Note on name normalization
- We unified species-name normalization across scripts to handle botanical hybrid signs (×), ASCII hybrid markers (" x "), diacritics (via transliteration), and whitespace/case in a consistent way. This reduces preventable mismatches between EIVE and TRY and slightly increases matched coverage.

TRY Curation Principles (from Enhanced Species-Level Trait Dataset)
- Species means: mature, healthy plants in natural conditions; aggregated from ~1M trait records (2,500+ sources) via TRY.
- QC workflow: probabilistic outlier detection + expert/external validation; harmonized units and protocols (Pérez‑Harguindeguy 2013; LEDA).
- Replicates metadata: curated tables include per-trait record counts (e.g., “(n.o.)” columns); many species have few records, some have many.
- SSD gaps: non‑woody SSD imputed from LDMC; curated files expose “SSD observed / imputed / combined”.
- Categorical context: woodiness, growth form, succulence, aquatic/terrestrial, nutrition type, leaf type; useful as covariates/random effects.

Modeling Implications We Will Apply
- SSD choice and filtering: baseline models use `SSD used (mg/mm3)`, which equals observed when present else the imputed value from `SSD combined`. Complete‑case membership is determined on `SSD combined` to retain coverage. We report an observed‑only SSD sensitivity subset and track `ssd_imputed_used` for transparency.
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
  - SSD used (mg/mm3) — observed where available; else imputed (from `SSD combined`)
