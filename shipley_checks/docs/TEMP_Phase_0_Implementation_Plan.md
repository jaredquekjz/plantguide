# TEMPORARY: Phase 0 Implementation Plan

**Status:** In Progress
**Date:** 2025-11-16
**Context Window:** Running low - use this doc to resume work

---

## Current Pipeline Status (Background)

**Running Pipeline (PID 2493195):**
- ✅ Phase 1: Complete, verified (41,738 taxa, 59 languages)
- 🔄 Phase 2: Running Kimi API (~30 min, 5,409 genera)
- ⏳ Phase 3: Pending (Köppen climate zones)
- ⏳ Phase 4: Pending (Merge taxonomy + Köppen)

**Log:** `/tmp/taxonomy_pipeline_complete.log`

---

## Phase 0 Overview

### Purpose
Create **organism_taxonomy_enriched.parquet** from GloBI data - the foundation for Phase 1 vernacular labeling.

### Current Problem
- Phase 1 uses `data/taxonomy/organism_taxonomy_enriched.parquet` (29,167 organisms)
- This file created manually/ad-hoc, not part of automated pipeline
- Need Phase 0 to extract from GloBI and enrich taxonomy **BEFORE** Phase 1 runs

### Pipeline Order (CORRECTED)
```
Phase 0: GloBI Extraction → organism_taxonomy_enriched.parquet
Phase 1: Vernacular Names → uses organism taxonomy
Phase 2: Kimi AI Labels
Phase 3: Köppen Climate
Phase 4: Merge All
```

---

## Implementation Strategy

### Model: Dual Verification Pipeline
**Reference:** `/home/olier/ellenberg/shipley_checks/docs/Stage_4_Dual_Verification_Pipeline.md`

**Proven Method:**
1. Python DuckDB (baseline - already exists)
2. R DuckDB (NEW - faithful port from Python)
3. Checksum verification (achieve byte-for-byte parity)

**Success Example:**
- Fungal guilds: MD5 `7f1519ce931dab09451f62f90641b7d6` (Python = R)
- Organism profiles: TBD (this is Phase 0)

---

## File Structure

```
shipley_checks/src/Stage_4/taxonomy/phase0_globi/
├── 00_extract_all_organisms.R           # Extract unique organisms from GloBI
├── 01_enrich_taxonomy.R                 # Add kingdom/phylum/class/order/family
├── 02_aggregate_organism_profiles.R     # Create final organism_taxonomy_enriched
├── verify_phase0_output.py              # Checksum validation
├── run_phase0_pipeline.R                # Master script
└── README.md

Outputs (data/taxonomy/):
├── all_organisms.parquet                # Unique organisms with roles
├── taxonomy_cache.parquet               # NCBI taxonomy lookups (reusable)
└── organism_taxonomy_enriched.parquet   # FINAL (29,167 rows × 11 cols)
```

---

## Python Baseline Scripts (TO PORT)

### Location
`/home/olier/ellenberg/src/Stage_4/`

### Key Scripts
1. `01_extract_organism_profiles.py` - Extract from GloBI interactions
2. `02_build_multitrophic_network.py` - Build organism network
3. `/home/olier/ellenberg/src/Stage_1/taxonomy/build_taxonomy_enrichment.R` - Taxonomy

### Current organism_taxonomy_enriched.parquet Structure
```python
Columns (11):
- organism_name      # e.g., "Andrena cressonii cressonii"
- genus              # e.g., "Andrena"
- is_herbivore       # Boolean
- is_pollinator      # Boolean
- is_predator        # Boolean
- kingdom            # e.g., "Animalia"
- phylum             # e.g., "Arthropoda"
- class              # e.g., "Insecta"
- order              # e.g., "Hymenoptera"
- family             # e.g., "Andrenidae"
- common_names       # Nullable

Rows: 29,167 organisms
Size: 675 KB
```

---

## Script 1: `00_extract_all_organisms.R`

### Purpose
Extract unique organisms from GloBI interactions with ecological roles.

### Python Baseline (to replicate)
```python
# From 01_extract_organism_profiles.py lines 54-180
# Extracts pollinators, herbivores, pathogens, flower visitors, predators

con = duckdb.connect()

# Example: Pollinators
pollinators = con.execute("""
    SELECT DISTINCT sourceTaxonName as organism_name
    FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
    WHERE interactionTypeName = 'pollinates'
      AND sourceTaxonName != 'no name'
""").fetchdf()
```

### R DuckDB Port (FAITHFUL)
```r
#!/usr/bin/env Rscript
library(duckdb)
library(arrow)

con <- dbConnect(duckdb::duckdb())

# EXACTLY replicate Python logic
pollinators <- dbGetQuery(con, "
  SELECT DISTINCT sourceTaxonName as organism_name
  FROM read_parquet('data/stage4/globi_interactions_final_dataset_11711.parquet')
  WHERE interactionTypeName = 'pollinates'
    AND sourceTaxonName != 'no name'
")

# Extract genus from scientific name
pollinators$genus <- sapply(strsplit(pollinators$organism_name, " "), `[`, 1)
pollinators$is_pollinator <- TRUE
```

### CRITICAL: Update to 11,711 plants
- Python uses: `perm2_11680_with_koppen_tiers_20251103.parquet`
- R should use: `bill_with_csr_ecoservices_11711.csv`
- **Update all queries to use 11,711 plant dataset**

### Verification Target
```r
# Expected output structure
all_organisms.parquet:
  - organism_name (character)
  - genus (character, extracted from name)
  - is_herbivore (logical)
  - is_pollinator (logical)
  - is_predator (logical)

# Expected rows: ~30,000-35,000 unique organisms
# Checksum: TBD (compare with Python baseline)
```

---

## Script 2: `01_enrich_taxonomy.R`

### Purpose
Add taxonomic hierarchy (kingdom → family) via NCBI lookups.

### Python Baseline
```python
# From build_taxonomy_enrichment.R (currently in R, needs DuckDB port)
# Uses taxizedb::classification() for NCBI lookups
```

### R DuckDB Port Strategy

**Option A: Cache-first (RECOMMENDED)**
```r
library(duckdb)
library(taxizedb)
library(arrow)

con <- dbConnect(duckdb::duckdb())

# Load organisms
organisms <- read_parquet("data/taxonomy/all_organisms.parquet")

# Check cache first
if (file.exists("data/taxonomy/taxonomy_cache.parquet")) {
  dbExecute(con, "
    CREATE TABLE taxonomy_cache AS
    SELECT * FROM read_parquet('data/taxonomy/taxonomy_cache.parquet')
  ")
} else {
  dbExecute(con, "CREATE TABLE taxonomy_cache (
    organism_name VARCHAR,
    kingdom VARCHAR,
    phylum VARCHAR,
    class VARCHAR,
    \"order\" VARCHAR,
    family VARCHAR,
    PRIMARY KEY (organism_name)
  )")
}

# Get organisms not in cache
uncached <- dbGetQuery(con, "
  SELECT DISTINCT o.organism_name
  FROM organisms o
  LEFT JOIN taxonomy_cache t ON o.organism_name = t.organism_name
  WHERE t.organism_name IS NULL
")

# Lookup via NCBI (batch process)
for (i in seq_len(nrow(uncached))) {
  organism <- uncached$organism_name[i]

  tax_data <- tryCatch({
    result <- classification(organism, db = "ncbi")[[1]]
    if (is.data.frame(result) && nrow(result) > 0) {
      list(
        kingdom = result$name[result$rank == "kingdom"][1],
        phylum = result$name[result$rank == "phylum"][1],
        class = result$name[result$rank == "class"][1],
        order = result$name[result$rank == "order"][1],
        family = result$name[result$rank == "family"][1]
      )
    }
  }, error = function(e) NULL)

  if (!is.null(tax_data)) {
    dbExecute(con, sprintf("
      INSERT INTO taxonomy_cache VALUES ('%s', '%s', '%s', '%s', '%s', '%s')
    ", organism, tax_data$kingdom, tax_data$phylum, tax_data$class,
       tax_data$order, tax_data$family))
  }

  # Progress every 100
  if (i %% 100 == 0) {
    cat(sprintf("Progress: %d/%d (%.1f%%)\n", i, nrow(uncached), 100*i/nrow(uncached)))
  }
}

# Save updated cache
taxonomy_cache <- dbGetQuery(con, "SELECT * FROM taxonomy_cache")
write_parquet(taxonomy_cache, "data/taxonomy/taxonomy_cache.parquet")

# Join with organisms
enriched <- dbGetQuery(con, "
  SELECT
    o.organism_name,
    o.genus,
    o.is_herbivore,
    o.is_pollinator,
    o.is_predator,
    t.kingdom,
    t.phylum,
    t.class,
    t.\"order\",
    t.family,
    NULL as common_names
  FROM organisms o
  LEFT JOIN taxonomy_cache t ON o.organism_name = t.organism_name
")

write_parquet(enriched, "data/taxonomy/organism_taxonomy_enriched.parquet")
```

### Verification
```r
# Check kingdom distribution
table(enriched$kingdom)
# Expected:
#   Animalia: ~17,000-20,000
#   Fungi: ~18
#   Plantae: ~12
#   Other/NA: remainder

# Check completeness
sum(!is.na(enriched$kingdom)) / nrow(enriched)
# Target: >95% have kingdom assigned
```

---

## Script 3: `verify_phase0_output.py`

### Purpose
Verify R DuckDB output matches expected structure and quality.

### Checks
```python
#!/usr/bin/env python3
import duckdb
from pathlib import Path
import hashlib
import sys

PROJECT_ROOT = Path("/home/olier/ellenberg")
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/organism_taxonomy_enriched.parquet"

con = duckdb.connect()

print("=" * 80)
print("PHASE 0 VERIFICATION: ORGANISM TAXONOMY ENRICHMENT")
print("=" * 80)
print()

all_checks_passed = True

# Check 1: File exists
if not OUTPUT_FILE.exists():
    print("❌ FAILED: Output file not found")
    sys.exit(1)
print(f"✓ Output file found: {OUTPUT_FILE}")
print(f"  Size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB")
print()

# Check 2: Row count
df = con.execute(f"SELECT * FROM read_parquet('{OUTPUT_FILE}')").fetchdf()
print(f"CHECK 2: Row count")
print(f"  Expected: ~29,000-30,000")
print(f"  Actual: {len(df):,}")
if 25000 <= len(df) <= 35000:
    print("✓ PASSED")
else:
    print("❌ FAILED: Row count out of expected range")
    all_checks_passed = False
print()

# Check 3: Required columns
required_cols = [
    'organism_name', 'genus', 'is_herbivore', 'is_pollinator', 'is_predator',
    'kingdom', 'phylum', 'class', 'order', 'family', 'common_names'
]
missing = [col for col in required_cols if col not in df.columns]
if len(missing) == 0:
    print(f"✓ All {len(required_cols)} required columns present")
else:
    print(f"❌ FAILED: Missing columns: {missing}")
    all_checks_passed = False
print()

# Check 4: Ecological role distribution
print("CHECK 4: Ecological role distribution")
n_herbivores = df['is_herbivore'].sum()
n_pollinators = df['is_pollinator'].sum()
n_predators = df['is_predator'].sum()
print(f"  Herbivores: {n_herbivores:,} ({100*n_herbivores/len(df):.1f}%)")
print(f"  Pollinators: {n_pollinators:,} ({100*n_pollinators/len(df):.1f}%)")
print(f"  Predators: {n_predators:,} ({100*n_predators/len(df):.1f}%)")
print()

# Check 5: Kingdom distribution
print("CHECK 5: Kingdom distribution")
kingdoms = df['kingdom'].value_counts()
for kingdom, count in kingdoms.head(10).items():
    print(f"  {kingdom}: {count:,}")
animalia_pct = 100 * kingdoms.get('Animalia', 0) / len(df)
if animalia_pct > 80:
    print("✓ PASSED: Majority Animalia (>80%)")
else:
    print(f"⚠️  WARNING: Animalia only {animalia_pct:.1f}%")
print()

# Check 6: Taxonomy completeness
print("CHECK 6: Taxonomy completeness")
pct_kingdom = 100 * df['kingdom'].notna().sum() / len(df)
pct_family = 100 * df['family'].notna().sum() / len(df)
print(f"  Kingdom assigned: {pct_kingdom:.1f}%")
print(f"  Family assigned: {pct_family:.1f}%")
if pct_kingdom > 95:
    print("✓ PASSED: >95% have kingdom")
else:
    print(f"❌ FAILED: Only {pct_kingdom:.1f}% have kingdom")
    all_checks_passed = False
print()

# Check 7: No duplicate organisms
print("CHECK 7: Duplicate check")
duplicates = df['organism_name'].value_counts()
duplicates = duplicates[duplicates > 1]
if len(duplicates) == 0:
    print("✓ PASSED: No duplicate organisms")
else:
    print(f"⚠️  WARNING: {len(duplicates)} organisms appear multiple times (multi-role OK)")
    print(f"  Top duplicates:")
    for org, count in duplicates.head(5).items():
        print(f"    {org}: {count} times")
print()

if all_checks_passed:
    print("✓ ALL CHECKS PASSED")
    sys.exit(0)
else:
    print("❌ SOME CHECKS FAILED")
    sys.exit(1)
```

---

## Script 4: `run_phase0_pipeline.R`

### Master Pipeline
```r
#!/usr/bin/env Rscript

cat("================================================================================\n")
cat("PHASE 0: GLOBI EXTRACTION & TAXONOMY ENRICHMENT\n")
cat("================================================================================\n\n")

script_dir <- dirname(sys.frame(1)$ofile)

# Step 1: Extract organisms from GloBI
cat("Step 1/3: Extracting organisms from GloBI...\n")
source(file.path(script_dir, "00_extract_all_organisms.R"))

# Step 2: Enrich taxonomy via NCBI
cat("\nStep 2/3: Enriching taxonomy via NCBI...\n")
source(file.path(script_dir, "01_enrich_taxonomy.R"))

# Step 3: Verify output
cat("\nStep 3/3: Verifying output...\n")
result <- system2(
  "/home/olier/miniconda3/envs/AI/bin/python",
  args = file.path(script_dir, "verify_phase0_output.py"),
  stdout = TRUE,
  stderr = TRUE
)
cat(paste(result, collapse = "\n"))
cat("\n\n")

exit_code <- attr(result, "status")
if (!is.null(exit_code) && exit_code != 0) {
  cat("❌ PHASE 0 VERIFICATION FAILED\n")
  quit(status = 1)
}

cat("================================================================================\n")
cat("PHASE 0 COMPLETE\n")
cat("================================================================================\n")
cat("Output: data/taxonomy/organism_taxonomy_enriched.parquet\n\n")
```

---

## Implementation Workflow

### Step-by-Step Process

1. **Create directory structure**
   ```bash
   mkdir -p shipley_checks/src/Stage_4/taxonomy/phase0_globi
   ```

2. **Implement Script 1** (`00_extract_all_organisms.R`)
   - Port Python GloBI extraction FAITHFULLY
   - Update to 11,711 plants
   - Test: Check row count (~30K organisms)
   - **Commit when verified**

3. **Implement Script 2** (`01_enrich_taxonomy.R`)
   - Port taxonomy enrichment with DuckDB caching
   - Test: Check kingdom distribution (>80% Animalia)
   - **Commit when verified**

4. **Implement Script 3** (`verify_phase0_output.py`)
   - Create verification checks
   - Test: Run against current organism_taxonomy_enriched.parquet
   - **Commit**

5. **Implement Script 4** (`run_phase0_pipeline.R`)
   - Master pipeline
   - Test end-to-end
   - **Commit**

6. **Checksum Verification** (if Python baseline exists)
   - Run Python baseline → get checksums
   - Run R DuckDB → get checksums
   - Compare, iterate until parity
   - Document in README.md

7. **Integrate into Master Pipeline**
   - Update `run_complete_taxonomy_pipeline.sh` to run Phase 0 first
   - Test full pipeline: Phase 0 → 1 → 2 → 3 → 4

---

## Critical Translation Rules

### Python DuckDB → R DuckDB

#### 1. SQL Syntax (IDENTICAL)
```r
# Python
con.execute("""SELECT * FROM table""").fetchdf()

# R
dbGetQuery(con, "SELECT * FROM table")
```

#### 2. LIST Aggregations (IDENTICAL)
```r
# Both languages
LIST(DISTINCT genus) FILTER (WHERE condition)
```

#### 3. Boolean Filtering (CRITICAL DIFFERENCE)
```r
# Python: FILTER (WHERE is_pathogen) → only TRUE
# R: WHERE is_pathogen = TRUE → explicit TRUE check
# ALWAYS use = TRUE in R DuckDB to match Python behavior
```

#### 4. String Splitting
```r
# Python
SPLIT_PART(name, ' ', 1)

# R (same in DuckDB!)
dbGetQuery(con, "SELECT SPLIT_PART(name, ' ', 1) as genus FROM organisms")

# Or extract in R
sapply(strsplit(organisms$name, " "), `[`, 1)
```

#### 5. NULL Handling
```r
# Python
COALESCE(col, 'default')

# R (identical)
dbGetQuery(con, "SELECT COALESCE(col, 'default') FROM table")
```

---

## Checksum Validation Methodology

### Reference
`shipley_checks/docs/Stage_4_Dual_Verification_Pipeline.md` sections 112-150

### Process
1. Export both Python and R outputs to CSV (sorted by organism_name)
2. Convert list columns to pipe-separated strings
3. Generate MD5/SHA256 checksums
4. Compare:
   - ✓ Identical → Parity achieved
   - ❌ Different → Row-by-row diff to find discrepancies

### Example (Fungal Guilds - ACHIEVED PARITY)
```bash
# Python output
MD5: 7f1519ce931dab09451f62f90641b7d6
SHA256: 335d132cd7e57b973c315672f3bc29675129428a5d7c34f751b0a252f2cceec8

# R output
MD5: 7f1519ce931dab09451f62f90641b7d6  # MATCH!
SHA256: 335d132cd7e57b973c315672f3bc29675129428a5d7c34f751b0a252f2cceec8  # MATCH!
```

---

## Git Workflow

### Commit Strategy
```bash
# After each script passes verification
git add shipley_checks/src/Stage_4/taxonomy/phase0_globi/00_extract_all_organisms.R
git commit -m "Add Phase 0: Extract organisms from GloBI (R DuckDB port)"
git push origin main

git add shipley_checks/src/Stage_4/taxonomy/phase0_globi/01_enrich_taxonomy.R
git commit -m "Add Phase 0: Enrich taxonomy via NCBI with DuckDB caching"
git push origin main

# After achieving checksum parity
git add shipley_checks/src/Stage_4/taxonomy/phase0_globi/
git commit -m "Phase 0 complete: Checksum parity achieved with Python baseline

R DuckDB port faithfully replicates Python extraction:
- Organisms: 29,167 (exact match)
- Kingdom distribution: Match
- Ecological roles: Match
- Checksum: MD5 XXXXXXXX (parity with Python)

Dual verification pipeline validated."
git push origin main
```

---

## Testing Checklist

- [ ] Script 1: Extract organisms
  - [ ] Row count ~30K
  - [ ] Genus extraction correct
  - [ ] Ecological role flags set
  - [ ] No nulls in organism_name

- [ ] Script 2: Enrich taxonomy
  - [ ] Kingdom >95% assigned
  - [ ] Animalia >80% of total
  - [ ] Cache working (no re-lookups)
  - [ ] Output matches schema

- [ ] Script 3: Verification
  - [ ] All 11 columns present
  - [ ] No duplicate organisms (unless multi-role)
  - [ ] Kingdom distribution reasonable
  - [ ] File size ~675 KB

- [ ] Script 4: Master pipeline
  - [ ] Runs all scripts sequentially
  - [ ] Handles errors gracefully
  - [ ] Verification passes
  - [ ] Outputs in correct locations

- [ ] Checksum parity (if baseline available)
  - [ ] Python baseline checksums obtained
  - [ ] R output checksums match
  - [ ] Row-by-row comparison if needed

- [ ] Integration
  - [ ] Phase 0 runs before Phase 1
  - [ ] organism_taxonomy_enriched.parquet used by Phase 1
  - [ ] Full pipeline completes successfully

---

## NEXT ACTIONS (Resume Here)

1. Create Phase 0 directory structure
2. Start with Script 1 (organism extraction)
3. Test against current data
4. Commit when verified
5. Repeat for Scripts 2-4
6. Achieve checksum parity
7. Integrate into master pipeline

**Priority:** Implement faithfully, verify thoroughly, commit incrementally.

**End of Temporary Plan**
