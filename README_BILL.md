# Bill Shipley Verification Pipeline - Windows Setup Guide

**Purpose**: This guide helps you verify the complete data pipeline from raw inputs through final CSR calculations on your Windows computer.

**Estimated Time**: Setup (10 minutes) + Pipeline runtime (8 hours overnight)

---

## What You'll Need

1. **Foundational Data** (you already have this)
   - File: `bill_foundational_data.zip` (20 GB)
   - Contains all raw input datasets

2. **This Repository** (clone from GitHub)
   - Contains all verification scripts
   - Contains pre-computed XGBoost results (included)

3. **R Software** (already installed on your computer)
   - You're using R for your analyses

4. **Reference Dataset** (you already have this)
   - File: `bill_with_csr_ecoservices_11711.csv`
   - You'll compare your reproduced results against this

---

## Step 1: Clone This Repository

### Using Command Line (Simple!)

Open Command Prompt (press **Windows Key + R**, type `cmd`, press Enter) and paste this command:

```cmd
cd C:\Users\shij1401\OneDrive - USherbrooke
git clone -b shipley-review --single-branch <REPOSITORY_URL> shipley_checks
```

This creates:
```
C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks\
```

**That's it!** You've cloned just the verification branch into a simple `shipley_checks\` folder.

---

## Step 2: Extract Foundational Data

You have a file called `bill_foundational_data.zip` (20 GB).

### Using Windows Explorer:

1. **Right-click** on `bill_foundational_data.zip`
2. Choose "Extract All..."
3. **IMPORTANT**: Extract to this exact location:
   ```
   C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks\input
   ```

4. After extraction, you should see these files in `input\`:
   - `classification.csv`
   - `duke_original.parquet`
   - `eive_original.parquet`
   - `mabberly_original.parquet`
   - `tryenhanced_species_original.parquet`
   - `austraits_taxa.parquet`
   - `try_selected_traits.parquet`
   - `gbif_occurrence_plantae.parquet`
   - `globi_interactions_plants.parquet`
   - `worldclim_occ_samples.parquet`
   - `soilgrids_occ_samples.parquet`
   - `agroclime_occ_samples.parquet`
   - `mixgb_tree_11711_species_20251107.nwk`
   - `mixgb_wfo_to_tree_mapping_11711.csv`

**Total: 14 files** should be in the `input\` folder.

---

## Step 3: Run Setup Script

This extracts the pre-computed XGBoost results (Stage 1-2) that you cannot run yourself.

### Open Command Prompt:

1. Press **Windows Key + R**
2. Type `cmd` and press Enter
3. Copy and paste this command:

```cmd
cd C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks
Rscript setup_bill.R
```

### What this does:

- Extracts `bill_intermediate_data.zip` (64 MB)
- Creates `intermediate\` folder with 7 files
- Creates `output\` folder for your results
- Checks if you have all required files
- Verifies R packages are installed

### Expected Output:

```
========================================================================
BILL SHIPLEY VERIFICATION SETUP
========================================================================

Detected repository root:  C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks
...
Step 1: Extracting intermediate data...
  ✓ Extracted 7 intermediate files

Step 2: Creating directory structure...
  Created: ...input
  Created: ...output
  ...

Step 3: Checking prerequisites...
  [INPUT DATA]
    ✓ duke_original.parquet
    ✓ eive_original.parquet
    ... (all 14 files)

  [R PACKAGES]
    ✓ arrow
    ✓ data.table
    ✓ dplyr
    ✓ readr
    ✓ WorldFlora
    ✓ ape
    ✓ phangorn

========================================================================
SETUP COMPLETE
========================================================================
```

**If you see missing R packages**, install them:

```r
install.packages(c("arrow", "data.table", "dplyr", "readr", "WorldFlora", "ape", "phangorn"))
```

---

## Step 4: Run the Complete Verification Pipeline

**IMPORTANT**: This will take approximately **8 hours** to complete. Run it overnight or when you can leave your computer on.

### In the same Command Prompt window:

```cmd
Rscript run_all_bill.R
```

### What will happen:

The script will run through all phases:

1. **Phase 0: WFO Normalization** (~2 hours)
   - Extracts plant names from 8 datasets
   - Matches to World Flora Online taxonomy

2. **Phase 1: Core Integration** (~1.5 hours)
   - Builds enriched datasets with WFO IDs
   - Filters to species with ≥3 traits
   - Adds GBIF occurrence counts
   - Filters to species with ≥30 occurrences → 11,711 species

3. **Phase 2: Environmental Aggregation** (~4 hours)
   - Aggregates climate data (WorldClim)
   - Aggregates soil data (SoilGrids)
   - Aggregates agricultural climate data
   - Calculates quantiles for all environmental variables

4. **Phase 3: Imputation Dataset Assembly** (~30 minutes)
   - Extracts phylogenetic eigenvectors from pre-computed tree
   - Assembles complete feature matrix (11,711 × 736)

5. **Stage 1-2: SKIPPED** (Using pre-computed XGBoost results)
   - These stages require Python and XGBoost compilation
   - Results already provided in `intermediate\` folder

6. **Stage 3: CSR + Ecosystem Services** (~10 seconds)
   - Calculates CSR strategy percentages
   - Calculates 10 ecosystem service ratings
   - **Produces final output!**

### Progress Tracking:

You'll see output like:

```
========================================================================
BILL SHIPLEY VERIFICATION PIPELINE
Cross-Platform Edition - Phases 0-3 + Stage 3
========================================================================

Detected paths:
  Repo root:     C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks
  Input:         ...shipley_checks/input
  Intermediate:  ...shipley_checks/intermediate
  Output:        ...shipley_checks/output
  Scripts:       ...shipley_checks/src

========================================================================
PHASE 0: WFO NORMALIZATION (Taxonomic Standardization)
========================================================================
...

[PHASE 0.1] Running extract_all_names_bill.R...
[PHASE 0.1] ✓ PASSED (3.8 seconds)

[PHASE 0.2] Running worldflora_duke_match_bill.R...
[PHASE 0.2] ✓ PASSED (45.2 seconds)
...
```

**Let it run to completion!** You can minimize the window but don't close it.

---

## Step 5: Find Your Results

When the pipeline completes, you'll see:

```
========================================================================
✓ VERIFICATION PIPELINE COMPLETE
========================================================================

Final output location:
  C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks/output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv

Compare with reference dataset:
  C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks/bill_with_csr_ecoservices_11711.csv
```

### Your Results File:

**Location (using Windows Explorer)**:

1. Open File Explorer
2. Navigate to: `OneDrive - USherbrooke\shipley_checks\output\stage3\`
3. Look for: `bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv`

This file contains:
- **11,711 species** (rows)
- **782 columns** including:
  - Plant functional traits (6 traits, 100% complete)
  - European Indicator Values (5 axes, 100% complete)
  - CSR strategy percentages (C, S, R - sum to 100%)
  - 10 ecosystem service ratings
  - Taxonomy (family, genus)
  - Nitrogen fixation ratings

---

## Step 6: Compare with Reference Dataset

### Load both datasets in R:

```r
library(readr)

# Your reproduced dataset
bill_verified <- read_csv("C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks/output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")

# Reference dataset (provided by Jared)
reference <- read_csv("C:/Users/shij1401/OneDrive - USherbrooke/shipley_checks/bill_with_csr_ecoservices_11711.csv")

# Check dimensions
dim(bill_verified)  # Should be: 11711 × 782
dim(reference)      # Should be: 11711 × 782

# Compare CSR values (should be identical)
library(dplyr)
library(waldo)

# Compare CSR columns
compare(
  bill_verified %>% select(wfo_taxon_id, C, S, R) %>% arrange(wfo_taxon_id),
  reference %>% select(wfo_taxon_id, C, S, R) %>% arrange(wfo_taxon_id),
  tolerance = 1e-6
)

# Compare ecosystem services
compare(
  bill_verified %>% select(starts_with("ecoserv_")) %>% arrange(wfo_taxon_id),
  reference %>% select(starts_with("ecoserv_")) %>% arrange(wfo_taxon_id),
  tolerance = 1e-6
)
```

### Expected Result:

If the pipeline worked correctly, you should see:
```
✓ No differences
```

Any numerical differences should be **< 0.000001** (one millionth).

---

## Troubleshooting

### Problem: "File not found" errors

**Solution**: Make sure you extracted `bill_foundational_data.zip` to the correct location:
```
C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks\input\
```

Use Windows Explorer to verify all 14 files are there.

---

### Problem: "Package not installed" errors

**Solution**: Install missing R packages:

```r
install.packages(c("arrow", "data.table", "dplyr", "readr", "WorldFlora", "ape", "phangorn"))
```

---

### Problem: Pipeline stops/crashes

**Common causes**:
1. Computer went to sleep (disable sleep mode for long runs)
2. Out of memory (close other programs)
3. Disk space (need ~10 GB free space for intermediate files)

**Solution**: Restart from where it stopped:
```cmd
cd C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks
Rscript run_all_bill.R
```

The pipeline will skip already-completed steps and continue from where it failed.

---

### Problem: WorldFlora matching is very slow

This is normal. The WorldFlora matching phase processes 8 datasets against 1.6 million taxonomic names. Each dataset takes 5-15 minutes.

**Total expected time for Phase 0**: ~2 hours

Be patient and let it run!

---

### Problem: Different results from reference dataset

**First, check**:
1. Did all phases complete successfully? (look for "✓ PASSED" for each step)
2. Did you skip running `setup_bill.R`? (This extracts the pre-computed intermediate data)
3. Are numerical differences very small (< 1e-6)? This is acceptable floating-point precision

**If differences are large**, contact Jared with:
- Your log file (if pipeline completed, there should be one)
- The specific differences you're seeing
- Which phase/step showed errors

---

## What Each File/Folder Does

```
shipley_checks\                   # This IS your cloned repository
├── input\                        # YOU extract foundational data here
│   ├── classification.csv        # WFO taxonomy backbone (904 MB)
│   ├── duke_original.parquet     # Duke trait database
│   ├── gbif_occurrence_plantae.parquet  # 5.4 GB occurrence data
│   └── ... (14 files total)
│
├── intermediate\                 # Auto-extracted by setup_bill.R
│   ├── bill_complete_with_eive_20251107.csv  # Pre-computed Stage 2
│   ├── duke_worldflora_enriched.parquet      # WFO-enriched data
│   └── ... (7 files total - these are XGBoost results you can't compute)
│
├── output\                       # Created by run_all_bill.R
│   ├── wfo_verification\         # Phase 0 outputs
│   ├── stage3\                   # Your final results HERE!
│   └── ...
│
├── src\                          # All R scripts (don't modify)
├── docs\                         # Documentation
├── setup_bill.R                  # RUN THIS FIRST
├── run_all_bill.R                # RUN THIS SECOND
└── bill_intermediate_data.zip    # Pre-computed XGBoost results
```

---

## Quick Reference Commands

### Setup (run once):
```cmd
cd C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks
Rscript setup_bill.R
```

### Run pipeline (takes 8 hours):
```cmd
Rscript run_all_bill.R
```

### Check results:
```r
library(readr)
results <- read_csv("output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")
dim(results)  # Should be: 11711 × 782
```

---

## Questions?

Contact Jared Olier with:
1. What step you're on
2. Any error messages you see
3. Screenshots of the problem (if helpful)

**Remember**: The pipeline takes ~8 hours total. This is normal! Run it overnight when you can leave your computer on.

---

## Final Checklist

Before running the pipeline, verify:

- [ ] Repository cloned to: `C:\Users\shij1401\OneDrive - USherbrooke\shipley_checks`
- [ ] Extracted `bill_foundational_data.zip` to `input\` folder inside shipley_checks
- [ ] All 14 input files present in `input\` folder
- [ ] Ran `Rscript setup_bill.R` successfully
- [ ] All 7 intermediate files extracted to `intermediate\` folder
- [ ] All required R packages installed
- [ ] Computer set to not sleep for 8+ hours
- [ ] At least 10 GB free disk space

**After pipeline completes**:

- [ ] Final file exists: `output\stage3\bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv`
- [ ] Compared with reference dataset
- [ ] Numerical differences < 1e-6
- [ ] Reported results to Jared

Good luck with your verification!
