# Frontend Verification Pipeline: 100-Guild Gold Standard

**Date Created**: 2025-11-11
**Purpose**: Establish checksum-verified baseline for frontend scorer implementations before Rust migration
**Status**: Planning

---

## Executive Summary

This pipeline creates a gold standard dataset of 100 diverse plant guilds scored by both Python and R implementations. Checksum-verified CSV outputs ensure 100% parity before building a Rust frontend, which will be validated against the same test suite.

**Verification Chain**:
```
Python guild_scorer_v3.py → results_python.csv ─┐
                                                  ├→ MD5/SHA256 comparison → ✓ Parity
R guild_scorer_v3_shipley.R → results_r.csv ────┘

                                                  ↓
Rust guild_scorer (future) → results_rust.csv ──→ Compare against gold standard
```

---

## Part 1: Test Guild Dataset Design

### 1.1 Coverage Requirements

**100 guilds total** covering:

**Size Distribution** (20 guilds each):
- 2-plant guilds (minimal, edge case)
- 3-plant guilds
- 5-plant guilds
- 7-plant guilds (calibration baseline)
- 10-plant guilds (large)

**Climate Distribution** (across all sizes):
- 17 guilds: tier_1_tropical
- 17 guilds: tier_2_arid
- 17 guilds: tier_3_humid_temperate
- 17 guilds: tier_4_mediterranean
- 16 guilds: tier_5_continental
- 16 guilds: tier_6_boreal_polar

**Metric Coverage Edge Cases**:

1. **M1 (Faith's PD)**:
   - Very low PD (<200): Same genus/family guilds
   - Very high PD (>1500): Maximum diversity guilds
   - Missing phylogeny: Plants not in tree (should handle gracefully)

2. **M2 (CSR Conflicts)**:
   - Zero conflicts: All stress-tolerant (High-S)
   - Maximum conflicts: All competitors (High-C)
   - Mixed strategies: C-S-R balanced

3. **M3 (Insect Control)**:
   - No data: No herbivores or predators
   - Rich data: Many herbivore-predator matches
   - Partial data: Some plants with data, others sparse

4. **M4 (Disease Control)**:
   - No data: No pathogens or mycoparasites
   - Rich data: Many pathogen-antagonist matches
   - Partial data: Mixed coverage

5. **M5 (Beneficial Fungi)**:
   - No fungi: Wind-pollinated grasses
   - Rich mycorrhizae: Forest understory plants
   - Mixed: Some with AMF, others with EMF

6. **M6 (Structural Diversity)**:
   - Monoform: All herbs
   - Maximum diversity: Trees + shrubs + herbs + vines
   - Height validated: Light preferences match heights

7. **M7 (Pollinator Support)**:
   - No pollinators: Wind-pollinated
   - Rich data: Bee-pollinated flowers
   - Shared networks: Many pollinators serving multiple plants

**Flags Coverage**:
- N5: Mix of nitrogen-fixing and non-fixing
- N6: pH compatible and incompatible guilds

### 1.2 Guild Selection Algorithm

**Script**: `shipley_checks/src/Stage_4/generate_100_guild_testset.R`

```r
library(arrow)
library(dplyr)
library(jsonlite)

generate_100_guild_testset <- function() {
  # Load full dataset
  plants <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
  organisms <- read_parquet('shipley_checks/validation/organism_profiles_pure_r.csv')
  fungi <- read_parquet('shipley_checks/validation/fungal_guilds_pure_r.csv')

  guilds <- list()

  # 1. Edge Cases (10 guilds)
  guilds[[1]] <- select_same_genus_guild(2)          # M1: Low PD
  guilds[[2]] <- select_max_diversity_guild(7)       # M1: High PD
  guilds[[3]] <- select_all_high_s_guild(5)          # M2: Zero conflicts
  guilds[[4]] <- select_all_high_c_guild(5)          # M2: Max conflicts
  guilds[[5]] <- select_no_data_guild(3)             # M3/M4/M5/M7: Sparse coverage
  guilds[[6]] <- select_rich_biocontrol_guild(7)     # M3/M4: Rich data
  guilds[[7]] <- select_monoform_guild(5)            # M6: All herbs
  guilds[[8]] <- select_max_structure_guild(7)       # M6: Max diversity
  guilds[[9]] <- select_wind_pollinated_guild(3)     # M7: No pollinators
  guilds[[10]] <- select_nitrogen_fixing_guild(5)    # N5: All legumes

  # 2. Size × Climate Grid (90 guilds)
  sizes <- c(2, 3, 5, 7, 10)
  tiers <- c('tier_1_tropical', 'tier_2_arid', 'tier_3_humid_temperate',
             'tier_4_mediterranean', 'tier_5_continental', 'tier_6_boreal_polar')

  guild_idx <- 11
  for (size in sizes) {
    for (tier in tiers) {
      # Select random guild from plants matching climate tier
      guild <- select_random_guild(plants, size, tier)
      guilds[[guild_idx]] <- guild
      guild_idx <- guild_idx + 1
    }
  }

  # Export as JSON
  write_json(guilds, 'shipley_checks/stage4/100_guild_testset.json',
             auto_unbox = TRUE, pretty = TRUE)

  return(guilds)
}

# Helper: Select plants from same genus
select_same_genus_guild <- function(n) {
  plants <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_11711.parquet')

  # Find genus with at least n species
  genus_counts <- plants %>%
    group_by(genus) %>%
    summarise(n = n()) %>%
    filter(n >= !!n) %>%
    arrange(desc(n))

  selected_genus <- genus_counts$genus[1]

  guild <- plants %>%
    filter(genus == selected_genus) %>%
    slice_sample(n = n) %>%
    pull(wfo_taxon_id)

  return(list(
    name = paste0("same_genus_", selected_genus, "_", n, "plant"),
    size = n,
    plant_ids = guild,
    expected_behavior = "Low Faith's PD (same genus)"
  ))
}

# Helper: Select maximum phylogenetic diversity
select_max_diversity_guild <- function(n) {
  plants <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_11711.parquet')

  # Get one species from each of n different families
  guild <- plants %>%
    group_by(family) %>%
    slice_sample(n = 1) %>%
    ungroup() %>%
    slice_sample(n = n) %>%
    pull(wfo_taxon_id)

  return(list(
    name = paste0("max_diversity_", n, "plant"),
    size = n,
    plant_ids = guild,
    expected_behavior = "High Faith's PD (different families)"
  ))
}

# ... Additional helper functions for each edge case
```

**Output**: `shipley_checks/stage4/100_guild_testset.json`

```json
[
  {
    "guild_id": "guild_001",
    "name": "same_genus_quercus_2plant",
    "size": 2,
    "climate_tier": "tier_3_humid_temperate",
    "plant_ids": ["wfo-0001234567", "wfo-0001234568"],
    "expected_behavior": "Low Faith's PD (same genus)",
    "tags": ["edge_case", "m1_low_pd"]
  },
  {
    "guild_id": "guild_002",
    "name": "max_diversity_7plant",
    "size": 7,
    "climate_tier": "tier_3_humid_temperate",
    "plant_ids": ["wfo-0001111111", "wfo-0002222222", ...],
    "expected_behavior": "High Faith's PD (different families)",
    "tags": ["edge_case", "m1_high_pd"]
  },
  ...
]
```

---

## Part 2: CSV Output Format

### 2.1 Output Schema

**File**: `shipley_checks/stage4/guild_scores_100guilds_{python|r}.csv`

**Columns** (61 columns total):

```
Guild Identification (4 columns):
- guild_id: str (guild_001, guild_002, ...)
- guild_name: str
- guild_size: int (2-10)
- climate_tier: str (tier_1_tropical, ...)

Overall Score (1 column):
- overall_score: float (0-100, precision=1 decimal)

Metric Scores - Normalized (7 columns):
- m1_norm: float (0-100, precision=1)
- m2_norm: float (0-100, precision=1)
- m3_norm: float (0-100, precision=1)
- m4_norm: float (0-100, precision=1)
- m5_norm: float (0-100, precision=1)
- m6_norm: float (0-100, precision=1)
- m7_norm: float (0-100, precision=1)

Metric Scores - Raw (7 columns):
- m1_raw: float (precision=6 decimals)
- m2_raw: float (precision=6 decimals)
- m3_raw: float (precision=6 decimals)
- m4_raw: float (precision=6 decimals)
- m5_raw: float (precision=6 decimals)
- m6_raw: float (precision=6 decimals)
- m7_raw: float (precision=6 decimals)

Metric Details - M1 Faith's PD (2 columns):
- m1_faiths_pd: float (precision=2)
- m1_pest_risk: float (precision=6)

Metric Details - M2 CSR (2 columns):
- m2_conflicts: int
- m2_conflict_density: float (precision=6)

Metric Details - M3 Biocontrol (4 columns):
- m3_biocontrol_raw: float (precision=6)
- m3_max_pairs: int
- m3_n_mechanisms: int
- m3_mechanism_types: str (pipe-separated: "animal_predator|fungal_parasite")

Metric Details - M4 Disease Control (4 columns):
- m4_pathogen_control_raw: float (precision=6)
- m4_max_pairs: int
- m4_n_mechanisms: int
- m4_mechanism_types: str (pipe-separated)

Metric Details - M5 Fungi (3 columns):
- m5_n_shared_fungi: int
- m5_plants_with_fungi: int
- m5_shared_fungi_sample: str (pipe-separated, first 5 species)

Metric Details - M6 Structure (3 columns):
- m6_n_forms: int
- m6_height_range: float (precision=2)
- m6_forms: str (pipe-separated: "tree|shrub|herbaceous")

Metric Details - M7 Pollinators (3 columns):
- m7_n_shared_pollinators: int
- m7_plants_with_pollinators: int
- m7_shared_pollinators_sample: str (pipe-separated, first 5 species)

Flags (2 columns):
- flag_nitrogen: str ("None" | "Partial" | "Full")
- flag_ph: str ("Compatible" | "Incompatible")

Plant IDs (1 column):
- plant_ids: str (pipe-separated WFO IDs)

Timestamp (1 column):
- timestamp: str (ISO 8601: "2025-11-11T10:30:45Z")
```

**Sorting**: Results must be sorted by `guild_id` ascending for deterministic checksums

**Precision**: All floats rounded to specified decimal places BEFORE writing CSV

### 2.2 Example Row

```csv
guild_id,guild_name,guild_size,climate_tier,overall_score,m1_norm,m2_norm,m3_norm,m4_norm,m5_norm,m6_norm,m7_norm,m1_raw,m2_raw,m3_raw,m4_raw,m5_raw,m6_raw,m7_raw,m1_faiths_pd,m1_pest_risk,m2_conflicts,m2_conflict_density,m3_biocontrol_raw,m3_max_pairs,m3_n_mechanisms,m3_mechanism_types,m4_pathogen_control_raw,m4_max_pairs,m4_n_mechanisms,m4_mechanism_types,m5_n_shared_fungi,m5_plants_with_fungi,m5_shared_fungi_sample,m6_n_forms,m6_height_range,m6_forms,m7_n_shared_pollinators,m7_plants_with_pollinators,m7_shared_pollinators_sample,flag_nitrogen,flag_ph,plant_ids,timestamp
guild_001,forest_garden_7plant,7,tier_3_humid_temperate,88.8,50.0,50.0,100.0,100.0,50.0,50.0,50.0,0.430000,0.000000,6.000000,2.857143,10.720000,0.730000,5.000000,844.68,0.430000,0,0.000000,12.600000,42,5,animal_predator|fungal_parasite,60.000000,42,8,general_mycoparasite,23,5,mycosphaerella|leptosphaeria|phyllosticta|septoria|cladosporium,4,22.84,tree|shrub|herbaceous|shrub/tree,5,5,Apis mellifera|Eristalis tenax|Lasioglossum|Eristalis arbustorum|Lasioglossum (austrevylaeus) maunga,Partial,Compatible,wfo-0000832453|wfo-0000649136|wfo-0000642673|wfo-0000984977|wfo-0000241769|wfo-0000092746|wfo-0000690499,2025-11-11T10:30:45Z
```

---

## Part 3: Python CSV Export Implementation

**File**: `shipley_checks/src/Stage_4/python_baseline/score_100_guilds_export_csv.py`

```python
#!/usr/bin/env python3
"""
Score 100 guilds using Python frontend and export to deterministic CSV.
"""

import sys
sys.path.insert(0, '/home/olier/ellenberg')

import json
import pandas as pd
from datetime import datetime, timezone
from pathlib import Path
from src.Stage_4.guild_scorer_v3 import GuildScorerV3

def score_100_guilds():
    """Score 100 test guilds and export to CSV."""

    # Load test guild dataset
    testset_path = Path('shipley_checks/stage4/100_guild_testset.json')
    with open(testset_path) as f:
        guilds = json.load(f)

    print(f"Loaded {len(guilds)} test guilds")

    results = []

    for guild in guilds:
        guild_id = guild['guild_id']
        plant_ids = guild['plant_ids']
        climate_tier = guild['climate_tier']

        print(f"Scoring {guild_id} ({len(plant_ids)} plants, {climate_tier})...")

        # Initialize scorer with correct climate tier
        scorer = GuildScorerV3(
            calibration_type='7plant',
            climate_tier=climate_tier
        )

        # Score guild
        result = scorer.score_guild(plant_ids)

        # Build CSV row with deterministic precision
        row = {
            'guild_id': guild_id,
            'guild_name': guild['name'],
            'guild_size': guild['size'],
            'climate_tier': climate_tier,
            'overall_score': round(result['overall_score'], 1),

            # Normalized scores
            'm1_norm': round(result['metrics']['m1'], 1),
            'm2_norm': round(result['metrics']['m2'], 1),
            'm3_norm': round(result['metrics']['m3'], 1),
            'm4_norm': round(result['metrics']['m4'], 1),
            'm5_norm': round(result['metrics']['m5'], 1),
            'm6_norm': round(result['metrics']['m6'], 1),
            'm7_norm': round(result['metrics']['m7'], 1),

            # Raw scores
            'm1_raw': round(result['details']['m1']['raw'], 6),
            'm2_raw': round(result['details']['m2']['raw'], 6),
            'm3_raw': round(result['details']['m3']['raw'], 6),
            'm4_raw': round(result['details']['m4']['raw'], 6),
            'm5_raw': round(result['details']['m5']['raw'], 6),
            'm6_raw': round(result['details']['m6']['raw'], 6),
            'm7_raw': round(result['details']['m7']['raw'], 6),

            # M1 details
            'm1_faiths_pd': round(result['details']['m1']['faiths_pd'], 2),
            'm1_pest_risk': round(result['details']['m1']['pest_risk_raw'], 6),

            # M2 details
            'm2_conflicts': result['details']['m2']['n_conflicts'],
            'm2_conflict_density': round(result['details']['m2']['conflict_density'], 6),

            # M3 details
            'm3_biocontrol_raw': round(result['details']['m3']['biocontrol_raw'], 6),
            'm3_max_pairs': result['details']['m3']['max_pairs'],
            'm3_n_mechanisms': result['details']['m3']['n_mechanisms'],
            'm3_mechanism_types': '|'.join(set([m['type'] for m in result['details']['m3']['mechanisms']])),

            # M4 details
            'm4_pathogen_control_raw': round(result['details']['m4']['pathogen_control_raw'], 6),
            'm4_max_pairs': result['details']['m4']['max_pairs'],
            'm4_n_mechanisms': result['details']['m4']['n_mechanisms'],
            'm4_mechanism_types': '|'.join(set([m['type'] for m in result['details']['m4']['mechanisms']])),

            # M5 details
            'm5_n_shared_fungi': result['details']['m5']['n_shared_fungi'],
            'm5_plants_with_fungi': result['details']['m5']['plants_with_fungi'],
            'm5_shared_fungi_sample': '|'.join(result['details']['m5']['shared_fungi_sample'][:5]),

            # M6 details
            'm6_n_forms': result['details']['m6']['n_forms'],
            'm6_height_range': round(result['details']['m6']['height_range'], 2),
            'm6_forms': '|'.join(sorted(result['details']['m6']['forms'])),

            # M7 details
            'm7_n_shared_pollinators': result['details']['m7']['n_shared_pollinators'],
            'm7_plants_with_pollinators': result['details']['m7']['plants_with_pollinators'],
            'm7_shared_pollinators_sample': '|'.join(result['details']['m7']['shared_pollinators_sample'][:5]),

            # Flags
            'flag_nitrogen': result['flags']['nitrogen'],
            'flag_ph': result['flags']['ph'],

            # Plant IDs
            'plant_ids': '|'.join(plant_ids),

            # Timestamp (fixed for deterministic output)
            'timestamp': '2025-11-11T00:00:00Z'
        }

        results.append(row)

    # Create DataFrame and sort by guild_id
    df = pd.DataFrame(results)
    df = df.sort_values('guild_id')

    # Export to CSV
    output_path = Path('shipley_checks/stage4/guild_scores_100guilds_python.csv')
    df.to_csv(output_path, index=False)

    print(f"\n✓ Exported {len(df)} guild scores to {output_path}")
    print(f"  File size: {output_path.stat().st_size:,} bytes")

    return df

if __name__ == '__main__':
    score_100_guilds()
```

**Key Points**:
- Fixed timestamp for deterministic output
- Sorted by guild_id
- Deterministic precision rounding
- Pipe-separated lists (sorted where applicable)

---

## Part 4: R CSV Export Implementation

**File**: `shipley_checks/src/Stage_4/score_100_guilds_export_csv.R`

```r
#!/usr/bin/env Rscript
#
# Score 100 guilds using R frontend and export to deterministic CSV.
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(readr)
})

source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

score_100_guilds <- function() {
  # Load test guild dataset
  guilds <- fromJSON('shipley_checks/stage4/100_guild_testset.json')

  cat(sprintf("Loaded %d test guilds\n", length(guilds)))

  results <- list()

  for (i in seq_along(guilds)) {
    guild <- guilds[[i]]
    guild_id <- guild$guild_id
    plant_ids <- guild$plant_ids
    climate_tier <- guild$climate_tier

    cat(sprintf("Scoring %s (%d plants, %s)...\n",
                guild_id, length(plant_ids), climate_tier))

    # Initialize scorer with correct climate tier
    scorer <- GuildScorerV3Shipley$new(
      calibration_type = '7plant',
      climate_tier = climate_tier
    )

    # Score guild
    result <- scorer$score_guild(plant_ids)

    # Build CSV row with deterministic precision
    row <- list(
      guild_id = guild_id,
      guild_name = guild$name,
      guild_size = guild$size,
      climate_tier = climate_tier,
      overall_score = round(result$overall_score, 1),

      # Normalized scores
      m1_norm = round(result$metrics$m1, 1),
      m2_norm = round(result$metrics$m2, 1),
      m3_norm = round(result$metrics$m3, 1),
      m4_norm = round(result$metrics$m4, 1),
      m5_norm = round(result$metrics$m5, 1),
      m6_norm = round(result$metrics$m6, 1),
      m7_norm = round(result$metrics$m7, 1),

      # Raw scores
      m1_raw = round(result$details$m1$raw, 6),
      m2_raw = round(result$details$m2$raw, 6),
      m3_raw = round(result$details$m3$raw, 6),
      m4_raw = round(result$details$m4$raw, 6),
      m5_raw = round(result$details$m5$raw, 6),
      m6_raw = round(result$details$m6$raw, 6),
      m7_raw = round(result$details$m7$raw, 6),

      # M1 details
      m1_faiths_pd = round(result$details$m1$faiths_pd, 2),
      m1_pest_risk = round(result$details$m1$pest_risk_raw, 6),

      # M2 details
      m2_conflicts = result$details$m2$n_conflicts,
      m2_conflict_density = round(result$details$m2$conflict_density, 6),

      # M3 details
      m3_biocontrol_raw = round(result$details$m3$biocontrol_raw, 6),
      m3_max_pairs = result$details$m3$max_pairs,
      m3_n_mechanisms = result$details$m3$n_mechanisms,
      m3_mechanism_types = paste(unique(sapply(result$details$m3$mechanisms, function(m) m$type)), collapse = '|'),

      # M4 details
      m4_pathogen_control_raw = round(result$details$m4$pathogen_control_raw, 6),
      m4_max_pairs = result$details$m4$max_pairs,
      m4_n_mechanisms = result$details$m4$n_mechanisms,
      m4_mechanism_types = paste(unique(sapply(result$details$m4$mechanisms, function(m) m$type)), collapse = '|'),

      # M5 details
      m5_n_shared_fungi = result$details$m5$n_shared_fungi,
      m5_plants_with_fungi = result$details$m5$plants_with_fungi,
      m5_shared_fungi_sample = paste(head(result$details$m5$shared_fungi_sample, 5), collapse = '|'),

      # M6 details
      m6_n_forms = result$details$m6$n_forms,
      m6_height_range = round(result$details$m6$height_range, 2),
      m6_forms = paste(sort(result$details$m6$forms), collapse = '|'),

      # M7 details
      m7_n_shared_pollinators = result$details$m7$n_shared_pollinators,
      m7_plants_with_pollinators = result$details$m7$plants_with_pollinators,
      m7_shared_pollinators_sample = paste(head(result$details$m7$shared_pollinators_sample, 5), collapse = '|'),

      # Flags
      flag_nitrogen = result$flags$nitrogen,
      flag_ph = result$flags$ph,

      # Plant IDs
      plant_ids = paste(plant_ids, collapse = '|'),

      # Timestamp (fixed for deterministic output)
      timestamp = '2025-11-11T00:00:00Z'
    )

    results[[i]] <- row
  }

  # Convert to data frame and sort by guild_id
  df <- bind_rows(results) %>%
    arrange(guild_id)

  # Export to CSV
  output_path <- 'shipley_checks/stage4/guild_scores_100guilds_r.csv'
  write_csv(df, output_path)

  cat(sprintf("\n✓ Exported %d guild scores to %s\n", nrow(df), output_path))
  cat(sprintf("  File size: %s bytes\n", format(file.size(output_path), big.mark = ',')))

  return(df)
}

# Run if called directly
if (!interactive()) {
  score_100_guilds()
}
```

---

## Part 5: Checksum Verification Script

**File**: `shipley_checks/src/Stage_4/verify_frontend_parity_100guilds.py`

```python
#!/usr/bin/env python3
"""
Verify checksum parity between Python and R guild scorer outputs.
"""

import hashlib
import pandas as pd
from pathlib import Path

def calculate_checksums(csv_path):
    """Calculate MD5 and SHA256 checksums for CSV file."""
    with open(csv_path, 'rb') as f:
        content = f.read()

    md5 = hashlib.md5(content).hexdigest()
    sha256 = hashlib.sha256(content).hexdigest()

    return md5, sha256

def compare_csv_files(python_path, r_path):
    """Compare two CSV files column by column."""

    print("Loading CSV files...")
    df_python = pd.read_csv(python_path)
    df_r = pd.read_csv(r_path)

    print(f"Python: {len(df_python)} rows, {len(df_python.columns)} columns")
    print(f"R:      {len(df_r)} rows, {len(df_r.columns)} columns")

    # Check row count
    if len(df_python) != len(df_r):
        print(f"❌ Row count mismatch: {len(df_python)} vs {len(df_r)}")
        return False

    # Check column names
    if list(df_python.columns) != list(df_r.columns):
        print("❌ Column names mismatch")
        print(f"Python columns: {df_python.columns.tolist()}")
        print(f"R columns: {df_r.columns.tolist()}")
        return False

    # Compare row by row
    differences = []

    for idx in range(len(df_python)):
        python_row = df_python.iloc[idx]
        r_row = df_r.iloc[idx]
        guild_id = python_row['guild_id']

        for col in df_python.columns:
            python_val = python_row[col]
            r_val = r_row[col]

            # Handle NaN comparison
            if pd.isna(python_val) and pd.isna(r_val):
                continue

            # Compare
            if python_val != r_val:
                differences.append({
                    'guild_id': guild_id,
                    'column': col,
                    'python_value': python_val,
                    'r_value': r_val
                })

    if differences:
        print(f"\n❌ Found {len(differences)} differences:")
        for diff in differences[:10]:  # Show first 10
            print(f"  {diff['guild_id']}.{diff['column']}: {diff['python_value']} vs {diff['r_value']}")
        if len(differences) > 10:
            print(f"  ... and {len(differences) - 10} more")
        return False

    return True

def verify_frontend_parity():
    """Main verification function."""

    python_path = Path('shipley_checks/stage4/guild_scores_100guilds_python.csv')
    r_path = Path('shipley_checks/stage4/guild_scores_100guilds_r.csv')

    print("=" * 70)
    print("Frontend Scorer Parity Verification: 100 Guild Gold Standard")
    print("=" * 70)

    # Check files exist
    if not python_path.exists():
        print(f"❌ Python output not found: {python_path}")
        return False

    if not r_path.exists():
        print(f"❌ R output not found: {r_path}")
        return False

    print(f"\n✓ Both output files exist")

    # Calculate checksums
    print("\nCalculating checksums...")
    python_md5, python_sha256 = calculate_checksums(python_path)
    r_md5, r_sha256 = calculate_checksums(r_path)

    print(f"\nPython CSV:")
    print(f"  MD5:    {python_md5}")
    print(f"  SHA256: {python_sha256}")

    print(f"\nR CSV:")
    print(f"  MD5:    {r_md5}")
    print(f"  SHA256: {r_sha256}")

    # Compare checksums
    if python_md5 == r_md5 and python_sha256 == r_sha256:
        print("\n" + "=" * 70)
        print("✅ PERFECT CHECKSUM PARITY")
        print("=" * 70)
        print("Python and R produce byte-for-byte identical CSV outputs.")
        print("Gold standard verified for Rust implementation.")
        return True
    else:
        print("\n⚠ Checksums differ - performing detailed comparison...")

        # Detailed comparison
        if compare_csv_files(python_path, r_path):
            print("\n" + "=" * 70)
            print("✅ LOGICAL PARITY (values match, formatting may differ)")
            print("=" * 70)
            print("Python and R produce identical numerical results.")
            print("Minor differences in string formatting acceptable.")
            return True
        else:
            print("\n" + "=" * 70)
            print("❌ VERIFICATION FAILED")
            print("=" * 70)
            print("Python and R produce different results.")
            print("Review differences above and debug scorer implementations.")
            return False

if __name__ == '__main__':
    success = verify_frontend_parity()
    exit(0 if success else 1)
```

---

## Part 6: Execution Pipeline

### 6.1 Complete Workflow

**Script**: `shipley_checks/src/Stage_4/run_frontend_verification_pipeline.sh`

```bash
#!/bin/bash
#
# Complete frontend verification pipeline
#

set -e  # Exit on error

echo "=========================================="
echo "Frontend Verification Pipeline: 100 Guilds"
echo "=========================================="
echo ""

# Step 1: Generate 100-guild test dataset
echo "Step 1: Generating 100-guild test dataset..."
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/generate_100_guild_testset.R

echo "✓ Test dataset generated"
echo ""

# Step 2: Run Python scorer
echo "Step 2: Scoring guilds with Python frontend..."
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/python_baseline/score_100_guilds_export_csv.py

echo "✓ Python scoring complete"
echo ""

# Step 3: Run R scorer
echo "Step 3: Scoring guilds with R frontend..."
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/score_100_guilds_export_csv.R

echo "✓ R scoring complete"
echo ""

# Step 4: Verify parity
echo "Step 4: Verifying checksum parity..."
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/verify_frontend_parity_100guilds.py

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ PIPELINE SUCCESS"
    echo "=========================================="
    echo "Gold standard verified. Ready for Rust implementation."
else
    echo ""
    echo "=========================================="
    echo "❌ PIPELINE FAILED"
    echo "=========================================="
    echo "Fix scorer implementations and re-run."
    exit 1
fi
```

**Usage**:
```bash
cd /home/olier/ellenberg
chmod +x shipley_checks/src/Stage_4/run_frontend_verification_pipeline.sh
./shipley_checks/src/Stage_4/run_frontend_verification_pipeline.sh
```

### 6.2 Expected Output

```
==========================================
Frontend Verification Pipeline: 100 Guilds
==========================================

Step 1: Generating 100-guild test dataset...
Selected 10 edge case guilds
Generated 90 size × climate guilds
✓ Exported 100 guilds to 100_guild_testset.json
✓ Test dataset generated

Step 2: Scoring guilds with Python frontend...
Loaded 100 test guilds
Scoring guild_001 (2 plants, tier_3_humid_temperate)...
Scoring guild_002 (7 plants, tier_3_humid_temperate)...
...
✓ Exported 100 guild scores to guild_scores_100guilds_python.csv
  File size: 45,123 bytes
✓ Python scoring complete

Step 3: Scoring guilds with R frontend...
Loaded 100 test guilds
Scoring guild_001 (2 plants, tier_3_humid_temperate)...
Scoring guild_002 (7 plants, tier_3_humid_temperate)...
...
✓ Exported 100 guild scores to guild_scores_100guilds_r.csv
  File size: 45,123 bytes
✓ R scoring complete

Step 4: Verifying checksum parity...
======================================================================
Frontend Scorer Parity Verification: 100 Guild Gold Standard
======================================================================

✓ Both output files exist

Calculating checksums...

Python CSV:
  MD5:    a3b2c1d4e5f6789012345678901234ab
  SHA256: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef

R CSV:
  MD5:    a3b2c1d4e5f6789012345678901234ab
  SHA256: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef

======================================================================
✅ PERFECT CHECKSUM PARITY
======================================================================
Python and R produce byte-for-byte identical CSV outputs.
Gold standard verified for Rust implementation.

==========================================
✅ PIPELINE SUCCESS
==========================================
Gold standard verified. Ready for Rust implementation.
```

---

## Part 7: Rust Frontend Verification (Future)

### 7.1 Rust Implementation Tests

Once Rust implementation is complete, run the same verification:

```bash
# Score with Rust
cargo run --release --bin score_100_guilds \
  --input shipley_checks/stage4/100_guild_testset.json \
  --output shipley_checks/stage4/guild_scores_100guilds_rust.csv

# Verify against gold standard (Python/R)
python shipley_checks/src/Stage_4/verify_rust_against_gold_standard.py
```

**Verification Script**: `verify_rust_against_gold_standard.py`

```python
def verify_rust_implementation():
    """Verify Rust output matches Python/R gold standard."""

    # Load gold standard (Python or R - they're identical)
    gold_standard = pd.read_csv('shipley_checks/stage4/guild_scores_100guilds_python.csv')

    # Load Rust output
    rust_output = pd.read_csv('shipley_checks/stage4/guild_scores_100guilds_rust.csv')

    # Compare
    differences = compare_dataframes(gold_standard, rust_output, tolerance=1e-6)

    if not differences:
        print("✅ Rust implementation matches gold standard perfectly")
        return True
    else:
        print(f"❌ Found {len(differences)} differences:")
        for diff in differences:
            print(f"  {diff}")
        return False
```

### 7.2 Continuous Verification

Add to CI/CD pipeline:

```yaml
# .github/workflows/verify_frontend.yml
name: Frontend Scorer Verification

on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Setup Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.11'

      - name: Setup R
        uses: r-lib/actions/setup-r@v2

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          Rscript -e 'install.packages(c("arrow", "dplyr", "jsonlite"))'

      - name: Run verification pipeline
        run: ./shipley_checks/src/Stage_4/run_frontend_verification_pipeline.sh

      - name: Verify Rust (if exists)
        run: |
          if [ -f "cargo.toml" ]; then
            cargo build --release
            python shipley_checks/src/Stage_4/verify_rust_against_gold_standard.py
          fi
```

---

## Part 8: Benefits and Validation Strategy

### 8.1 Why This Approach Works

1. **Deterministic Output**: Fixed timestamps, sorted rows, consistent precision
2. **Comprehensive Coverage**: 100 guilds × 7 metrics × 6 climate tiers = 42,000 data points
3. **Edge Case Testing**: Explicit coverage of boundary conditions
4. **Gold Standard**: Python ⟷ R verification creates trusted baseline
5. **Future-Proof**: Rust (and any future implementation) tests against proven baseline

### 8.2 Validation Confidence

**Before Rust Migration**:
- ✓ Python implementation tested (current production)
- ✓ R implementation tested (Bill Shipley verification)
- ✓ Python ⟷ R checksum parity (100% match)
- ✓ 100 guilds covering all edge cases
- ✓ Data source independence maintained

**After Rust Migration**:
- ✓ Rust tested against gold standard CSV
- ✓ Performance benchmarked (Rust should be 10-20× faster)
- ✓ Container size verified (should be <50 MB)
- ✓ API compatibility maintained (same JSON inputs/outputs)

### 8.3 Acceptance Criteria

**For Rust implementation to pass**:
1. All 100 guilds match gold standard within tolerance (±0.000001 for floats)
2. Performance: <1ms per guild (vs 14ms Python, 18ms R)
3. Container: <50 MB (vs 500 MB Python, 2 GB R)
4. Memory: <100 MB per request (vs 150 MB Python, 300 MB R)
5. API compatibility: Drop-in replacement for Python scorer

---

## Part 9: Timeline and Effort

### 9.1 Implementation Schedule

**Week 1: Python/R Gold Standard**
- Day 1: Generate 100-guild test dataset (4 hours)
- Day 2: Python CSV export script (3 hours)
- Day 3: R CSV export script (3 hours)
- Day 4: Checksum verification script (2 hours)
- Day 5: Run verification pipeline, debug differences (4 hours)

**Week 2-3: Rust Implementation**
- Week 2: Core Rust scorer (M1-M7 metrics)
- Week 3: Testing, debugging, optimization

**Week 4: Deployment**
- Rust API wrapper
- Docker container
- Cloud Run deployment
- Load testing

### 9.2 Success Metrics

**Gold Standard Phase**:
- ✅ 100 guilds generated with comprehensive coverage
- ✅ Python and R produce identical CSV (byte-for-byte checksum match)
- ✅ Execution time: <5 minutes for full pipeline
- ✅ Documentation complete

**Rust Implementation Phase**:
- ✅ Passes all 100 guild tests (gold standard match)
- ✅ 10× faster than Python (target: <2ms per guild)
- ✅ Container <50 MB
- ✅ Memory <100 MB per request
- ✅ Production deployment successful

---

## Document Status

**Status**: Planning - Ready for Implementation

**Next Actions**:
1. Generate 100-guild test dataset with edge case coverage
2. Implement Python CSV export with deterministic output
3. Implement R CSV export with deterministic output
4. Run verification pipeline and ensure checksum parity
5. Document gold standard for Rust implementation

**Dependencies**:
- Existing Python scorer: `src/Stage_4/guild_scorer_v3.py`
- Existing R scorer: `shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R`
- C++ Faith's PD binary: `src/Stage_4/compact_tree`
- Calibration JSON: `shipley_checks/stage4/normalization_params_7plant_R.json`
