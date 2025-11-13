# Data Preparation Verification (Bill Shipley)

**Purpose**: Independent R-based verification of Stage 1 data preparation pipeline
**Date**: 2025-11-07
**Environment**: Pure R, no Python/SQL required

---
## Scripts Overview

All scripts located in: `src/Stage_1/bill_verification/`

### Phase 0: WFO Normalization (13 scripts)
**Extraction (4):**
- `extract_all_names_bill.R` - Extract names from 8 datasets
- `extract_gbif_names_bill.R` - GBIF occurrence names
- `extract_globi_names_bill.R` - GloBI interaction names
- `extract_try_traits_names_bill.R` - TRY traits names

**Matching (8):**
- `worldflora_{duke,eive,mabberly,tryenhanced,austraits,gbif,globi,try_traits}_match_bill.R`

**Verification (1):**
- `verify_wfo_matching_bill.R` - Row counts, no duplicates, match rates

### Phase 1: Core Integration (6 scripts)
- `build_bill_enriched_parquets.R` - Merge WFO with original data
- `verify_enriched_parquets_bill.R` - WFO merge integrity (6 parquets)
- `verify_stage1_integrity_bill.R` - Reconstruct master union and shortlist
- `verify_master_shortlist_bill.R` - Master union (86,592), shortlist (24,511)
- `add_gbif_counts_bill.R` - Add GBIF counts
- `verify_gbif_integration_bill.R` - Verify ≥30 occurrences filter (11,711)

### Phase 2: Environmental Aggregation (3 scripts)
- `aggregate_env_summaries_bill.R` - Per-species mean/stddev/min/max
- `aggregate_env_quantiles_bill.R` - Per-species q05/q50/q95/IQR
- `verify_env_aggregation_bill.R` - Verify quantile ordering, completeness

### Phase 3: Imputation Dataset (5 scripts)
- `build_phylogeny_bill.R` - Build phylogenetic tree using V.PhyloMaker2 (optional, pre-generated)
- `extract_phylo_eigenvectors_bill.R` - Extract 92 eigenvectors (broken stick)
- `verify_phylo_eigenvectors_bill.R` - Verify tree (11,010 tips), 92 EVs, 99.7% coverage
- `assemble_canonical_imputation_input_bill.R` - Assemble 736-column dataset
- `verify_canonical_assembly_bill.R` - **CRITICAL**: Anti-leakage, dimensions, coverage

**Total: 27 scripts** (14 for processing, 13 for verification)

---

## Workflow Overview

**Phase 0**: Extract names → WorldFlora matching → Verify outputs
**Phase 1**: Build enriched parquets → Verify integrity → Add GBIF counts
**Phase 2**: Aggregate environmental data → Verify aggregations
**Phase 3**: Extract phylogeny eigenvectors → Assemble final dataset

**Note**: GBOTB→WFO mapping (item #13) verified Nov 8, 2025 - 100% data-identical to regenerated version

---

## Required Source Data (Read-Only)

Bill's scripts read from these **15 canonical files**. All outputs write to `shipley_checks/`.

### 8 Dataset Parquets
1. `data/stage1/duke_original.parquet` (58K rows)
2. `data/stage1/eive_original.parquet` (21K rows)
3. `data/stage1/mabberly_original.parquet` (13K rows)
4. `data/stage1/tryenhanced_species_original.parquet` (46K rows)
5. `data/stage1/austraits/taxa.parquet` (33K rows)
6. `data/gbif/occurrence_plantae.parquet` (161K rows, 5.4 GB)
7. `data/stage1/globi_interactions_plants.parquet` (4.6M rows)
8. `data/stage1/try_selected_traits.parquet` (81K rows)

### 3 Environmental Samples
9. `data/stage1/worldclim_occ_samples.parquet` (31.5M rows, 63 variables)
10. `data/stage1/soilgrids_occ_samples.parquet` (31.5M rows, 42 variables)
11. `data/stage1/agroclime_occ_samples.parquet` (31.5M rows, 51 variables)

### 1 WFO Taxonomy
12. `data/classification.csv` (1.6M taxa, tab-separated, Latin-1)

### 1 GBIF WFO-Enriched (Optional)
13. `data/gbif/occurrence_plantae_wfo.parquet` (49.7M rows)

### 2 Phylogenetic Data (Pre-Generated)
14. `shipley_checks/data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet` (74,529 GBOTB species → WFO IDs)
15. `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk` (11,010 tips) + `mixgb_wfo_to_tree_mapping_11711.csv`

---

## Phase 0: WFO Normalization

### Step 1: Extract Names

```bash
# Extract distinct names from all datasets (~1-2 minutes)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/extract_all_names_bill.R
```

**Output**: 8 name CSVs in `shipley_checks/wfo_verification/`
- `duke_names_for_r.csv` (14,027 names)
- `eive_names_for_r.csv` (14,835 names)
- `mabberly_names_for_r.csv` (13,489 names)
- `tryenhanced_names_for_r.csv` (46,047 names)
- `austraits_names_for_r.csv` (33,370 names)
- `gbif_occurrence_names_for_r.tsv` (160,713 names)
- `globi_interactions_names_for_r.tsv` (74,002 names)
- `try_selected_traits_names_for_r.csv` (80,788 names)

### Step 2: Run WorldFlora Matching

```bash
# Run 8 WorldFlora scripts 
# Tip: Run in parallel using nohup

R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_duke_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_eive_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_mabberly_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_tryenhanced_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_austraits_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_gbif_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_globi_match_bill.R
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/worldflora_try_traits_match_bill.R
```

**Note**: "Checking for fuzzy matches" message is misleading. With `Fuzzy=0`, NO string-distance fuzzy matching occurs. The message refers to fallback exact matching at higher taxonomic levels (subspecies → species → genus).

### Step 3: Verify WorldFlora Outputs

```bash
# Verify internal consistency (~5 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_wfo_matching_bill.R
```

**Expected internal verification checks**:
```
✓ Row counts match expected (Mabberly: 13,489 | Duke: 14,027 | EIVE: 14,835...)
✓ No duplicate WFO IDs per dataset
✓ All genus/species fields populated (no blank taxonomy)
✓ Match rates within expected range:
  - Duke: ~84% (ethnobotany, older names)
  - EIVE: ~95% (European flora, well-curated)
  - Mabberly: ~99% (genera-level, comprehensive)
✓ All 8 datasets produce valid WFO CSVs
```

---

## Phase 1: Data Integrity Check

### Step 1: Build Enriched Parquets

```bash
# Merge WorldFlora CSVs with original parquets (~60 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/build_bill_enriched_parquets.R
```

**Output**: 6 enriched parquets in `shipley_checks/wfo_verification/`:
- `duke_worldflora_enriched.parquet` (14,030 rows)
- `eive_worldflora_enriched.parquet` (14,835 rows)
- `mabberly_worldflora_enriched.parquet` (13,489 rows)
- `tryenhanced_worldflora_enriched.parquet` (46,047 rows)
- `austraits_traits_worldflora_enriched.parquet` (1,798,215 rows)
- `try_selected_traits_worldflora_enriched.parquet` (618,932 rows)

### Step 2: Verify Data Integrity

```bash
# Reconstruct master union and shortlist, verify integrity (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_stage1_integrity_bill.R
```

**Expected internal verification checks**:
```
[1] Master Taxa Union:
    ✓ Unique WFO taxa: 86,592 (EXPECTED)
    ✓ No duplicate WFO IDs
    ✓ Source coverage verified:
      - Duke: 10,640 | EIVE: 12,868 | Mabberly: 12,664
      - TRY Enhanced: 44,266 | AusTraits: 28,072

[2] Shortlist Candidates:
    ✓ Shortlisted species: 24,511 (EXPECTED)
    ✓ Trait-richness filters verified:
      - EIVE ≥3 indices: 12,599
      - TRY ≥3 traits: 12,655
      - AusTraits ≥3 traits: 3,849
    ✓ Deduplication logic: rank-based tie-breaking confirmed

[3] Column Schemas:
    ✓ All expected columns present
    ✓ WFO IDs match between datasets
    ✓ Source flags correctly populated
```

### Step 3: Add GBIF Occurrence Counts

```bash
# Add GBIF counts using Arrow streaming (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/add_gbif_counts_bill.R
```

**Expected internal verification checks**:
```
[1] GBIF Counting:
    ✓ Unique WFO taxa with GBIF: 144,655
    ✓ Total occurrences: 48,977,163
    ✓ Total georeferenced: 48,886,200

[2] Merge with Shortlist:
    ✓ Species with GBIF records: 18,451
    ✓ No NA in gbif_occurrence_count (merge successful)

[3] Filter to ≥30 Occurrences:
    ✓ Final species count: 11,711 (EXPECTED)
    ✓ All species have ≥30 occurrences (filter verified)
```

**Output**: `shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet` (11,711 species)

**Critical**: This shortlist is the input for Phase 3 tree building and all subsequent analyses

---

## Phase 2: Environmental Data Verification

### Step 1: Aggregate Summary Statistics

```bash
# Compute per-species mean, stddev, min, max (~5-10 min per dataset)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/aggregate_env_summaries_bill.R all
```

**Output**: 3 summary parquets in `shipley_checks/`:
- `worldclim_species_summary_R.parquet` (11,711 species, 63 vars)
- `soilgrids_species_summary_R.parquet` (11,711 species, 42 vars)
- `agroclime_species_summary_R.parquet` (11,711 species, 51 vars)

### Step 2: Aggregate Quantile Statistics

```bash
# Compute per-species q05, q50, q95, IQR (~10-15 min per dataset)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/aggregate_env_quantiles_bill.R all
```

**Output**: 3 quantile parquets in `shipley_checks/`:
- `worldclim_species_quantiles_R.parquet` (11,711 species)
- `soilgrids_species_quantiles_R.parquet` (11,711 species)
- `agroclime_species_quantiles_R.parquet` (11,711 species)

**Note**: Uses `quantile(..., type=1)` to match DuckDB's quantile method (inverted empirical CDF).

### Step 3: Verify Environmental Integrity

```bash
# Verify aggregation validity (~30 seconds)
R_LIBS_USER=.Rlib /usr/bin/Rscript src/Stage_1/bill_verification/verify_env_aggregation_bill.R
```

**Expected internal verification checks**:
```
[1] Row Coverage:
    ✓ All datasets: 11,711 species (100% coverage)
    ✓ WFO IDs match shortlist

[2] Variable Counts:
    ✓ WorldClim: 63 variables
    ✓ SoilGrids: 42 variables
    ✓ Agroclim: 51 variables

[3] Summary Statistics:
    ✓ No NA in mean/q50 (mandatory aggregations)
    ✓ Value ranges sensible (e.g., temperature -50 to 50°C)
    ✓ stddev non-negative (validity check)

[4] Quantile Statistics:
    ✓ IQR non-negative (validity check)
    ✓ Quantile ordering: q05 < q50 < q95 for all species/variables
```

---

## Phase 3: Canonical Imputation Dataset

**Prerequisites**:
- **Phase 1 must be complete**: Shortlist with ≥30 GBIF occurrences (`stage1_shortlist_with_gbif_ge30_R.parquet`, 11,711 species)
- Phylogenetic tree for 11,711 species (pre-generated, or rebuild using Steps 0a-0b below)

### Step 0: Build Phylogenetic Tree (Optional - Pre-Generated)

**Dependency**: Requires shortlist output from Phase 1 Step 3 (`add_gbif_counts_bill.R`)

**Note**: The phylogenetic tree is pre-generated and available at `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk`. You may skip Steps 0a and 0b unless you need to regenerate the tree.

#### Step 0a: Prepare Species List with Family

V.PhyloMaker2 requires a species CSV with family taxonomy. Create from Bill's verified shortlist:

```bash
# Create species list with family column (~30 seconds)
cat > /tmp/create_species_list_bill.R << 'EOF'
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(data.table)
})

# Load Bill's verified shortlist
shortlist <- read_parquet("shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet")
species <- shortlist %>%
  select(wfo_taxon_id, wfo_scientific_name, genus) %>%
  distinct() %>%
  arrange(wfo_taxon_id)

# Join with WFO for family
wfo <- fread("data/classification.csv",
             sep = "\t",
             encoding = "Latin-1",
             select = c("taxonID", "family"),
             data.table = FALSE)

result <- species %>%
  left_join(wfo %>% select(taxonID, family),
            by = c("wfo_taxon_id" = "taxonID")) %>%
  select(wfo_taxon_id, wfo_scientific_name, family, genus)

# Save to Bill's directory
dir.create("shipley_checks/phylogeny", showWarnings = FALSE, recursive = TRUE)
write_csv(result, "shipley_checks/phylogeny/species_list_11711_bill.csv")
cat("Species list created:", nrow(result), "species\n")
cat("Missing family:", sum(is.na(result$family)), "\n")
EOF

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript /tmp/create_species_list_bill.R
```

**Output**: `shipley_checks/phylogeny/species_list_11711_bill.csv` (11,711 species with family)

**Note**: This creates Bill's own species CSV from his independently verified shortlist parquet. The canonical CSV at `data/stage1/phlogeny/mixgb_shortlist_species_11711_20251107.csv` already exists and was used to build the pre-generated tree, but Bill can create his own for full reproducibility.

#### Step 0b: Build Phylogenetic Tree

```bash
# Build tree with proper infraspecific handling (~10-15 minutes)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/build_phylogeny_bill.R \
    --species_csv=shipley_checks/phylogeny/species_list_11711_bill.csv \
    --gbotb_wfo_mapping=shipley_checks/data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet \
    --output_newick=shipley_checks/phylogeny/tree_11711_bill.nwk \
    --output_mapping=shipley_checks/phylogeny/tree_mapping_11711_bill.csv
```

**Note**: This would create Bill's own tree from his verified species list. However, since the canonical tree at `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk` is already built and used throughout the pipeline, Bill can reference it directly as a canonical input (similar to the WFO classification file).

**Methodology**:
1. Load species list (11,711 species)
2. Collapse infraspecific taxa to parent binomials (11,043 unique parents)
3. Build phylogenetic tree using V.PhyloMaker2 scenario S3
4. Create WFO→tree mapping (infraspecific taxa inherit parent's tree tip)

**Expected output**:
```
Input species: 11,711
  Species-level: 10,887
  Infraspecific: 824
  Unique parent binomials: 11,043

Tree built: 11,010 tips
  Species mapped: 11,673 (99.7%)
  Failed to place: 38 species (0.3%)

Outputs:
  ✓ Newick tree: data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk (559.7 KB)
  ✓ WFO→tree mapping: data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv (1.3 MB)
```

**Coverage**: 11,673 / 11,711 species mapped to tree (99.7%)

### Step 1: Extract Phylogenetic Eigenvectors

**Recommendation**: Use the pre-generated canonical tree as input (read-only canonical source), similar to how Bill uses the WFO classification file.

```bash
# Extract 92 eigenvectors using broken stick rule (~10-20 minutes)
# Uses canonical tree at data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/extract_phylo_eigenvectors_bill.R
```

**Expected output**:
```
[1/7] Loading tree: 11,010 tips
[2/7] Loading WFO mapping: 11,711 species
[3/7] Building VCV matrix: 11,010 × 11,010
[4/7] Eigendecomposition: 11,010 eigenvalues
[5/7] Broken stick rule: 92 eigenvectors selected (89.8% variance)
[6/7] Mapping to species: 11,673 / 11,711 (99.7%)
[7/7] Output: phylo_eigenvectors_11711_bill.csv (11.2 MB)
```

**Coverage**: 11,673 species with eigenvectors (99.7%), 38 unmapped (primarily *Rumex* spp.)

### Step 2: Assemble Canonical Imputation Input

```bash
# Assemble 736-column dataset (~2 minutes)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/assemble_canonical_imputation_input_bill.R
```

**What it does**:
1. Load base shortlist (11,711 species)
2. Extract environmental quantile features (624 columns: 156 vars × 4 stats = q05, q50, q95, iqr)
3. Extract TRY Enhanced traits (6 raw, convert to numeric, species-level median)
4. Extract AusTraits for SLA fallback
5. Compute canonical SLA waterfall + log transforms
6. **Anti-leakage**: Drop ALL raw traits (only keep log-transformed versions)
7. Extract categorical traits (7 total: 4 from TRY Enhanced + 3 from TRY Selected)
8. Extract EIVE indicators (5 columns)
9. Load phylogenetic eigenvectors (92 columns)
10. Merge all components and verify structure

**Expected internal verification checks**:
```
[1] Dimensions:
    ✓ 11,711 species × 736 columns (EXPECTED)

[2] Column Breakdown:
    ✓ IDs: 2 (wfo_taxon_id, wfo_scientific_name)
    ✓ Log traits: 6 (logLA, logNmass, logLDMC, logSLA, logH, logSM)
    ✓ Categorical: 7 (woodiness, growth_form, habitat, leaf_type, phenology, photosynthesis, mycorrhiza)
    ✓ EIVE: 5 (EIVEres-L/T/M/N/R)
    ✓ Phylo eigenvectors: 92 (phylo_ev1...phylo_ev92)
    ✓ Environmental features: 624 (156 vars × 4 stats)
      - q05: 156, q50: 156, q95: 156, iqr: 156

[3] Anti-Leakage Verification:
    ✓ NO raw trait columns present (leaf_area_mm2, nmass_mg_g, ldmc_g_g, sla_mm2_mg, plant_height_m, seed_mass_mg)
    ✓ NO LMA columns present (try_lma_g_m2, aust_lma_g_m2)

[4] Trait Coverage (BEFORE imputation):
    ✓ logLA: 44.6% (5,226 species)
    ✓ logNmass: 34.2% (4,005 species)
    ✓ logLDMC: 21.9% (2,567 species)
    ✓ logSLA: 47.3% (5,535 species)
    ✓ logH: 77.1% (9,029 species)
    ✓ logSM: 65.8% (7,700 species)

[5] Categorical Trait Coverage:
    ✓ try_woodiness: 78.8% (9,224 species)
    ✓ try_growth_form: 77.6% (9,087 species)
    ✓ try_habitat_adaptation: 75.0% (8,781 species)
    ✓ try_leaf_type: 76.8% (8,998 species)
    ✓ try_leaf_phenology: 49.6% (5,810 species) ← Fixed from 0%
    ✓ try_photosynthesis_pathway: 70.7% (8,277 species) ← Fixed from 0%
    ✓ try_mycorrhiza_type: 23.8% (2,783 species) ← Fixed from 0%

[6] EIVE Coverage:
    ✓ EIVEres-L: 52.9% (6,190 species)
    ✓ EIVEres-T: 53.3% (6,238 species)
    ✓ EIVEres-M: 53.5% (6,261 species)
    ✓ EIVEres-N: 51.5% (6,027 species)
    ✓ EIVEres-R: 51.9% (6,082 species)

[7] Phylogenetic Coverage:
    ✓ 99.7% species have eigenvectors (11,673 / 11,711)

[8] Environmental Coverage:
    ✓ 100% coverage for all q50 features (156 vars)
    ✓ 100% coverage for all quantiles (468 vars: q05/q95/iqr)
```

**Output**: `shipley_checks/modelling/canonical_imputation_input_11711_bill.csv` (11,711 × 736, ~46 MB)

**Critical fix applied**: TraitID 37, 22, 7 extraction changed from `StdValue` (numeric, all NA) to `OrigValueStr` (text values), restoring 3 categorical traits from 0% coverage.

### Step 3: Verify Canonical Assembly (CRITICAL)

```bash
# Verify anti-leakage, dimensions, coverage (~30 seconds)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/bill_verification/verify_canonical_assembly_bill.R
```

**Expected output**:
```
✓ VERIFICATION PASSED
✓ 11,711 × 736 dimensions
✓ CRITICAL: Anti-leakage check passed - no raw trait columns present
✓ All feature groups present and within expected coverage
✓ 3 fixed categorical traits confirmed (from 0% to 24-70%)
```

---

## Success Criteria

### Phase 0: WFO Normalization
- [ ] All 8 WorldFlora scripts run without errors
- [ ] verify_worldflora_checksums_bill.R: All row counts match expected
- [ ] No duplicate WFO IDs per dataset
- [ ] Match rates within expected range (Duke ~84%, EIVE ~95%, Mabberly ~99%)

### Phase 1: Data Integrity
- [ ] verify_stage1_integrity_bill.R passes all checks:
  - [ ] Master union: 86,592 unique WFO taxa
  - [ ] Shortlist: 24,511 species
  - [ ] Trait counts: EIVE ≥3: 12,599 | TRY ≥3: 12,655 | AusTraits ≥3: 3,849
- [ ] add_gbif_counts_bill.R: 11,711 species with ≥30 occurrences
- [ ] No NA in critical columns (wfo_taxon_id, source flags, gbif counts)

### Phase 2: Environmental Data
- [ ] All aggregations complete for 11,711 species
- [ ] verify_env_integrity_bill.R passes all checks:
  - [ ] Variable counts: WorldClim 63 | SoilGrids 42 | Agroclim 51
  - [ ] No NA in mean/q50 aggregations
  - [ ] Quantile ordering: q05 < q50 < q95 for all species/variables
  - [ ] No negative stddev/IQR values

### Phase 3: Imputation Dataset
- [ ] (Optional) build_phylogeny_bill.R: Tree with 11,010 tips, 99.7% coverage (pre-generated, can skip)
- [ ] Phylogenetic eigenvectors: 92 selected, 99.7% coverage
- [ ] assemble_canonical_imputation_input_bill.R passes all checks:
  - [ ] Dimensions: 11,711 × 736 columns
  - [ ] Anti-leakage verified (no raw traits)
  - [ ] Categorical traits properly extracted (3 fixed from 0%)
  - [ ] Log trait coverage: 22-77% (before imputation)
  - [ ] EIVE coverage: 51-54%
  - [ ] Environmental: 100% coverage

### Bill's Independent Assessment
- [ ] Code logic review: Deduplication, trait filters, SLA waterfall logic sound
- [ ] Ecological sanity: Value ranges plausible, taxonomic distributions reasonable
- [ ] Report findings: Any data quality issues or methodological concerns

**If all checks pass**: Stage 1 data preparation independently verified ✓

---

## System Requirements

```r
# Required R packages (install once)
install.packages(c("arrow", "dplyr", "data.table", "WorldFlora", "ape", "V.PhyloMaker2"))
```

**R environment**: Use `.Rlib` custom library via `R_LIBS_USER=.Rlib`
**R executable**: System R at `/usr/bin/Rscript`
**WFO backbone**: `data/classification.csv` (tab-separated, Latin-1 encoding)
**Phylogeny package**: V.PhyloMaker2 (contains GBOTB.extended megatree backbone)
