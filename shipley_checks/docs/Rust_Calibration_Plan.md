# Rust-Based Köppen-Stratified Calibration Plan

**Date Created**: 2025-11-17
**Purpose**: Migrate Köppen-stratified calibration from R to Rust for 10-25× speedup
**Status**: Planning Phase

---

## Executive Summary

**Objective:** Replace R-based calibration pipeline with Rust implementation while maintaining 100% parity with existing calibration logic.

**Key Benefits:**
- **20-25× speedup** vs R (based on existing Rust scorer benchmarks)
- **100× speedup** vs Python (Rust + Polars vs pandas)
- **Climate-stratified calibration** (6 Köppen tiers)
- **2-stage calibration** (2-plant pairs + 7-plant guilds)
- **Parallel processing** (Rayon) for Monte Carlo sampling

**Target Performance:**
- Current R: ~120K guilds in 300-600 seconds
- Projected Rust: ~120K guilds in 12-30 seconds

**Data Source:** New Phase 4 output with multilingual vernaculars + Köppen zones
- File: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`
- 11,713 plants × 861 columns
- 100% Köppen coverage, 88% vernacular coverage

---

## CRITICAL PREREQUISITE: R-Rust M4 Parity

**BLOCKER:** Rust implementation has fungivore enhancement for M4 (disease control) that R lacks.

**Current State:**

**R M4 Implementation** (2 mechanisms):
1. Mechanism 1: Specific antagonist matches (pathogen → known mycoparasite)
2. Mechanism 2: General mycoparasites

**Rust M4 Implementation** (3 mechanisms):
1. Mechanism 1: Specific antagonist matches (pathogen → known mycoparasite)
2. Mechanism 2: General mycoparasites
3. **Mechanism 3: Fungivores eating pathogens** (NEW - Rust only)

**Impact:** R and Rust will produce different M4 scores, breaking parity verification.

**Required Before Calibration:**

1. **Update R M4 to include fungivore logic:**
   - File: `shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R`
   - Function: `calculate_m4()`
   - Add: Fungivore-pathogen matching mechanism
   - Weight: Same as Rust (1.0 for specific matches, 0.2 for general)

2. **Verify local parity on M4:**
   - Test with 3 guilds (Forest Garden, Competitive Clash, Stress Tolerant)
   - Compare M4 raw scores: R vs Rust (tolerance: ±0.001)
   - Compare M4 normalized scores: R vs Rust (tolerance: ±0.1)

3. **Update R data source:**
   - Ensure R has fungivore data: `organism_profiles_pure_r.csv`
   - Column: `fungivores_eats` (pipe-separated animal genera)
   - Source: Phase 0 Script 2 (organism_profiles_11711.parquet)

**Timeline:**
- R fungivore implementation: 1-2 hours
- Parity verification: 30 minutes
- **Then proceed with Rust calibration plan below**

**Alternative Approach:**
If fungivore enhancement is experimental, could:
1. Remove fungivore logic from Rust M4 temporarily
2. Calibrate with 2-mechanism M4 (parity achieved)
3. Re-add fungivore logic after calibration
4. Accept that M4 scores will shift (recalibration needed)

**Recommended:** Implement fungivore in R first for full parity.

---

## Part 1: Current State Analysis

### 1.1 Existing R Calibration Pipeline

**Script:** `shipley_checks/src/Stage_4/calibrate_2stage_koppen.R`

**Architecture:**
```
Stage 1: 2-Plant Pairs
  - 20K pairs per tier × 6 tiers = 120K pairs
  - Purpose: Capture baseline conflict patterns
  - Metrics: M1 (Faith's PD), M2 (CSR conflicts)

Stage 2: 7-Plant Guilds
  - 20K guilds per tier × 6 tiers = 120K guilds
  - Purpose: Capture full biocontrol network patterns
  - Metrics: M1-M7 (all metrics)

Output: normalization_params_7plant.json
  - 6 tiers × 7 metrics × 13 percentiles = 546 calibration values
```

**Climate Tiers (Köppen zones):**
```r
tier_1_tropical:       Af, Am, Aw, As          (1,659 plants, 14.2%)
tier_2_mediterranean:  Csa, Csb, Csc           (4,085 plants, 34.9%)
tier_3_humid_temperate: Cfa, Cfb, Cfc, Cwa, Cwb, Cwc (8,833 plants, 75.4%)
tier_4_continental:    Dfa, Dfb, Dfc, Dfd, Dwa, Dwb, Dwc, Dwd, Dsa, Dsb, Dsc, Dsd (4,402 plants, 37.6%)
tier_5_boreal_polar:   ET, EF                  (964 plants, 8.2%)
tier_6_arid:           BWh, BWk, BSh, BSk      (2,413 plants, 20.6%)
```

**Percentile Bins:** 13 values per metric per tier
- p1, p5, p10, p20, p30, p40, p50, p60, p70, p80, p90, p95, p99

**Current Performance (R):**
- 2-plant calibration: ~150 seconds (120K pairs)
- 7-plant calibration: ~450 seconds (120K guilds)
- **Total: ~600 seconds (10 minutes)**

### 1.2 Existing Rust Implementation Status

**Location:** `shipley_checks/src/Stage_4/guild_scorer_rust/`

**Implemented Components:**

✅ **Data Loading** (`src/data.rs`):
- Polars LazyFrame-based loading
- Schema-only initialization (800× memory reduction)
- Currently uses: `bill_with_csr_ecoservices_koppen_11711_rust.parquet`

✅ **Metrics** (`src/metrics/`):
- M1: Pest & Pathogen Independence (Faith's PD) - ✅ Implemented
- M2: Growth Compatibility (CSR conflicts) - ✅ Implemented
- M3: Insect Control (biocontrol) - ✅ Implemented
- M4: Disease Control (antagonist fungi) - ✅ Implemented
- M5: Beneficial Fungi Networks - ✅ Implemented
- M6: Structural Diversity - ✅ Implemented
- M7: Pollinator Support - ✅ Implemented

✅ **Normalization** (`src/utils/normalization.rs`):
- Percentile interpolation with 13 bins
- CSR percentile normalization (global)
- Calibration JSON loading
- 100% parity with R verified

✅ **Guild Scorer** (`src/scorer.rs`):
- Sequential and parallel (Rayon) implementations
- Climate tier compatibility checking
- Parity tested vs R with 3 guilds

**Test Coverage:** 22 unit tests passing

**Build Status:** Release build with LTO successful

**Current File Paths:**
```rust
// data.rs line 151
let plants_path = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_rust.parquet";

// data.rs line 170
let organisms_path = "shipley_checks/validation/organism_profiles_pure_rust.parquet";

// data.rs line 185
let fungi_path = "shipley_checks/validation/fungal_guilds_pure_rust.parquet";
```

### 1.3 100-Guild Testset

**File:** `shipley_checks/stage4/100_guild_testset.json`

**Structure:**
```json
{
  "guild_id": "guild_001",
  "name": "edge_same_genus_quercus_2plant",
  "size": 2,
  "climate_tier": "tier_3_humid_temperate",
  "plant_ids": ["wfo-0000292300", "wfo-0000293817"],
  "expected_behavior": "Low Faith's PD - same genus",
  "tags": ["edge_case", "m1_low_pd"]
}
```

**Coverage:** 100 guilds spanning:
- All 6 Köppen tiers
- Guild sizes: 2, 5, 7 plants
- Edge cases for each metric (M1-M7)
- Expected behaviors documented

---

## Part 2: Required Changes to Rust Implementation

### 2.1 Update Data File Paths

**File:** `src/data.rs`

**Changes Required:**

```rust
// BEFORE (OLD):
let plants_path = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_rust.parquet";

// AFTER (NEW Phase 4 dataset):
let plants_path = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet";
```

**Impact:**
- New dataset has 861 columns (vs 799)
- Adds 62 vernacular columns (61 languages + metadata)
- Plant count: 11,713 (vs 11,711) - 2 legitimate duplicates
- All required columns (CSR, Köppen tiers, heights) still present

**Verification Needed:**
```rust
// Ensure these columns still exist:
col("wfo_taxon_id")
col("wfo_scientific_name")
col("CSR_C"), col("CSR_S"), col("CSR_R")
col("height_m"), col("try_growth_form")
col("light_pref") // EIVE-L
col("tier_1_tropical"), col("tier_2_mediterranean"), ...
```

### 2.2 Add Climate Tier Organization

**File:** `src/data.rs` (new function)

**Purpose:** Group plants by Köppen tier for stratified sampling

**Implementation:**
```rust
use rustc_hash::FxHashMap;

pub struct ClimateOrganizer {
    tier_plants: FxHashMap<String, Vec<String>>,  // tier_name → plant_wfo_ids
}

impl ClimateOrganizer {
    /// Organize plants by Köppen tier from DataFrame
    pub fn from_plants(plants_df: &DataFrame) -> Result<Self> {
        let tier_columns = vec![
            "tier_1_tropical",
            "tier_2_mediterranean",
            "tier_3_humid_temperate",
            "tier_4_continental",
            "tier_5_boreal_polar",
            "tier_6_arid",
        ];

        let mut tier_plants: FxHashMap<String, Vec<String>> = FxHashMap::default();
        let wfo_ids = plants_df.column("wfo_taxon_id")?.str()?;

        for tier_col in &tier_columns {
            let tier_mask = plants_df.column(tier_col)?
                .bool()?;

            let mut tier_ids = Vec::new();
            for (idx, is_member) in tier_mask.iter().enumerate() {
                if is_member.unwrap_or(false) {
                    if let Some(wfo_id) = wfo_ids.get(idx) {
                        tier_ids.push(wfo_id.to_string());
                    }
                }
            }

            tier_plants.insert(tier_col.to_string(), tier_ids);
            println!("  {:<30}: {:>5} plants", tier_col, tier_ids.len());
        }

        Ok(Self { tier_plants })
    }

    /// Get plant IDs for a specific tier
    pub fn get_tier_plants(&self, tier_name: &str) -> &[String] {
        self.tier_plants.get(tier_name).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Get all tiers
    pub fn tiers(&self) -> Vec<&str> {
        self.tier_plants.keys().map(|s| s.as_str()).collect()
    }
}
```

**Expected Output:**
```
tier_1_tropical               : 1,659 plants
tier_2_mediterranean          : 4,085 plants
tier_3_humid_temperate        : 8,833 plants
tier_4_continental            : 4,402 plants
tier_5_boreal_polar           :   964 plants
tier_6_arid                   : 2,413 plants
```

### 2.3 Add Raw Score Computation

**File:** `src/metrics/mod.rs` (new public function)

**Purpose:** Compute all 7 raw scores without normalization

**Implementation:**
```rust
use crate::GuildData;
use polars::prelude::*;

/// Raw scores for all 7 metrics (unnormalized)
#[derive(Debug)]
pub struct RawScores {
    pub m1_faiths_pd: f64,
    pub m1_pest_risk: f64,
    pub m2_conflict_density: f64,
    pub m3_biocontrol_raw: f64,
    pub m4_pathogen_control_raw: f64,
    pub m5_beneficial_fungi_raw: f64,
    pub m6_stratification_raw: f64,
    pub m7_pollinator_raw: f64,
}

/// Compute raw scores for calibration (no normalization)
pub fn compute_raw_scores_for_calibration(
    plant_ids: &[String],
    data: &GuildData,
    phylo_calculator: &PhyloPDCalculator,
) -> Result<RawScores> {
    // Filter to guild plants
    let guild_plants = data.plants_lazy.clone()
        .filter(col("wfo_taxon_id").is_in(lit(plant_ids)))
        .collect()?;

    let n_plants = guild_plants.height();

    // M1: Faith's PD → exp(-k × faiths_pd)
    let faiths_pd = phylo_calculator.calculate_pd(plant_ids)?;
    let k = 0.001;
    let m1_pest_risk = (-k * faiths_pd).exp();

    // M2: CSR conflict density
    let m2_conflict_density = m2_growth_compatibility::calculate_csr_conflicts(&guild_plants)?;

    // M3: Biocontrol (3 mechanisms)
    let m3_biocontrol_raw = m3_insect_control::calculate_biocontrol_raw(
        plant_ids,
        &data.organisms_lazy,
        &data.fungi_lazy,
        &data.herbivore_predators,
        &data.insect_parasites,
    )?;
    let max_pairs = (n_plants * (n_plants - 1)) as f64;
    let m3_normalized = (m3_biocontrol_raw / max_pairs) * 20.0;

    // M4: Pathogen control (2 mechanisms)
    let m4_pathogen_control_raw = m4_disease_control::calculate_pathogen_control_raw(
        plant_ids,
        &data.fungi_lazy,
        &data.pathogen_antagonists,
    )?;
    let m4_normalized = (m4_pathogen_control_raw / max_pairs) * 10.0;

    // M5: Beneficial fungi (quadratic weighting)
    let (n_shared_fungi, plants_with_fungi) = m5_beneficial_fungi::calculate_fungal_network(
        plant_ids,
        &data.fungi_lazy,
    )?;
    let m5_beneficial_fungi_raw = (n_shared_fungi as f64).sqrt() * (plants_with_fungi as f64).sqrt();

    // M6: Structural diversity (70% light-validated + 30% form diversity)
    let m6_stratification_raw = m6_structural_diversity::calculate_stratification(&guild_plants)?;

    // M7: Pollinator support (quadratic weighting)
    let (n_shared_pollinators, plants_with_pollinators) = m7_pollinator_support::calculate_pollinator_network(
        plant_ids,
        &data.organisms_lazy,
    )?;
    let m7_pollinator_raw = (n_shared_pollinators as f64).sqrt() * (plants_with_pollinators as f64).sqrt();

    Ok(RawScores {
        m1_faiths_pd: faiths_pd,
        m1_pest_risk,
        m2_conflict_density,
        m3_biocontrol_raw: m3_normalized,
        m4_pathogen_control_raw: m4_normalized,
        m5_beneficial_fungi_raw,
        m6_stratification_raw,
        m7_pollinator_raw,
    })
}
```

---

## Part 3: Rust Calibration Pipeline Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ STAGE 1: 2-PLANT PAIRS (20K × 6 TIERS = 120K)             │
├─────────────────────────────────────────────────────────────┤
│ 1. Organize plants by Köppen tier                          │
│ 2. For each tier:                                           │
│    - Sample 20K random 2-plant pairs                        │
│    - Compute raw scores (M1, M2) in parallel                │
│    - Calculate percentiles (p1-p99)                         │
│ 3. Export normalization_params_2plant_rust.json            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ STAGE 2: 7-PLANT GUILDS (20K × 6 TIERS = 120K)            │
├─────────────────────────────────────────────────────────────┤
│ 1. For each tier:                                           │
│    - Sample 20K random 7-plant guilds                       │
│    - Compute raw scores (M1-M7) in parallel                 │
│    - Calculate percentiles (p1-p99)                         │
│ 2. Export normalization_params_7plant_rust.json            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ VERIFICATION: 100-GUILD TESTSET                             │
├─────────────────────────────────────────────────────────────┤
│ 1. Load 100-guild testset JSON                             │
│ 2. Score all guilds with Rust calibration                  │
│ 3. Score all guilds with R calibration                     │
│ 4. Compare normalized scores (tolerance: ±0.1)             │
│ 5. Report parity statistics                                │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Main Calibration Binary

**File:** `src/bin/calibrate_koppen_stratified.rs` (NEW)

**Structure:**
```rust
//! Köppen-Stratified Calibration Pipeline (Rust Implementation)
//!
//! 2-Stage Calibration:
//!   Stage 1: 2-plant pairs (20K per tier × 6 tiers = 120K pairs)
//!   Stage 2: 7-plant guilds (20K per tier × 6 tiers = 120K guilds)
//!
//! Output: normalization_params_7plant_rust.json (546 calibration values)
//!
//! Expected Performance:
//!   - R baseline: ~600 seconds
//!   - Rust target: ~25 seconds (24× speedup)

use guild_scorer_rust::{GuildData, PhyloPDCalculator, ClimateOrganizer};
use guild_scorer_rust::metrics::compute_raw_scores_for_calibration;
use rayon::prelude::*;
use serde_json::json;
use std::time::Instant;

const GUILDS_PER_TIER: usize = 20_000;
const PERCENTILES: [f64; 13] = [1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 95.0, 99.0];

fn main() -> anyhow::Result<()> {
    println!("\n{}", "=".repeat(80));
    println!("KÖPPEN-STRATIFIED CALIBRATION PIPELINE (RUST)");
    println!("{}", "=".repeat(80));

    let total_start = Instant::now();

    // Load datasets
    println!("\nLoading datasets...");
    let data = GuildData::load()?;
    let phylo_calculator = PhyloPDCalculator::new()?;

    // Organize by climate tier
    println!("\nOrganizing plants by Köppen tier...");
    let organizer = ClimateOrganizer::from_plants(&data.plants)?;

    // STAGE 1: 2-PLANT PAIRS
    println!("\n{}", "=".repeat(80));
    println!("STAGE 1: 2-PLANT PAIR CALIBRATION");
    println!("{}", "=".repeat(80));

    let stage1_start = Instant::now();
    let params_2plant = calibrate_2plant_pairs(&organizer, &data, &phylo_calculator)?;
    let stage1_time = stage1_start.elapsed();

    // Save Stage 1 results
    let output_path_2plant = "shipley_checks/stage4/normalization_params_2plant_rust.json";
    std::fs::write(output_path_2plant, serde_json::to_string_pretty(&params_2plant)?)?;
    println!("\n✓ Saved: {}", output_path_2plant);

    // STAGE 2: 7-PLANT GUILDS
    println!("\n{}", "=".repeat(80));
    println!("STAGE 2: 7-PLANT GUILD CALIBRATION");
    println!("{}", "=".repeat(80));

    let stage2_start = Instant::now();
    let params_7plant = calibrate_7plant_guilds(&organizer, &data, &phylo_calculator)?;
    let stage2_time = stage2_start.elapsed();

    // Save Stage 2 results
    let output_path_7plant = "shipley_checks/stage4/normalization_params_7plant_rust.json";
    std::fs::write(output_path_7plant, serde_json::to_string_pretty(&params_7plant)?)?;
    println!("\n✓ Saved: {}", output_path_7plant);

    // Summary
    let total_time = total_start.elapsed();
    println!("\n{}", "=".repeat(80));
    println!("CALIBRATION COMPLETE");
    println!("{}", "=".repeat(80));
    println!("\nStage 1 (2-plant pairs): {:.1}s", stage1_time.as_secs_f64());
    println!("Stage 2 (7-plant guilds): {:.1}s", stage2_time.as_secs_f64());
    println!("\nTotal time: {:.1}s", total_time.as_secs_f64());
    println!("Total guilds: {}", GUILDS_PER_TIER * 6 * 2);

    Ok(())
}

/// Stage 1: Calibrate 2-plant pairs
fn calibrate_2plant_pairs(
    organizer: &ClimateOrganizer,
    data: &GuildData,
    phylo_calculator: &PhyloPDCalculator,
) -> anyhow::Result<serde_json::Value> {
    let mut params = serde_json::Map::new();

    for tier_name in organizer.tiers() {
        println!("\n{}", "-".repeat(70));
        println!("Tier: {}", tier_name);
        println!("{}", "-".repeat(70));

        let tier_plants = organizer.get_tier_plants(tier_name);
        println!("  Available plants: {}", tier_plants.len());

        if tier_plants.len() < 2 {
            println!("  ⚠ Skipping tier (insufficient plants)");
            continue;
        }

        // Sample 20K random pairs
        let start_sampling = Instant::now();
        let pairs = sample_random_pairs(tier_plants, GUILDS_PER_TIER);
        println!("  Sampled {} pairs in {:.2}s", pairs.len(), start_sampling.elapsed().as_secs_f64());

        // Compute raw scores in parallel
        let start_scoring = Instant::now();
        let raw_scores: Vec<_> = pairs.par_iter()
            .filter_map(|pair| {
                compute_raw_scores_for_calibration(pair, data, phylo_calculator).ok()
            })
            .collect();
        println!("  Computed raw scores in {:.2}s", start_scoring.elapsed().as_secs_f64());
        println!("  Valid scores: {}", raw_scores.len());

        // Calculate percentiles for M1 and M2
        let tier_params = calculate_tier_percentiles_2plant(&raw_scores);
        params.insert(tier_name.to_string(), tier_params);
    }

    Ok(serde_json::Value::Object(params))
}

/// Stage 2: Calibrate 7-plant guilds
fn calibrate_7plant_guilds(
    organizer: &ClimateOrganizer,
    data: &GuildData,
    phylo_calculator: &PhyloPDCalculator,
) -> anyhow::Result<serde_json::Value> {
    let mut params = serde_json::Map::new();

    for tier_name in organizer.tiers() {
        println!("\n{}", "-".repeat(70));
        println!("Tier: {}", tier_name);
        println!("{}", "-".repeat(70));

        let tier_plants = organizer.get_tier_plants(tier_name);
        println!("  Available plants: {}", tier_plants.len());

        if tier_plants.len() < 7 {
            println!("  ⚠ Skipping tier (insufficient plants)");
            continue;
        }

        // Sample 20K random 7-plant guilds
        let start_sampling = Instant::now();
        let guilds = sample_random_guilds(tier_plants, 7, GUILDS_PER_TIER);
        println!("  Sampled {} guilds in {:.2}s", guilds.len(), start_sampling.elapsed().as_secs_f64());

        // Compute raw scores in parallel
        let start_scoring = Instant::now();
        let raw_scores: Vec<_> = guilds.par_iter()
            .filter_map(|guild| {
                compute_raw_scores_for_calibration(guild, data, phylo_calculator).ok()
            })
            .collect();
        println!("  Computed raw scores in {:.2}s", start_scoring.elapsed().as_secs_f64());
        println!("  Valid scores: {}", raw_scores.len());

        // Calculate percentiles for M1-M7
        let tier_params = calculate_tier_percentiles_7plant(&raw_scores);
        params.insert(tier_name.to_string(), tier_params);
    }

    Ok(serde_json::Value::Object(params))
}

/// Sample random pairs from tier plants
fn sample_random_pairs(plants: &[String], n_pairs: usize) -> Vec<Vec<String>> {
    use rand::seq::SliceRandom;
    use rand::thread_rng;

    let mut rng = thread_rng();
    let mut pairs = Vec::with_capacity(n_pairs);

    for _ in 0..n_pairs {
        let mut pair: Vec<_> = plants.choose_multiple(&mut rng, 2).cloned().collect();
        pairs.push(pair);
    }

    pairs
}

/// Sample random guilds from tier plants
fn sample_random_guilds(plants: &[String], guild_size: usize, n_guilds: usize) -> Vec<Vec<String>> {
    use rand::seq::SliceRandom;
    use rand::thread_rng();

    let mut rng = thread_rng();
    let mut guilds = Vec::with_capacity(n_guilds);

    for _ in 0..n_guilds {
        let guild: Vec<_> = plants.choose_multiple(&mut rng, guild_size).cloned().collect();
        guilds.push(guild);
    }

    guilds
}

/// Calculate percentiles for 2-plant pairs (M1, M2 only)
fn calculate_tier_percentiles_2plant(raw_scores: &[RawScores]) -> serde_json::Value {
    // Extract raw values
    let m1_values: Vec<f64> = raw_scores.iter().map(|s| s.m1_pest_risk).collect();
    let m2_values: Vec<f64> = raw_scores.iter().map(|s| s.m2_conflict_density).collect();

    // Calculate percentiles
    let m1_percentiles = calculate_percentiles(&m1_values);
    let m2_percentiles = calculate_percentiles(&m2_values);

    json!({
        "m1": m1_percentiles,
        "n4": m2_percentiles,  // n4 is legacy name for M2
    })
}

/// Calculate percentiles for 7-plant guilds (M1-M7)
fn calculate_tier_percentiles_7plant(raw_scores: &[RawScores]) -> serde_json::Value {
    // Extract raw values for each metric
    let m1_values: Vec<f64> = raw_scores.iter().map(|s| s.m1_pest_risk).collect();
    let m2_values: Vec<f64> = raw_scores.iter().map(|s| s.m2_conflict_density).collect();
    let m3_values: Vec<f64> = raw_scores.iter().map(|s| s.m3_biocontrol_raw).collect();
    let m4_values: Vec<f64> = raw_scores.iter().map(|s| s.m4_pathogen_control_raw).collect();
    let m5_values: Vec<f64> = raw_scores.iter().map(|s| s.m5_beneficial_fungi_raw).collect();
    let m6_values: Vec<f64> = raw_scores.iter().map(|s| s.m6_stratification_raw).collect();
    let m7_values: Vec<f64> = raw_scores.iter().map(|s| s.m7_pollinator_raw).collect();

    // Calculate percentiles
    json!({
        "m1": calculate_percentiles(&m1_values),
        "n4": calculate_percentiles(&m2_values),  // n4 is legacy name for M2
        "p1": calculate_percentiles(&m3_values),  // p1 is legacy name for M3
        "p2": calculate_percentiles(&m4_values),  // p2 is legacy name for M4
        "p3": calculate_percentiles(&m5_values),  // p3 is legacy name for M5
        "p5": calculate_percentiles(&m6_values),  // p5 is legacy name for M6
        "p6": calculate_percentiles(&m7_values),  // p6 is legacy name for M7
    })
}

/// Calculate percentile values for a metric
fn calculate_percentiles(values: &[f64]) -> serde_json::Value {
    use statrs::statistics::Statistics;

    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let mut percentile_map = serde_json::Map::new();

    for &p in &PERCENTILES {
        let index = (p / 100.0 * (sorted.len() - 1) as f64).round() as usize;
        let value = sorted.get(index).copied().unwrap_or(50.0);  // Fallback to 50.0
        percentile_map.insert(format!("p{}", p as i32), json!(value));
    }

    serde_json::Value::Object(percentile_map)
}
```

**Dependencies to Add:**
```toml
# Cargo.toml
[dependencies]
rand = "0.8"
statrs = "0.16"
```

### 3.3 Verification Binary

**File:** `src/bin/verify_100_guild_testset.rs` (NEW)

**Purpose:** Score 100-guild testset with Rust and compare to R baseline

**Structure:**
```rust
//! Verify 100-Guild Testset with Rust Implementation
//!
//! 1. Load 100-guild testset JSON
//! 2. Score all guilds with Rust calibration
//! 3. Load R scores from CSV (gold standard)
//! 4. Compare normalized scores (tolerance: ±0.1)
//! 5. Report parity statistics

use guild_scorer_rust::GuildScorer;
use serde::{Deserialize, Serialize};
use std::fs;

#[derive(Deserialize)]
struct TestGuild {
    guild_id: String,
    name: String,
    size: usize,
    climate_tier: String,
    plant_ids: Vec<String>,
    expected_behavior: String,
    tags: Vec<String>,
}

#[derive(Serialize)]
struct GuildResult {
    guild_id: String,
    overall_score: f64,
    m1: f64,
    m2: f64,
    m3: f64,
    m4: f64,
    m5: f64,
    m6: f64,
    m7: f64,
}

fn main() -> anyhow::Result<()> {
    println!("\n{}", "=".repeat(80));
    println!("100-GUILD TESTSET VERIFICATION");
    println!("{}", "=".repeat(80));

    // Load testset
    let testset_json = fs::read_to_string("shipley_checks/stage4/100_guild_testset.json")?;
    let guilds: Vec<TestGuild> = serde_json::from_str(&testset_json)?;
    println!("\nLoaded {} test guilds", guilds.len());

    // Score all guilds by tier
    let mut results = Vec::new();
    let mut scorers: std::collections::HashMap<String, GuildScorer> = std::collections::HashMap::new();

    for guild in &guilds {
        // Initialize scorer for tier (cached)
        if !scorers.contains_key(&guild.climate_tier) {
            println!("\nInitializing scorer for {}...", guild.climate_tier);
            let scorer = GuildScorer::new("7plant_rust", &guild.climate_tier)?;
            scorers.insert(guild.climate_tier.clone(), scorer);
        }

        let scorer = scorers.get(&guild.climate_tier).unwrap();

        // Score guild
        let result = scorer.score_guild(&guild.plant_ids)?;

        results.push(GuildResult {
            guild_id: guild.guild_id.clone(),
            overall_score: result.overall_score,
            m1: result.metrics[0],
            m2: result.metrics[1],
            m3: result.metrics[2],
            m4: result.metrics[3],
            m5: result.metrics[4],
            m6: result.metrics[5],
            m7: result.metrics[6],
        });

        println!("  {} ({} plants): {:.1}/100", guild.guild_id, guild.size, result.overall_score);
    }

    // Save Rust results
    let rust_csv = "shipley_checks/stage4/100_guild_scores_rust.csv";
    save_results_to_csv(&results, rust_csv)?;
    println!("\n✓ Saved Rust scores: {}", rust_csv);

    // Compare to R baseline
    let r_csv = "shipley_checks/stage4/100_guild_scores_r.csv";
    if std::path::Path::new(r_csv).exists() {
        println!("\nComparing to R baseline...");
        compare_scores(&results, r_csv)?;
    } else {
        println!("\n⚠ R baseline not found: {}", r_csv);
        println!("  Run: Rscript shipley_checks/src/Stage_4/score_guilds_export_csv.R");
    }

    Ok(())
}

fn save_results_to_csv(results: &[GuildResult], path: &str) -> anyhow::Result<()> {
    use std::io::Write;
    let mut file = fs::File::create(path)?;
    writeln!(file, "guild_id,overall_score,m1,m2,m3,m4,m5,m6,m7")?;
    for r in results {
        writeln!(file, "{},{:.1},{:.1},{:.1},{:.1},{:.1},{:.1},{:.1},{:.1}",
            r.guild_id, r.overall_score, r.m1, r.m2, r.m3, r.m4, r.m5, r.m6, r.m7)?;
    }
    Ok(())
}

fn compare_scores(rust_results: &[GuildResult], r_csv_path: &str) -> anyhow::Result<()> {
    use std::io::BufRead;

    // Load R baseline
    let file = fs::File::open(r_csv_path)?;
    let reader = std::io::BufReader::new(file);
    let mut r_results = std::collections::HashMap::new();

    for line in reader.lines().skip(1) {  // Skip header
        let line = line?;
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 9 {
            let guild_id = parts[0].to_string();
            let scores: Vec<f64> = parts[1..9]
                .iter()
                .filter_map(|s| s.parse::<f64>().ok())
                .collect();
            r_results.insert(guild_id, scores);
        }
    }

    // Compare
    let tolerance = 0.1;
    let mut max_diff = 0.0_f64;
    let mut total_diff = 0.0_f64;
    let mut n_comparisons = 0;
    let mut mismatches = Vec::new();

    for rust_r in rust_results {
        if let Some(r_scores) = r_results.get(&rust_r.guild_id) {
            let rust_scores = vec![
                rust_r.overall_score, rust_r.m1, rust_r.m2, rust_r.m3,
                rust_r.m4, rust_r.m5, rust_r.m6, rust_r.m7,
            ];

            for (i, (rust_val, r_val)) in rust_scores.iter().zip(r_scores.iter()).enumerate() {
                let diff = (rust_val - r_val).abs();
                total_diff += diff;
                n_comparisons += 1;

                if diff > max_diff {
                    max_diff = diff;
                }

                if diff > tolerance {
                    let metric_name = match i {
                        0 => "Overall",
                        1 => "M1",
                        2 => "M2",
                        3 => "M3",
                        4 => "M4",
                        5 => "M5",
                        6 => "M6",
                        7 => "M7",
                        _ => "Unknown",
                    };
                    mismatches.push(format!(
                        "  {} {}: Rust={:.1}, R={:.1}, diff={:.1}",
                        rust_r.guild_id, metric_name, rust_val, r_val, diff
                    ));
                }
            }
        }
    }

    // Report
    let avg_diff = total_diff / n_comparisons as f64;
    let parity_pct = 100.0 * (1.0 - mismatches.len() as f64 / n_comparisons as f64);

    println!("\n{}", "=".repeat(80));
    println!("PARITY ANALYSIS");
    println!("{}", "=".repeat(80));
    println!("\nComparisons: {}", n_comparisons);
    println!("Average difference: {:.3}", avg_diff);
    println!("Max difference: {:.3}", max_diff);
    println!("Parity rate: {:.1}% (tolerance ±{})", parity_pct, tolerance);

    if mismatches.is_empty() {
        println!("\n✓ ALL CHECKS PASSED - Perfect parity with R");
    } else {
        println!("\n❌ {} mismatches found:", mismatches.len());
        for mismatch in &mismatches {
            println!("{}", mismatch);
        }
    }

    Ok(())
}
```

---

## Part 4: Execution Plan

### 4.0 Phase 0: R-Rust M4 Parity (PREREQUISITE)

**MUST COMPLETE BEFORE CALIBRATION**

**Task 1: Add fungivore column to organism_profiles_pure_r.csv (30 minutes)**

Current R organism data missing fungivores column:
```bash
# Verify current columns
head -1 shipley_checks/validation/organism_profiles_pure_r.csv
```

Expected columns (should include):
- `plant_wfo_id`
- `herbivores` (pipe-separated)
- `pollinators` (pipe-separated)
- `flower_visitors` (pipe-separated)
- `predators_hasHost` (pipe-separated)
- `predators_interactsWith` (pipe-separated)
- `predators_adjacentTo` (pipe-separated)
- **`fungivores_eats`** (pipe-separated) ← MISSING

Solution: Re-run Phase 0 R extraction with fungivore logic from Script 2.

**Task 2: Update R M4 implementation (1 hour)**

File: `shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R`

Add to `calculate_m4()` function after Mechanism 2:

```r
# Mechanism 3: Fungivores eating pathogens (NEW)
# Get guild organism data
guild_organisms <- self$organisms_df %>% filter(plant_wfo_id %in% plant_ids)

for (i in seq_len(nrow(guild_fungi))) {
  row_a <- guild_fungi[i, ]
  plant_a_id <- row_a$plant_wfo_id
  pathogens_a <- row_a$pathogenic_fungi[[1]]

  if (is.null(pathogens_a) || length(pathogens_a) == 0) {
    next
  }

  for (j in seq_len(nrow(guild_organisms))) {
    row_b <- guild_organisms[j, ]
    plant_b_id <- row_b$plant_wfo_id

    if (plant_a_id == plant_b_id) next

    fungivores_b <- row_b$fungivores_eats[[1]]

    if (is.null(fungivores_b) || length(fungivores_b) == 0) {
      next
    }

    # Specific matches: pathogen genus matches fungivore target
    # (Requires lookup table - may not be available)
    # For now: General fungivores (weight 0.2)
    if (length(pathogens_a) > 0 && length(fungivores_b) > 0) {
      pathogen_control_raw <- pathogen_control_raw + length(fungivores_b) * 0.2
      mechanisms[[length(mechanisms) + 1]] <- list(
        type = 'general_fungivore',
        vulnerable_plant = plant_a_id,
        n_pathogens = length(pathogens_a),
        control_plant = plant_b_id,
        fungivores = head(fungivores_b, 5)
      )
    }
  }
}
```

**Task 3: Verify M4 parity (30 minutes)**

Test with 3 guilds:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/test_guilds_against_calibration.R
```

Compare M4 scores:
- Forest Garden: R M4 vs Rust M4 (expect ±0.1 tolerance)
- Competitive Clash: R M4 vs Rust M4
- Stress Tolerant: R M4 vs Rust M4

**Success Criteria:**
- ✅ M4 raw scores match within ±0.001
- ✅ M4 normalized scores match within ±0.1
- ✅ Overall scores match within ±0.5

**If parity fails:** Debug mechanism weights, ensure fungivore data loaded correctly.

---

### 4.1 Phase 1: Update Rust Implementation (1-2 hours)

**Tasks:**
1. Update data.rs file paths to use Phase 4 dataset
2. Add ClimateOrganizer struct for Köppen tier organization
3. Add compute_raw_scores_for_calibration function
4. Add rand and statrs dependencies to Cargo.toml
5. Build and test with debug mode

**Verification:**
```bash
cargo build
cargo run --bin test_3_guilds_parallel
```

**Expected:** 3 guilds score successfully with new dataset

### 4.2 Phase 2: Implement Calibration Pipeline (2-3 hours)

**Tasks:**
1. Create `src/bin/calibrate_koppen_stratified.rs`
2. Implement 2-plant pair calibration (Stage 1)
3. Implement 7-plant guild calibration (Stage 2)
4. Implement percentile calculation
5. Test with debug build on small sample (100 guilds per tier)

**Verification:**
```bash
cargo run --bin calibrate_koppen_stratified
```

**Expected Output:**
```
Stage 1 (2-plant pairs): ~5s
Stage 2 (7-plant guilds): ~15s
Total time: ~20s
```

### 4.3 Phase 3: Full Calibration Run (30 minutes)

**Tasks:**
1. Build release version: `cargo build --release`
2. Run full calibration: 120K pairs + 120K guilds
3. Export normalization_params_7plant_rust.json
4. Verify JSON structure matches R output

**Verification:**
```bash
# Compare file structure
diff <(jq 'keys' normalization_params_7plant_R.json) \
     <(jq 'keys' normalization_params_7plant_rust.json)
```

### 4.4 Phase 4: 100-Guild Parity Testing (1 hour)

**Tasks:**
1. Create `src/bin/verify_100_guild_testset.rs`
2. Score 100-guild testset with Rust + Rust calibration
3. Score 100-guild testset with R + R calibration
4. Compare results (tolerance: ±0.1)

**Verification:**
```bash
# Generate R baseline
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/score_guilds_export_csv.R

# Score with Rust
cargo run --release --bin verify_100_guild_testset
```

**Expected:**
- Parity rate: >99%
- Max difference: <0.2
- Average difference: <0.05

### 4.5 Phase 5: Documentation and Commit (30 minutes)

**Tasks:**
1. Update Rust_Implementation_Verification.md with calibration results
2. Update Phase_0_Extraction_Pipeline.md with "Next Steps: Rust Calibration"
3. Git commit all changes

---

## Part 5: Performance Expectations

### 5.1 Benchmarks

**R Baseline (Current):**
```
Stage 1 (120K pairs):   ~150s
Stage 2 (120K guilds):  ~450s
Total:                  ~600s (10 minutes)
```

**Rust Projection:**
```
Stage 1 (120K pairs):   ~6s   (25× speedup)
Stage 2 (120K guilds):  ~20s  (22× speedup)
Total:                  ~26s  (23× speedup)
```

**Bottleneck Analysis:**

R bottlenecks:
- Data frame filtering (dplyr): ~30% of time
- Row-by-row iteration: ~40% of time
- Vector concatenation: ~20% of time

Rust advantages:
- Polars LazyFrame query optimization: 10× faster filtering
- Rayon parallel processing: 8× speedup on 8-core CPU
- No GC pauses: ~2× speedup from predictable memory

### 5.2 Memory Usage

**R Baseline:**
- Peak memory: ~4 GB (full plant dataset × multiple clones)
- Data frame copies: ~1 GB per tier iteration

**Rust Projection:**
- Peak memory: ~500 MB (LazyFrame schema-only loading)
- No cloning: Polars uses Arc<T> for zero-copy views
- 8× memory reduction

---

## Part 6: Risk Mitigation

### 6.1 Potential Issues

**Issue 1: Percentile calculation differences**
- Risk: Rust statrs vs R quantile() may use different interpolation
- Mitigation: Use same interpolation algorithm (linear)
- Fallback: Implement custom percentile function matching R

**Issue 2: Random sampling reproducibility**
- Risk: Rust rand vs R sample() produce different sequences
- Mitigation: Set seed for reproducibility
- Fallback: Accept different samples (calibration robust to sampling variance)

**Issue 3: New dataset column incompatibility**
- Risk: Phase 4 dataset missing required columns
- Mitigation: Verify all required columns exist before calibration
- Fallback: Regenerate Phase 4 dataset with required columns

### 6.2 Validation Strategy

**3-Level Verification:**

1. **Unit Tests** (Metric-level parity)
   - Test each metric calculation against R
   - Verify raw scores match (tolerance: ±0.001)

2. **Integration Tests** (100-guild testset)
   - Score all 100 guilds with Rust calibration
   - Compare to R baseline (tolerance: ±0.1)
   - Report mismatch rate

3. **Statistical Validation** (Calibration distribution)
   - Compare percentile distributions (Rust vs R)
   - Verify p1, p50, p99 values within ±1%
   - Check for systematic bias

---

## Part 7: Success Criteria

### 7.1 Minimum Requirements

✅ **Performance:** Rust calibration completes in <60 seconds (10× R speedup)
✅ **Parity:** 100-guild testset parity >95% (tolerance ±0.1)
✅ **Coverage:** All 6 Köppen tiers calibrated successfully
✅ **Format:** JSON output structure matches R exactly

### 7.2 Stretch Goals

🎯 **Performance:** Rust calibration completes in <30 seconds (20× R speedup)
🎯 **Parity:** 100-guild testset parity >99% (tolerance ±0.1)
🎯 **Reproducibility:** Seeded random sampling produces identical calibrations
🎯 **Documentation:** Complete API docs for calibration pipeline

---

## Part 8: Next Steps After Calibration

### 8.1 Production Integration

**Deploy Rust scorer to web API:**
- Cloud Run deployment with Rust binary
- REST API for guild scoring
- Response time: <100ms per guild
- Supports climate-stratified normalization

### 8.2 Advanced Calibration

**Tier-specific guild size calibration:**
- Current: Same calibration for 2-plant and 7-plant
- Proposed: Separate calibration per guild size (2, 3, 5, 7, 10 plants)
- Benefit: More accurate normalization for small/large guilds

**Dynamic calibration updates:**
- Monthly recalibration as new data added
- Automated pipeline: new plants → recalibrate → update API
- Version tracking for calibration parameters

---

## Appendix: Implementation Checklist

### Data Updates
- [ ] Update `src/data.rs` file paths to Phase 4 dataset
- [ ] Add `ClimateOrganizer` struct for Köppen tier organization
- [ ] Add `compute_raw_scores_for_calibration` function
- [ ] Verify all required columns exist in new dataset

### Calibration Pipeline
- [ ] Create `src/bin/calibrate_koppen_stratified.rs`
- [ ] Implement 2-plant pair sampling and scoring
- [ ] Implement 7-plant guild sampling and scoring
- [ ] Implement percentile calculation (13 bins)
- [ ] Add JSON export for calibration parameters
- [ ] Add progress reporting and timing

### Verification
- [ ] Create `src/bin/verify_100_guild_testset.rs`
- [ ] Load and parse 100-guild JSON testset
- [ ] Score all guilds with Rust calibration
- [ ] Compare to R baseline CSV
- [ ] Report parity statistics
- [ ] Generate detailed mismatch report

### Dependencies
- [ ] Add `rand = "0.8"` to Cargo.toml
- [ ] Add `statrs = "0.16"` to Cargo.toml
- [ ] Update `serde_json` to latest version
- [ ] Cargo build and test

### Testing
- [ ] Unit tests for climate organizer
- [ ] Unit tests for percentile calculation
- [ ] Integration test with 3 guilds
- [ ] Full 100-guild parity test
- [ ] Performance benchmark vs R

### Documentation
- [ ] Update Rust_Implementation_Verification.md
- [ ] Update Phase_0_Extraction_Pipeline.md
- [ ] Add calibration usage examples
- [ ] Document expected performance
- [ ] Git commit with detailed message
