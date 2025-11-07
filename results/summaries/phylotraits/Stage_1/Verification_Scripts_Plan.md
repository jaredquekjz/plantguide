# Verification Scripts Design Plan

**Purpose**: Design rigorous internal verification scripts for each critical junction in Bill's verification pipeline

**Principle**: Each verification script should comprehensively check data integrity, completeness, and validity WITHOUT comparing to Python canonical outputs

---

## Verification Script Overview

### Phase 0: WFO Normalization
1. `verify_wfo_matching_bill.R` - After WorldFlora matching completes

### Phase 1: Core Integration
2. `verify_enriched_parquets_bill.R` - After building enriched parquets
3. `verify_master_shortlist_bill.R` - After creating master union & shortlist (combines existing verify_stage1_integrity_bill.R)
4. `verify_gbif_integration_bill.R` - After GBIF count integration

### Phase 2: Environmental Data
5. `verify_env_aggregation_bill.R` - After environmental summary & quantile aggregation (combines existing verify_env_integrity_bill.R)

### Phase 3: Imputation Dataset
6. `verify_phylo_eigenvectors_bill.R` - After phylogenetic eigenvector extraction
7. `verify_canonical_assembly_bill.R` - After canonical imputation input assembly

### Stage 1: Trait Imputation
8. `verify_mixgb_cv_bill.R` - After cross-validation completes
9. `verify_production_imputation_bill.R` - After production imputation completes
10. `verify_complete_dataset_bill.R` - After assembling complete dataset (already exists, may need enhancement)

### Stage 2: EIVE Prediction
11. `verify_stage2_features_bill.R` - After building per-axis feature tables
12. `verify_stage2_training_bill.R` - After XGBoost training completes
13. `verify_eive_imputation_bill.R` - After EIVE imputation completes

**Total: 13 comprehensive verification scripts**

---

## Detailed Script Specifications

### 1. verify_wfo_matching_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify WorldFlora matching outputs are complete and valid

**Inputs**:
- 8 WorldFlora output CSVs: `data/shipley_checks/wfo_verification/*_wfo.csv`

**Checks**:

1. **File Existence**:
   - All 8 expected CSV files present
   - No empty files (file size > 0)

2. **Row Counts**:
   - Duke: 14,027 rows
   - EIVE: 14,835 rows
   - Mabberly: 13,489 rows
   - TRY Enhanced: 46,047 rows
   - AusTraits: 33,370 rows
   - GBIF: 160,713 rows
   - GloBI: 74,002 rows
   - TRY Selected: 80,788 rows
   - Tolerance: ±10 rows (minor extraction differences acceptable)

3. **Column Completeness**:
   - All expected WFO columns present: `OriSeq`, `Input`, `Matched`, `Genus`, `Species`, `Family`, `taxonID`, etc.
   - No completely empty columns

4. **Data Quality**:
   - No duplicate WFO IDs (taxonID) within each dataset
   - No blank taxonomy (all matched records have genus/species)
   - Match success rates within expected range:
     - Duke: 75-90%
     - EIVE: 90-98%
     - Mabberly: 97-100%
     - TRY Enhanced: 85-95%
     - AusTraits: 85-95%
     - GBIF: 80-90%
     - GloBI: 70-85%
     - TRY Selected: 85-95%

5. **WFO ID Format**:
   - All taxonID values start with "wfo-" prefix
   - No malformed IDs

**Output**: Summary report with ✓/✗ for each check, fail on first critical error

**Exit code**: 0 if all pass, 1 if any critical check fails

---

### 2. verify_enriched_parquets_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify merge of WFO taxonomy with original datasets

**Inputs**:
- 6 enriched parquets: `data/shipley_checks/wfo_verification/*_worldflora_enriched.parquet`
- Original 8 parquets (for row count comparison)

**Checks**:

1. **File Existence**:
   - All 6 expected parquet files present
   - File sizes reasonable (> 100 KB)

2. **Row Counts Match Input**:
   - Duke enriched: 14,030 rows (matches WFO output ±5)
   - EIVE enriched: 14,835 rows
   - Mabberly enriched: 13,489 rows
   - TRY Enhanced enriched: 46,047 rows
   - AusTraits traits enriched: 1,798,215 rows (traits × taxa)
   - TRY Selected enriched: 618,932 rows (traits × taxa)

3. **Merge Success**:
   - All rows have wfo_taxon_id populated (no NA)
   - All rows have wfo_scientific_name populated
   - No rows lost during merge (left join preserved all original records)

4. **Column Schema**:
   - All original columns present
   - WFO columns added: `wfo_taxon_id`, `wfo_scientific_name`, `genus`, `family`
   - No duplicate column names

5. **Data Integrity**:
   - Original data unchanged (spot-check 10 random rows)
   - No duplicate rows introduced by merge
   - WFO taxonomy consistent (same wfo_taxon_id → same scientific name)

**Output**: Per-dataset verification report, overall pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 3. verify_master_shortlist_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify master taxa union and shortlist creation logic

**Inputs**:
- Bill's enriched parquets
- Output: `data/shipley_checks/master_taxa_union_bill.parquet`
- Output: `data/shipley_checks/stage1_shortlist_candidates_bill.parquet`

**Checks**:

1. **Master Taxa Union**:
   - Row count: 86,592 unique WFO taxa (±50 tolerance)
   - No duplicate wfo_taxon_id
   - Source coverage flags correct:
     - has_duke, has_eive, has_mabberly, has_tryenhanced, has_austraits (all boolean)
   - Source counts sum correctly:
     - Duke: ~10,640 taxa with flag=TRUE
     - EIVE: ~12,868 taxa
     - Mabberly: ~12,664 taxa
     - TRY Enhanced: ~44,266 taxa
     - AusTraits: ~28,072 taxa
   - Deduplication logic verified:
     - For taxa in multiple sources, highest-rank source wins
     - Rank order: EIVE > TRY Enhanced > AusTraits > Duke > Mabberly

2. **Shortlist Candidates**:
   - Row count: 24,511 species (±50 tolerance)
   - No duplicate wfo_taxon_id
   - Trait-richness filters applied correctly:
     - `eive_numeric_count >= 3`: verify counts
     - `try_numeric_count >= 3`: verify counts
     - `austraits_numeric_count >= 3`: verify counts
   - Qualification flags correct:
     - `qualified_by_eive`, `qualified_by_try`, `qualified_by_austraits` (boolean)
   - Expected trait counts:
     - Species with EIVE ≥3: ~12,599
     - Species with TRY ≥3: ~12,655
     - Species with AusTraits ≥3: ~3,849

3. **Data Consistency**:
   - All shortlist species exist in master union
   - Trait counts are non-negative integers
   - At least one qualification flag TRUE per species

**Output**: Detailed verification report with counts, pass/fail per check

**Exit code**: 0 if all pass, 1 if any critical check fails

---

### 4. verify_gbif_integration_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify GBIF occurrence count integration and filtering

**Inputs**:
- GBIF occurrence data: `data/gbif/occurrence_plantae.parquet`
- Output: `data/shipley_checks/stage1_shortlist_with_gbif_ge30_bill.parquet`

**Checks**:

1. **GBIF Count Aggregation**:
   - Total unique WFO taxa with GBIF: ~144,655
   - Total occurrences counted: ~48,977,163
   - Total georeferenced: ~48,886,200
   - Counts are non-negative integers

2. **Merge with Shortlist**:
   - All shortlist species (24,511) attempted merge
   - Species with GBIF records: ~18,451 (75% match rate)
   - No NA in gbif_occurrence_count for matched species
   - No NA in gbif_georeferenced_count for matched species
   - Unmatched species have NA GBIF counts (expected)

3. **Filter to ≥30 Occurrences**:
   - Final species count: 11,711 (±20 tolerance)
   - All species have gbif_occurrence_count ≥ 30 (verify 100%)
   - No species with < 30 occurrences present
   - No duplicate wfo_taxon_id

4. **Data Integrity**:
   - All columns from shortlist preserved
   - GBIF columns added: `gbif_occurrence_count`, `gbif_georeferenced_count`
   - georeferenced_count ≤ occurrence_count (logical constraint)

**Output**: Summary report with counts, filter verification, pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 5. verify_env_aggregation_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify environmental summary and quantile aggregations

**Inputs**:
- Summary parquets: `data/shipley_checks/{worldclim,soilgrids,agroclime}_species_summary_R.parquet`
- Quantile parquets: `data/shipley_checks/{worldclim,soilgrids,agroclime}_species_quantiles_R.parquet`

**Checks**:

1. **File Existence & Coverage**:
   - All 6 files present (3 summaries + 3 quantiles)
   - All files contain 11,711 species
   - No duplicate wfo_taxon_id in any file

2. **Variable Counts**:
   - WorldClim: 63 variables
   - SoilGrids: 42 variables
   - Agroclim: 51 variables
   - Each variable has 4 summary stats (mean, stddev, min, max)
   - Each variable has 4 quantile stats (q05, q50, q95, iqr)

3. **Summary Statistics Validity**:
   - No NA in mean (mandatory aggregation)
   - No NA in q50 (mandatory aggregation)
   - stddev ≥ 0 (non-negative)
   - iqr ≥ 0 (non-negative)
   - min ≤ mean ≤ max (logical constraint)
   - Value ranges reasonable:
     - Temperature: -50 to 50°C
     - Precipitation: 0 to 10,000 mm
     - Soil pH: 3 to 10

4. **Quantile Ordering**:
   - For each species and variable: q05 ≤ q50 ≤ q95
   - Check 100% compliance (all species × all variables)
   - iqr = q95 - q05 (verify calculation)

5. **Data Type Consistency**:
   - All aggregated values are numeric (not character)
   - No Inf/-Inf values
   - No excessively large values (> 1e10, likely error)

**Output**: Per-dataset report, quantile ordering check results, overall pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 6. verify_phylo_eigenvectors_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify phylogenetic eigenvector extraction

**Inputs**:
- Phylo tree: `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk`
- Mapping: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv`
- Output: `data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv`

**Checks**:

1. **Tree Properties**:
   - Tree loaded successfully (ape::read.tree)
   - Tree has 11,010 tips (±10 tolerance)
   - Tree is ultrametric (all tips equidistant from root)
   - No negative branch lengths

2. **Mapping Completeness**:
   - Mapping has 11,711 rows (all shortlist species)
   - Species with tree tips: ~11,673 (99.7%)
   - Unmapped species: ~38 (0.3%)
   - No duplicate wfo_taxon_id in mapping

3. **Eigenvector Output**:
   - Dimensions: 11,711 rows × 93 columns (wfo_taxon_id + 92 eigenvectors)
   - No duplicate wfo_taxon_id
   - Eigenvector columns: phylo_ev1 through phylo_ev92

4. **Eigenvector Properties**:
   - All eigenvector columns are numeric
   - No Inf/-Inf values
   - Coverage: ~11,673 species with non-NA eigenvectors (99.7%)
   - 38 species with all NA eigenvectors (unmapped)
   - Eigenvectors are mean-centered (mean ≈ 0 for each column)
   - Variance explained: Verify broken stick rule (first eigenvector > last)

5. **Mathematical Properties**:
   - Eigenvectors are orthogonal (spot-check correlation matrix)
   - First eigenvector captures most variance
   - Variance explained decreasing from ev1 to ev92

**Output**: Tree properties, coverage report, eigenvector validation, pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 7. verify_canonical_assembly_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify canonical imputation input assembly (comprehensive version of existing verify_complete_imputation_bill.R)

**Inputs**:
- Output: `data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv`

**Checks**:

1. **Dimensions**:
   - Rows: 11,711 species (exact)
   - Columns: 736 (exact)

2. **Column Presence & Categories**:
   - IDs: 2 (wfo_taxon_id, wfo_scientific_name)
   - Log traits: 6 (logLA, logNmass, logLDMC, logSLA, logH, logSM)
   - Categorical: 7 (try_woodiness, try_growth_form, try_habitat_adaptation, try_leaf_type, try_leaf_phenology, try_photosynthesis_pathway, try_mycorrhiza_type)
   - EIVE: 5 (EIVEres-L, EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R)
   - Phylo eigenvectors: 92 (phylo_ev1...phylo_ev92)
   - Environmental q50: 156 (WorldClim + SoilGrids + Agroclim medians)
   - Environmental quantiles: 468 (q05, q95, iqr for 156 vars)

3. **Anti-Leakage Verification** (CRITICAL):
   - NO raw trait columns present:
     - leaf_area_mm2, nmass_mg_g, ldmc_g_g, sla_mm2_mg, plant_height_m, seed_mass_mg
   - NO LMA columns present:
     - try_lma_g_m2, aust_lma_g_m2
   - Script MUST FAIL if any raw trait column found

4. **Log Trait Coverage** (before imputation):
   - logLA: 44-46% (5,200-5,400 species)
   - logNmass: 34-36% (4,000-4,200 species)
   - logLDMC: 21-23% (2,500-2,700 species)
   - logSLA: 47-49% (5,500-5,700 species)
   - logH: 76-78% (8,900-9,100 species)
   - logSM: 65-67% (7,600-7,800 species)

5. **Categorical Trait Coverage**:
   - try_woodiness: 77-80% (9,000-9,400 species)
   - try_growth_form: 76-79% (8,900-9,200 species)
   - try_habitat_adaptation: 74-76% (8,600-8,900 species)
   - try_leaf_type: 76-78% (8,900-9,100 species)
   - try_leaf_phenology: 48-51% (5,600-6,000 species) ← CRITICAL: Must be > 0% (bug fix verification)
   - try_photosynthesis_pathway: 69-72% (8,100-8,400 species) ← CRITICAL: Must be > 0%
   - try_mycorrhiza_type: 23-25% (2,700-2,900 species) ← CRITICAL: Must be > 0%

6. **EIVE Coverage**:
   - EIVEres-L: 51-54% (6,000-6,300 species)
   - EIVEres-T: 52-55% (6,100-6,400 species)
   - EIVEres-M: 52-55% (6,100-6,400 species)
   - EIVEres-N: 50-53% (5,900-6,200 species)
   - EIVEres-R: 51-53% (6,000-6,200 species)

7. **Phylogenetic Coverage**:
   - 99.6-99.8% species with non-NA eigenvectors (11,650-11,690 species)

8. **Environmental Coverage**:
   - 100% coverage for all q50 features (156 vars)
   - 100% coverage for all quantiles (468 vars)

9. **Value Ranges** (spot-check):
   - Log traits: Verify reasonable ranges (e.g., logH: -5 to 5)
   - EIVE: 1-9 for L/T/M/R, 1-12 for N
   - Environmental: No extreme outliers (> 5 SD from mean)

10. **Data Types**:
    - IDs: character
    - Log traits: numeric
    - Categorical: character or factor
    - EIVE: numeric
    - Phylo eigenvectors: numeric
    - Environmental: numeric

**Output**: Comprehensive report with all checks, coverage percentages, anti-leakage verification, pass/fail

**Exit code**: 0 if all pass, 1 if critical check fails (especially anti-leakage)

---

### 8. verify_mixgb_cv_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify cross-validation completeness and results validity

**Inputs**:
- CV metrics: `data/shipley_checks/imputation/mixgb_cv_rmse_bill.csv`
- CV predictions: `data/shipley_checks/imputation/mixgb_cv_rmse_bill_predictions.csv`

**Checks**:

1. **Completeness**:
   - CV metrics file has 60 rows (6 traits × 10 folds)
   - CV predictions file present
   - All traits present: logLA, logNmass, logLDMC, logSLA, logH, logSM
   - All folds present: 1-10 for each trait

2. **CV Metrics Validity**:
   - All R² values: 0 < R² < 1
   - All RMSE values: RMSE > 0
   - All MdAPE values: 0 < MdAPE < 100
   - Tolerance bands: 0 ≤ within_10pct ≤ 100, within_25pct ≤ 100, within_50pct ≤ 100
   - No NA values in any metric

3. **Expected Results** (with 7 categorical traits):
   - logLA: R² = 0.45-0.53, RMSE = 1.4-1.6
   - logNmass: R² = 0.42-0.50, RMSE = 0.30-0.36
   - logLDMC: R² = 0.45-0.55, RMSE = 0.36-0.42
   - logSLA: R² = 0.45-0.52, RMSE = 0.50-0.56
   - logH: R² = 0.70-0.78, RMSE = 0.90-1.00
   - logSM: R² = 0.68-0.76, RMSE = 1.60-1.80

4. **Fold Consistency**:
   - No single fold with R² < 0 (model failure)
   - Standard deviation across folds reasonable (CV < 20%)
   - No outlier folds (> 3 SD from mean)

5. **Sample Sizes**:
   - logLA: ~5,200-5,300 observations
   - logNmass: ~4,000-4,100 observations
   - logLDMC: ~2,500-2,600 observations
   - logSLA: ~6,800-6,900 observations
   - logH: ~9,000-9,100 observations
   - logSM: ~7,600-7,800 observations

**Output**: Per-trait summary, fold consistency check, expected vs actual comparison, pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 9. verify_production_imputation_bill.R

**Location**: `src/Stage_1/bill_verification/`

**Purpose**: Verify production imputation completeness and PMM validity

**Inputs**:
- 10 individual runs: `data/shipley_checks/imputation/mixgb_imputed_bill_7cats_m{1-10}.csv`
- Ensemble mean: `data/shipley_checks/imputation/mixgb_imputed_bill_7cats_mean.csv`

**Checks**:

1. **File Existence**:
   - All 10 individual runs present (m1-m10)
   - Ensemble mean present
   - All files > 1 MB (reasonable size)

2. **Dimensions**:
   - All files: 11,711 rows × 8 columns (wfo_taxon_id, wfo_scientific_name, 6 traits)
   - No extra/missing columns

3. **Completeness** (CRITICAL):
   - All 6 traits: 0 missing values (100% coverage)
   - Verify for each file (m1-m10 + mean)
   - logLA: 11,711 complete
   - logNmass: 11,711 complete
   - logLDMC: 11,711 complete
   - logSLA: 11,711 complete
   - logH: 11,711 complete
   - logSM: 11,711 complete

4. **PMM Validity** (check ensemble mean):
   - All values within observed ranges (no extrapolation):
     - logLA: min/max from training data
     - logNmass: min/max from training data
     - logLDMC: min/max from training data
     - logSLA: min/max from training data
     - logH: min/max from training data
     - logSM: min/max from training data
   - Load original observed values to get true min/max
   - Tolerance: ±0.01 (floating point precision)

5. **Ensemble Stability**:
   - For each trait, compute CV across 10 runs
   - CV < 15% for all traits (reasonable stability)
   - Mean CV across all traits < 10% (overall stability)

6. **Imputation Counts**:
   - logLA: ~6,485 imputed (11,711 - 5,226 observed)
   - logNmass: ~7,706 imputed
   - logLDMC: ~9,144 imputed
   - logSLA: ~4,865 imputed
   - logH: ~2,682 imputed
   - logSM: ~4,011 imputed

7. **Data Integrity**:
   - No duplicate wfo_taxon_id
   - Observed values unchanged (spot-check against input)
   - All data types numeric

**Output**: Completeness report, PMM validation, ensemble stability, pass/fail

**Exit code**: 0 if all pass, 1 if critical check fails (completeness, PMM extrapolation)

---

### 10. verify_complete_dataset_bill.R

**Location**: `src/Stage_1/bill_verification/` (already exists, enhance)

**Purpose**: Verify complete dataset assembly after imputation

**Current status**: EXISTS as `verify_complete_imputation_bill.R`, may need enhancement

**Inputs**:
- Output: `data/shipley_checks/imputation/bill_complete_11711_20251107.csv`

**Checks** (enhance existing script):

1. **Dimensions**:
   - 11,711 rows × 736 columns

2. **Log Trait Completeness** (CRITICAL):
   - All 6 traits: 0 missing (100%)
   - Verify imputation succeeded

3. **Feature Group Presence**:
   - Log traits: 6
   - Phylo eigenvectors: 92
   - EIVE: 5
   - Categorical: 7
   - Environmental: 624

4. **Categorical Trait Verification**:
   - Same coverage as canonical input (~24-79%)
   - 3 fixed traits still have proper coverage (> 0%)

5. **Data Integrity**:
   - No duplicate wfo_taxon_id
   - All expected columns present
   - No unexpected zero patterns

**Output**: Enhanced report, pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 11. verify_stage2_features_bill.R

**Location**: `src/Stage_2/bill_verification/`

**Purpose**: Verify per-axis feature table construction

**Inputs**:
- 5 feature tables: `data/shipley_checks/stage2_features/{L,T,M,N,R}_features_11711_bill_20251107.csv`

**Checks**:

1. **File Existence**:
   - All 5 axis files present (L, T, M, N, R)

2. **Dimensions** (per axis):
   - L: ~6,190 rows × ~750 columns
   - T: ~6,238 rows × ~750 columns
   - M: ~6,261 rows × ~750 columns
   - N: ~6,027 rows × ~750 columns
   - R: ~6,082 rows × ~750 columns

3. **Species Filtering**:
   - Each file contains only species with observed EIVE for that axis
   - No species with missing target axis present

4. **Feature Composition** (per axis):
   - IDs: 2 (wfo_taxon_id, wfo_scientific_name)
   - Log traits: 6 (100% complete)
   - Phylo eigenvectors: 92
   - Environmental: 624
   - Categorical one-hot: ~18 dummy columns (from 7 categorical traits)
   - Target 'y': 1 (current axis EIVE only)
   - Total: ~743 columns

5. **Anti-Leakage** (CRITICAL):
   - NO cross-axis EIVE present (only target axis as 'y')
   - For L features: EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R must NOT be present
   - For T features: EIVEres-L, EIVEres-M, EIVEres-N, EIVEres-R must NOT be present
   - etc. for each axis

6. **One-Hot Encoding Validation**:
   - Original 7 categorical columns removed
   - ~18 dummy columns added (depending on factor levels)
   - Dummy columns are binary (0/1 or TRUE/FALSE)
   - Each row sums to ≤7 across all dummies (one category per trait)

7. **Target Column**:
   - Column named 'y' present
   - 'y' contains EIVE values for current axis only
   - 'y' range: 1-9 for L/T/M/R, 1-12 for N
   - No NA in 'y' (already filtered to observed)

8. **Data Completeness**:
   - Log traits: 100% complete (no NA)
   - Phylo eigenvectors: 99.7% complete
   - Environmental: 100% complete

**Output**: Per-axis report, anti-leakage verification, one-hot encoding check, pass/fail

**Exit code**: 0 if all pass, 1 if critical check fails (anti-leakage, target column)

---

### 12. verify_stage2_training_bill.R

**Location**: `src/Stage_2/bill_verification/`

**Purpose**: Verify XGBoost Stage 2 training completeness and quality

**Inputs**:
- 5 model files: `data/shipley_checks/stage2_models/xgb_{L,T,M,N,R}_model.json`
- 5 scaler files: `data/shipley_checks/stage2_models/xgb_{L,T,M,N,R}_scaler.json`
- 5 CV metrics: `data/shipley_checks/stage2_models/xgb_{L,T,M,N,R}_cv_metrics.json`

**Checks**:

1. **File Existence**:
   - All 5 models present (L, T, M, N, R)
   - All 5 scalers present
   - All 5 CV metrics present

2. **Model File Validity**:
   - All model files > 100 KB (reasonable size)
   - JSON files valid (parse without error)

3. **CV Metrics** (per axis):
   - Expected performance (with one-hot categorical):
     - L: R² = 0.55-0.65, RMSE = 0.90-1.05, Acc±1 = 85-90%
     - T: R² = 0.78-0.85, RMSE = 0.75-0.85, Acc±1 = 91-95%
     - M: R² = 0.62-0.70, RMSE = 0.88-0.98, Acc±1 = 87-92%
     - N: R² = 0.56-0.64, RMSE = 1.15-1.25, Acc±1 = 78-83%
     - R: R² = 0.40-0.48, RMSE = 1.15-1.25, Acc±1 = 79-84%

4. **Model Quality**:
   - All R² > 0 (no negative predictive power)
   - All RMSE > 0
   - Acc±1 (ordinal accuracy) ≥ 75% for all axes
   - Acc±2 ≥ 90% for all axes

5. **Cross-Validation Stability**:
   - 10 folds completed for each axis
   - No fold with negative R²
   - CV < 10% for R² across folds (reasonable stability)

6. **Comparison to Baseline** (if baseline exists):
   - With one-hot categorical vs without categorical
   - Expected improvement: +2-6% R² per axis

**Output**: Per-axis training report, CV metrics summary, quality checks, pass/fail

**Exit code**: 0 if all pass, 1 if any check fails

---

### 13. verify_eive_imputation_bill.R

**Location**: `src/Stage_2/bill_verification/`

**Purpose**: Verify EIVE imputation completeness and validity

**Inputs**:
- Per-axis predictions: `data/shipley_checks/stage2_predictions/{L,T,M,N,R}_predictions_bill_20251107.csv`
- Final dataset: `data/shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv`

**Checks**:

1. **File Existence**:
   - All 5 per-axis prediction files present
   - Final combined dataset present

2. **Prediction Counts** (per axis):
   - L: ~5,521 predictions
   - T: ~5,473 predictions
   - M: ~5,450 predictions
   - N: ~5,684 predictions
   - R: ~5,629 predictions
   - Total predictions: ~27,757 (across all axes)

3. **Final Dataset Dimensions**:
   - 11,711 species (all species from shortlist)
   - All EIVE columns present: EIVEres-L, EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R

4. **EIVE Completeness** (CRITICAL):
   - All 5 EIVE axes: 0 missing (100% coverage)
   - EIVEres-L: 11,711 complete
   - EIVEres-T: 11,711 complete
   - EIVEres-M: 11,711 complete
   - EIVEres-N: 11,711 complete
   - EIVEres-R: 11,711 complete

5. **Value Validity**:
   - All values within valid ranges:
     - L: 1-9
     - T: 1-9
     - M: 1-9
     - N: 1-12 (nitrogen has extended range)
     - R: 1-9
   - No values < 1 or > max for each axis
   - Tolerance: ±0.1 (may need rounding)

6. **Observed vs Imputed**:
   - Original observed EIVE unchanged (spot-check)
   - Only missing values imputed
   - Missingness resolved:
     - Complete EIVE (5/5): ~50.7% → 100% (target achieved)
     - No EIVE (0/5): 46.4% → 0% (all imputed)
     - Partial EIVE (1-4): 2.9% → 0% (completed)

7. **Data Integrity**:
   - No duplicate wfo_taxon_id
   - All EIVE columns numeric
   - No Inf/-Inf values
   - No extreme outliers (> 5 SD from mean per axis)

**Output**: Completeness report, value validation, imputation counts, pass/fail

**Exit code**: 0 if all pass, 1 if critical check fails (completeness, invalid values)

---

## Implementation Priority

### High Priority (Critical junctions):
1. **verify_canonical_assembly_bill.R** - Anti-leakage is critical
2. **verify_production_imputation_bill.R** - 100% completeness is critical
3. **verify_stage2_features_bill.R** - Cross-axis leakage prevention critical
4. **verify_eive_imputation_bill.R** - Final output validation critical

### Medium Priority (Data integrity):
5. **verify_master_shortlist_bill.R** - Deduplication logic verification
6. **verify_gbif_integration_bill.R** - Filter application verification
7. **verify_env_aggregation_bill.R** - Quantile ordering verification
8. **verify_stage2_training_bill.R** - Model quality verification

### Lower Priority (Sanity checks):
9. **verify_wfo_matching_bill.R** - Upstream data quality
10. **verify_enriched_parquets_bill.R** - Merge success
11. **verify_phylo_eigenvectors_bill.R** - Phylo extraction quality
12. **verify_mixgb_cv_bill.R** - CV completeness
13. **verify_complete_dataset_bill.R** - Already exists, enhance

---

## General Script Structure (Template)

```r
#!/usr/bin/env Rscript
#
# verify_<stage>_bill.R
#
# Purpose: Verify [specific stage] data integrity and completeness
# Author: Pipeline verification framework
# Date: 2025-11-07
#

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(arrow)
})

# ==============================================================================
# CONFIGURATION
# ==============================================================================

INPUT_FILES <- c(
  "path/to/input1.csv",
  "path/to/input2.parquet"
)

EXPECTED_COUNTS <- list(
  rows = 11711,
  cols = 736
)

TOLERANCE <- 0.01  # 1% tolerance for numeric comparisons

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_pass <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", message))
    return(FALSE)
  }
}

check_critical <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ CRITICAL FAIL: %s\n", message))
    cat("\nVerification FAILED. Exiting.\n")
    quit(status = 1)
  }
}

# ==============================================================================
# VERIFICATION CHECKS
# ==============================================================================

cat("========================================================================\n")
cat("VERIFICATION: [Stage Name]\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
cat("[1/N] Checking file existence...\n")
for (f in INPUT_FILES) {
  exists <- file.exists(f)
  all_checks_pass <- check_pass(exists, sprintf("File exists: %s", basename(f))) && all_checks_pass
}

# CHECK 2: Dimensions
cat("\n[2/N] Checking dimensions...\n")
# ... dimension checks

# CHECK 3: Data integrity
cat("\n[3/N] Checking data integrity...\n")
# ... integrity checks

# CHECK 4: Value validity
cat("\n[4/N] Checking value validity...\n")
# ... validity checks

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n")
  quit(status = 1)
}
```

---

## Integration with Existing Scripts

### Scripts to Modify:
1. **verify_stage1_integrity_bill.R** → Enhance to become `verify_master_shortlist_bill.R`
2. **verify_env_integrity_bill.R** → Enhance to become `verify_env_aggregation_bill.R`
3. **verify_complete_imputation_bill.R** → Enhance to become `verify_complete_dataset_bill.R`

### Scripts to Create (New):
- verify_wfo_matching_bill.R
- verify_enriched_parquets_bill.R
- verify_gbif_integration_bill.R
- verify_phylo_eigenvectors_bill.R
- verify_canonical_assembly_bill.R (most critical)
- verify_mixgb_cv_bill.R
- verify_production_imputation_bill.R
- verify_stage2_features_bill.R
- verify_stage2_training_bill.R
- verify_eive_imputation_bill.R

**Total new scripts: 10**
**Total enhanced scripts: 3**
**Total verification framework: 13 scripts**

---

## Success Criteria

Each verification script should:
1. ✓ Run autonomously (no user input required)
2. ✓ Exit with code 0 (pass) or 1 (fail)
3. ✓ Provide clear ✓/✗ output for each check
4. ✓ Fail fast on critical errors (anti-leakage, completeness)
5. ✓ Generate summary report at end
6. ✓ Include expected values and tolerances
7. ✓ Check data integrity, not just existence

---

**Next Steps**:
1. Review this plan with user
2. Implement high-priority scripts first (canonical assembly, production imputation, Stage 2 features, EIVE imputation)
3. Test each script on Bill's actual outputs
4. Integrate into condensed documentation
