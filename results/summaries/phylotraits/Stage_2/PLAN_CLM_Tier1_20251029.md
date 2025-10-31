# CLM Baseline Pipeline Plan: Tier 1 with Canonical Shipley Specification

**Date:** 2025-10-29
**Purpose:** Run Shipley-style cumulative link model (CLM) baseline for comparison with XGBoost
**Scope:** Axes L, M, N for 1,084-species Tier 1 dataset
**Approach:** **Traits-only (no phylo)** - canonical Shipley et al. (2017) specification

---

## Rationale: Why Traits-Only CLM?

**Following the original Shipley et al. (2017) paper:**
- Shipley's canonical specification used **4 log-transformed traits + plant form**
- No phylogenetic predictor in the original paper
- No environmental variables (soil, climate)
- No cross-axis EIVE predictors

**Goal:** Establish a clean baseline showing:
1. How much functional traits alone can predict EIVE
2. The added value of XGBoost's environmental + phylo + cross-axis features
3. Fair comparison to the published Shipley results

---

## CLM Feature Specification (Canonical Shipley)

### Predictors (Traits Only)

**Categorical:**
- `plant_form`: 4 levels (graminoid, herb, shrub, tree)

**Continuous (log-transformed):**
- `logLA`: log(Leaf Area)
- `logLDMC`: log(Leaf Dry Matter Content)
- `logSLA`: log(Specific Leaf Area)
- `logSM`: log(Seed Mass)

**Interactions (as per Shipley et al. 2017):**
- All 2-way log-trait combinations
- All 3-way log-trait combinations
- All 4-way log-trait combinations
- Trait × plant_form slopes

**Total:** ~30-40 terms (main effects + interactions)

### Response Variable

- Target: `EIVEres-L`, `EIVEres-M`, `EIVEres-N`
- Encoding: `ordered(round(axis_value) + 1)` → 11 ordinal categories (1-11)

### Model Specification

```r
vglm(
  ordered_response ~ plant_form +
    logLA + logLDMC + logSLA + logSM +
    logLA:logLDMC + logLA:logSLA + ... (all 2-way) +
    logLA:logLDMC:logSLA + ... (all 3-way) +
    logLA:logLDMC:logSLA:logSM + (4-way) +
    plant_form:logLA + ... (form × trait slopes),
  family = cumulative(link = "logit", parallel = TRUE),
  data = training_data
)
```

---

## Pipeline Steps

### Step 1: Build CLM Master Table

**Input:** Tier 1 modelling master with corrected phylo
- `model_data/inputs/modelling_master_1084_tier1_20251029.parquet`

**Extract columns needed for CLM:**
- Identifiers: `wfo_taxon_id`, `wfo_scientific_name`
- Targets: `EIVEres-L`, `EIVEres-M`, `EIVEres-N`
- Traits: `logLA`, `logLDMC`, `logSLA`, `logSM` (already log-transformed)
- Growth form info: `try_growth_form`, `try_woodiness` → derive `plant_form`

**Script:** `src/Stage_2/build_clm_master.py`

**Command:**
```bash
/home/olier/miniconda3/envs/AI/bin/python src/Stage_2/build_clm_master.py \
  --input model_data/inputs/modelling_master_1084_tier1_20251029.parquet \
  --output model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv \
  --axes L,M,N
```

**Expected output:**
- File: `clm_master_tier1_20251029.csv`
- Columns: wfo_taxon_id, wfo_scientific_name, EIVEres-L, EIVEres-M, EIVEres-N,
           Leaf area (mm2), LDMC, LMA (g/m2), Diaspore mass (mg), Plant height (m),
           Growth Form, Woodiness, plant_form
- Rows: 1,084 species

### Step 2: Run Traits-Only CLM (No Phylo)

**For each axis (L, M, N):**

**Script:** `src/legacy/Stage_4_SEM_Analysis/run_clm_trait_phylo.R`
(Modify to use Tier 1 data and disable phylo predictor)

**Command template:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/legacy/Stage_4_SEM_Analysis/run_clm_trait_phylo.R \
    --axis {L|M|N} \
    --input model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv \
    --out_dir artifacts/stage2_clm_trait_only_tier1_20251029/{AXIS} \
    --folds 10 \
    --repeats 1 \
    --no_phylo \
    --seed 42
```

**Expected outputs per axis:**
- `cv_predictions.csv` - Cross-validated predictions
- `cv_metrics.csv` - MAE, RMSE, ±1/±2 hit rates, R²
- `coefficients.csv` - Model coefficients
- `final_model.rds` - Trained model on full data

### Step 3: Calculate Metrics

**For each axis, extract from CV predictions:**

**Metrics to report:**
- R² (from aggregated CV predictions)
- RMSE
- MAE
- Accuracy ±1 rank (% within ±1 integer rank)
- Accuracy ±2 ranks (% within ±2 integer ranks)

**Calculation:**
```r
# After rounding predictions to integer ranks
truth_rank <- round(cv_predictions$truth)
pred_rank <- round(cv_predictions$prediction)

acc_pm1 <- mean(abs(truth_rank - pred_rank) <= 1)
acc_pm2 <- mean(abs(truth_rank - pred_rank) <= 2)
r2 <- cor(truth, prediction)^2
```

### Step 4: Compare CLM vs XGBoost

**Create comparison table for each axis:**

| Metric | CLM (traits only) | XGBoost (Tier 1) | XGBoost Advantage |
|--------|-------------------|------------------|-------------------|
| R² | ? | 0.621 (L) / 0.675 (M) / 0.701 (N) | ? |
| RMSE | ? | 0.911 (L) / 0.881 (M) / 1.026 (N) | ? |
| Acc±1 | ? | 88.0% (L) / 90.1% (M) / 84.5% (N) | ? |

**Expected findings:**
- CLM R² ~ 0.25-0.40 (traits alone, no env/phylo/cross-axis)
- XGBoost R² ~ 0.62-0.70 (full feature set)
- XGBoost advantage: +0.20-0.40 R², +10-15% accuracy

**Why XGBoost beats CLM:**
1. **Feature richness:** 741 features (env quantiles, phylo, cross-axis) vs 4 traits
2. **Automatic interactions:** Trees find complex patterns without manual specification
3. **Non-linearity:** Flexible splits vs linear ordinal regression
4. **Cross-axis signal:** EIVEres-M/N/R predictors add +0.03-0.10 R²

---

## Script Modifications Needed

### 1. Update `build_clm_master.py`

**Modifications:**
- Accept `--input` pointing to Tier 1 parquet
- Extract Tier 1 phylo columns (but won't use them for traits-only)
- Handle column name mapping (try_* → legacy CLM names)
- Output to `model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv`

### 2. Adapt `run_clm_trait_phylo.R`

**Modifications:**
- Point to new CLM master path
- Ensure `--no_phylo` flag works correctly
- Update output paths for Tier 1 results
- Use 10-fold CV (match XGBoost setup)
- Seed = 42 (match XGBoost)

**No changes to:**
- Model specification (keep Shipley's trait interactions)
- Response encoding (ordered 11-category)
- Fitting engine (VGAM cumulative logit)

---

## Expected Runtime

**Per axis:**
- CLM fitting: ~2-5 minutes per fold
- 10 folds × 3 axes = 30 folds total
- Total: ~60-150 minutes (~1-2.5 hours)

**Sequential execution** (avoid memory issues with VGAM):
```bash
# L-axis
run_clm_trait_phylo.R --axis L --no_phylo ...

# M-axis
run_clm_trait_phylo.R --axis M --no_phylo ...

# N-axis
run_clm_trait_phylo.R --axis N --no_phylo ...
```

---

## Deliverables

**1. CLM master table:**
- `model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv`

**2. CLM results per axis:**
- `artifacts/stage2_clm_trait_only_tier1_20251029/L/cv_metrics.csv`
- `artifacts/stage2_clm_trait_only_tier1_20251029/M/cv_metrics.csv`
- `artifacts/stage2_clm_trait_only_tier1_20251029/N/cv_metrics.csv`

**3. Comparison document:**
- `results/summaries/hybrid_axes/phylotraits/Stage_2/2.6_CLM_vs_XGBoost_Tier1.md`
  - CLM metrics (traits only)
  - XGBoost metrics (full features)
  - Gap analysis
  - Ecological interpretation

**4. Verification:**
- Check CLM metrics match expected range from Shipley (2017)
- Confirm XGBoost advantage is statistically meaningful
- Document feature contribution breakdown

---

## Comparison to Shipley et al. (2017)

**Original paper (Table 3):**

| Axis | Species | Exact hits | ±1 Hit | ±2 Hit |
|------|---------|------------|--------|--------|
| L | 972 | 63.7% | ~80% | 96.5% |
| M | 981 | 45.2% | ~70% | 97.4% |
| N | 922 | 39.5% | ~65% | 90.7% |

**Our Tier 1 CLM (expected):**
- Similar ±1 accuracy (~70-80%)
- Similar ±2 accuracy (~90-95%)
- Slightly different species set (1,084 European flora)

**Our Tier 1 XGBoost:**
- ±1 accuracy: 84-90% (+10-15% vs CLM)
- ±2 accuracy: 98-99% (+5-8% vs CLM)
- R²: 0.62-0.70 (+0.25-0.35 vs CLM)

---

## Next Steps After CLM Completion

1. **Document results** in 2.6_CLM_vs_XGBoost_Tier1.md
2. **Interpret gap:** Why does XGBoost pull ahead?
3. **Feature ablation:** Test XGBoost with traits-only to isolate env/phylo contributions
4. **Decision:** Keep CLM as historical baseline or focus on XGBoost?

---

**Status:** PLAN READY
**Prerequisite:** Tier 1 modelling master with corrected phylo (✓ COMPLETED)
**Estimated time:** 2-3 hours for all 3 axes
**Next action:** Modify scripts and execute pipeline
