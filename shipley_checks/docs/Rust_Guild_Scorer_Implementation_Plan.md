# Rust Guild Scorer Implementation Plan (Modular Architecture)

**Objective**: Build the fastest possible guild scorer in Rust following the verified modular R architecture

**Performance Target**: 20-25× faster than Python, 8-10× faster than R

**Parity Requirement**: 100% match with R modular implementation (< 0.0001 difference)

## Architecture Overview

### Design Philosophy

**Follow the R Modular Blueprint**: The R implementation (`guild_scorer_v3_modular.R`) has been refactored with comprehensive documentation for each metric. The Rust implementation will:

1. **Mirror the module structure** - One Rust module per metric with identical logic
2. **Preserve calculation steps** - Follow the documented R algorithms exactly
3. **Add Rust optimizations** - Zero-copy, parallelization, SIMD where applicable
4. **Maintain parity** - Verify against R modular results at each step

### Core Performance Principles

1. **Zero-copy data loading** - Polars LazyFrames with Arrow columnar format
2. **Parallel metric execution** - Rayon for independent metric calculation
3. **SIMD vectorization** - Auto-vectorize CSR conflicts and distance calculations
4. **Memory efficiency** - Reuse allocations, minimize cloning
5. **Batch processing** - Amortize initialization cost across many guilds

## Project Structure (Mirrors R Modules)

```
guild_scorer_rust/
├── Cargo.toml
├── src/
│   ├── lib.rs                          # Public API
│   ├── scorer.rs                       # GuildScorer coordinator struct
│   ├── data.rs                         # Polars data loading layer
│   │
│   ├── metrics/
│   │   ├── mod.rs
│   │   ├── m1_pest_pathogen_indep.rs   # Faith's PD (R: 169 lines)
│   │   ├── m2_growth_compatibility.rs  # CSR conflicts (R: 447 lines - LARGEST)
│   │   ├── m3_insect_control.rs        # Biocontrol (R: 292 lines)
│   │   ├── m4_disease_control.rs       # Disease suppression (R: 224 lines)
│   │   ├── m5_beneficial_fungi.rs      # Mycorrhizal networks (R: 97 lines)
│   │   ├── m6_structural_diversity.rs  # Vertical stratification (R: 119 lines)
│   │   └── m7_pollinator_support.rs    # Pollinator networks (R: 90 lines)
│   │
│   ├── utils/
│   │   ├── mod.rs
│   │   ├── normalization.rs            # Percentile normalization (R: 193 lines)
│   │   └── organism_counter.rs         # Shared organism counting (R: 98 lines)
│   │
│   └── phylo.rs                        # Faith's PD wrapper (C++ FFI)
│
├── benches/
│   ├── single_guild.rs                 # Single guild benchmarks
│   └── batch_guilds.rs                 # Batch processing benchmarks
│
└── tests/
    ├── parity_r.rs                     # Compare against R modular results
    └── parity_python.rs                # Compare against Python results
```

## Technology Stack

```toml
[dependencies]
# Data processing (10-100× faster than pandas)
polars = { version = "0.39", features = ["lazy", "parquet", "csv", "dtype-full"] }

# Parallel processing
rayon = "1.8"  # Data parallelism for metric calculation

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"  # Load calibration JSON

# Performance utilities
ahash = "0.8"          # Faster hashing than std HashMap
smallvec = "1.11"      # Stack-allocated vectors for organism lists
rustc-hash = "1.1"     # FxHashMap for small keys

# Math utilities
libm = "0.2"          # exp() and other math functions

# Benchmarking
criterion = { version = "0.5", features = ["html_reports"] }

[dev-dependencies]
approx = "0.5"  # Floating-point comparison for tests
```

## Metric Implementation Guide

Each metric implementation follows the R module structure:

### M1: Pest & Pathogen Independence

**R Reference**: `shipley_checks/src/Stage_4/metrics/m1_pest_pathogen_indep.R` (169 lines)

**Algorithm** (from R documentation):
1. Calculate Faith's PD using C++ binary wrapper
2. Apply exponential transformation: `pest_risk_raw = exp(-k × faiths_pd)` where k = 0.001
3. Percentile normalize with `invert = false`
4. Display score: `100 - percentile`

**Rust Implementation Strategy**:
```rust
// src/metrics/m1_pest_pathogen_indep.rs

use crate::phylo::PhyloPDCalculator;
use crate::utils::normalization::percentile_normalize;

/// M1: Pest & Pathogen Independence
///
/// Ecological Rationale:
/// - Phylogenetically diverse guilds reduce shared pest risk
/// - Host specificity: Most pests are genus/family-specific
/// - Dilution effect: Non-host plants reduce pest transmission
///
/// R reference: shipley_checks/src/Stage_4/metrics/m1_pest_pathogen_indep.R
pub fn calculate_m1(
    plant_ids: &[String],
    phylo_calculator: &PhyloPDCalculator,
    calibration: &Calibration,
) -> MetricResult {
    // Edge case: Single plant guild
    if plant_ids.len() < 2 {
        return MetricResult {
            raw: 1.0,        // Maximum risk
            normalized: 0.0, // Minimum percentile
            details: MetricDetails::M1 {
                faiths_pd: 0.0,
                note: "Single plant - no phylogenetic diversity".into(),
            },
        };
    }

    // Step 1: Calculate Faith's PD (reuse C++ binary)
    let faiths_pd = phylo_calculator.calculate_pd(plant_ids)?;

    // Step 2: Exponential transformation
    const K: f64 = 0.001;
    let pest_risk_raw = (-K * faiths_pd).exp();

    // Step 3: Percentile normalization (invert = false)
    let normalized = percentile_normalize(
        pest_risk_raw,
        "m1",
        calibration,
        false, // No inversion during normalization
    );

    MetricResult {
        raw: pest_risk_raw,
        normalized,
        details: MetricDetails::M1 {
            faiths_pd,
            note: format!(
                "Faith's PD = {:.1} MY; Pest risk = {:.3}; Percentile = {:.1}",
                faiths_pd, pest_risk_raw, normalized
            ),
        },
    }
}
```

**Performance Optimization**:
- Faith's PD: Reuse existing C++ binary (708× faster than R picante)
- No parallelization needed (single calculation per guild)
- Expected performance: ~1ms per guild

### M2: Growth Compatibility (CSR Conflicts)

**R Reference**: `shipley_checks/src/Stage_4/metrics/m2_growth_compatibility.R` (447 lines - LARGEST)

**Algorithm** (from R documentation):
1. Convert CSR scores to global percentiles (threshold: 75)
2. Detect 4 conflict types with pairwise analysis:
   - **C-C**: High-Competitive vs High-Competitive (base severity 1.0)
     * Modulation: Growth form (vine+tree: 0.2×, tree+herb: 0.4×)
     * Modulation: Height difference (<2m: 1.0×, 2-5m: 0.6×, >5m: 0.3×)
   - **C-S**: High-Competitive vs High-Stress-Tolerant (base severity 0.6)
     * CRITICAL: Light preference of S plant
       - L < 3.2 (shade-adapted): 0.0× (S WANTS shade!)
       - L > 7.47 (sun-loving): 0.9× (C shades out S)
       - L 3.2-7.47 (flexible): 0.6× with height modulation
   - **C-R**: High-Competitive vs High-Ruderal (base severity 0.8)
     * Modulation: Height difference >5m: 0.3×
   - **R-R**: High-Ruderal vs High-Ruderal (base severity 0.3)
3. Normalize by max pairs: `conflict_density = conflicts / (n × (n-1))`
4. Percentile normalize with `invert = false`
5. Display score: `100 - percentile`

**Rust Implementation Strategy**:
```rust
// src/metrics/m2_growth_compatibility.rs

use rayon::prelude::*;
use polars::prelude::*;

/// M2: Growth Compatibility (CSR Conflicts)
///
/// Ecological Rationale:
/// - CSR framework (Grime 1977): Competitive, Stress-tolerant, Ruderal strategies
/// - Conflicts arise from incompatible resource use strategies
/// - Light preference is CRITICAL for C-S conflict modulation
///
/// R reference: shipley_checks/src/Stage_4/metrics/m2_growth_compatibility.R
pub fn calculate_m2(
    guild_plants: &DataFrame,
    calibration: &Calibration,
) -> MetricResult {
    let n = guild_plants.height();

    // Extract columns (zero-copy slices)
    let csr_c = guild_plants.column("CSR_C")?.f64()?;
    let csr_s = guild_plants.column("CSR_S")?.f64()?;
    let csr_r = guild_plants.column("CSR_R")?.f64()?;
    let heights = guild_plants.column("height_m")?.f64()?;
    let growth_forms = guild_plants.column("try_growth_form")?.utf8()?;
    let light_prefs = guild_plants.column("light_pref")?.f64()?;

    // Convert to percentiles (global calibration)
    const PERCENTILE_THRESHOLD: f64 = 75.0;

    let c_percentiles: Vec<f64> = csr_c.into_iter()
        .map(|c| csr_to_percentile(c.unwrap_or(0.0), 'c', calibration))
        .collect();

    // Find high-C, high-S, high-R plants
    let high_c: Vec<usize> = c_percentiles.iter()
        .enumerate()
        .filter(|(_, p)| **p > PERCENTILE_THRESHOLD)
        .map(|(i, _)| i)
        .collect();

    // ... similar for S and R

    // PARALLEL pairwise conflict detection
    let conflicts: f64 = (0..n).into_par_iter()
        .flat_map(|i| {
            (i+1..n).into_par_iter().filter_map(move |j| {
                Some(calculate_pair_conflict(
                    i, j,
                    &c_percentiles, &s_percentiles, &r_percentiles,
                    &heights, &growth_forms, &light_prefs,
                ))
            })
        })
        .sum();

    // Normalize by guild size
    let max_pairs = (n * (n - 1)) as f64;
    let conflict_density = conflicts / max_pairs;

    // Percentile normalize (metric 'n4')
    let normalized = percentile_normalize(conflict_density, "n4", calibration, false);

    MetricResult {
        raw: conflict_density,
        normalized,
        details: MetricDetails::M2 {
            raw_conflicts: conflicts,
            conflict_density,
            high_c: high_c.len(),
            high_s: high_s.len(),
            high_r: high_r.len(),
        },
    }
}

/// Calculate conflict between two plants
/// Inlined for performance (hot path)
#[inline(always)]
fn calculate_pair_conflict(
    i: usize, j: usize,
    c_pcts: &[f64], s_pcts: &[f64], r_pcts: &[f64],
    heights: &ChunkedArray<Float64Type>,
    forms: &ChunkedArray<Utf8Type>,
    light_prefs: &ChunkedArray<Float64Type>,
) -> f64 {
    const THRESHOLD: f64 = 75.0;

    let mut conflict = 0.0;

    // Conflict 1: C-C (Competitive vs Competitive)
    if c_pcts[i] > THRESHOLD && c_pcts[j] > THRESHOLD {
        conflict += calculate_cc_conflict(i, j, heights, forms);
    }

    // Conflict 2: C-S (Competitive vs Stress-Tolerant)
    // CRITICAL: Light-based modulation
    if c_pcts[i] > THRESHOLD && s_pcts[j] > THRESHOLD {
        conflict += calculate_cs_conflict(i, j, heights, light_prefs.get(j));
    }
    if c_pcts[j] > THRESHOLD && s_pcts[i] > THRESHOLD {
        conflict += calculate_cs_conflict(j, i, heights, light_prefs.get(i));
    }

    // Conflict 3: C-R (Competitive vs Ruderal)
    if c_pcts[i] > THRESHOLD && r_pcts[j] > THRESHOLD {
        conflict += calculate_cr_conflict(i, j, heights);
    }
    // ... symmetric case

    // Conflict 4: R-R (Ruderal vs Ruderal)
    if r_pcts[i] > THRESHOLD && r_pcts[j] > THRESHOLD {
        conflict += 0.3; // Low conflict - ephemeral species
    }

    conflict
}
```

**Performance Optimization**:
- **Parallel pairwise**: Use Rayon for O(n²) comparisons
- **Early exit**: Skip pairs with no high CSR values
- **Inlined functions**: Force inline for hot path functions
- **SIMD auto-vectorization**: Compiler will vectorize numeric comparisons
- Expected performance: ~2-5ms per guild (10× faster than Python)

### M3-M7: Remaining Metrics

Each metric follows the same pattern:

**M3: Insect Control** (`m3_insect_control.rs`)
- R reference: 292 lines with 3 biocontrol mechanisms
- Optimization: Parallel pairwise analysis + HashMap lookups with ahash

**M4: Disease Control** (`m4_disease_control.rs`)
- R reference: 224 lines with 2 mechanisms
- Optimization: Same as M3, reuse organism counting logic

**M5: Beneficial Fungi** (`m5_beneficial_fungi.rs`)
- R reference: 97 lines (simplest metric)
- Optimization: Shared organism counter with smallvec for stack allocation

**M6: Structural Diversity** (`m6_structural_diversity.rs`)
- R reference: 119 lines with light validation
- Optimization: Vectorized height difference calculations

**M7: Pollinator Support** (`m7_pollinator_support.rs`)
- R reference: 90 lines with quadratic weighting
- Optimization: Shared organism counter + quadratic formula

## Utility Modules

### Normalization Module

**R Reference**: `shipley_checks/src/Stage_4/utils/normalization.R` (193 lines)

```rust
// src/utils/normalization.rs

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Deserialize)]
pub struct Calibration {
    tiers: HashMap<String, TierCalibration>,
    csr_global: Option<CsrCalibration>,
}

#[derive(Debug, Deserialize)]
struct TierCalibration {
    m1: PercentileParams,
    n4: PercentileParams,
    p1: PercentileParams,
    p2: PercentileParams,
    p3: PercentileParams,
    p5: PercentileParams,
    p6: PercentileParams,
}

#[derive(Debug, Deserialize)]
struct PercentileParams {
    p1: f64,
    p5: f64,
    p10: f64,
    p20: f64,
    p30: f64,
    p40: f64,
    p50: f64,
    p60: f64,
    p70: f64,
    p80: f64,
    p90: f64,
    p95: f64,
    p99: f64,
}

/// Percentile normalize using linear interpolation
///
/// Algorithm (from R):
/// 1. Find bracketing percentiles [pi, pi+1] where values[pi] <= raw <= values[pi+1]
/// 2. Linear interpolation: percentile = pi + fraction × (pi+1 - pi)
/// 3. If invert = true, apply: percentile = 100 - percentile
///
/// R reference: shipley_checks/src/Stage_4/utils/normalization.R::percentile_normalize
pub fn percentile_normalize(
    raw_value: f64,
    metric_name: &str,
    calibration: &Calibration,
    invert: bool,
) -> f64 {
    const PERCENTILES: [f64; 13] = [1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0,
                                     60.0, 70.0, 80.0, 90.0, 95.0, 99.0];

    let tier = calibration.tiers.get(&calibration.active_tier)
        .expect("Invalid tier");

    let params = match metric_name {
        "m1" => &tier.m1,
        "n4" => &tier.n4,
        "p1" => &tier.p1,
        "p2" => &tier.p2,
        "p3" => &tier.p3,
        "p5" => &tier.p5,
        "p6" => &tier.p6,
        _ => panic!("Unknown metric: {}", metric_name),
    };

    let values = [
        params.p1, params.p5, params.p10, params.p20, params.p30,
        params.p40, params.p50, params.p60, params.p70, params.p80,
        params.p90, params.p95, params.p99,
    ];

    // Edge cases
    if raw_value <= values[0] {
        return if invert { 100.0 } else { 0.0 };
    }
    if raw_value >= values[12] {
        return if invert { 0.0 } else { 100.0 };
    }

    // Linear interpolation
    for i in 0..12 {
        if values[i] <= raw_value && raw_value <= values[i + 1] {
            let fraction = (raw_value - values[i]) / (values[i + 1] - values[i]);
            let percentile = PERCENTILES[i] + fraction * (PERCENTILES[i + 1] - PERCENTILES[i]);

            return if invert { 100.0 - percentile } else { percentile };
        }
    }

    50.0 // Fallback (should never reach)
}
```

### Organism Counter Module

**R Reference**: `shipley_checks/src/Stage_4/utils/shared_organism_counter.R` (98 lines)

```rust
// src/utils/organism_counter.rs

use rustc_hash::FxHashMap;
use smallvec::SmallVec;

/// Count organisms shared across plants
///
/// Returns a map of organism_id → count (number of plants hosting it)
///
/// R reference: shipley_checks/src/Stage_4/utils/shared_organism_counter.R
pub fn count_shared_organisms(
    df: &DataFrame,
    plant_ids: &[String],
    columns: &[&str],
) -> FxHashMap<String, usize> {
    let mut counts: FxHashMap<String, usize> = FxHashMap::default();

    // Filter to guild plants
    let guild_df = df.filter(&col("plant_wfo_id").is_in(plant_ids))?;

    for row in guild_df.iter() {
        // Aggregate organisms from all specified columns
        let mut plant_organisms: SmallVec<[String; 16]> = SmallVec::new();

        for col_name in columns {
            if let Some(org_list) = row.get(col_name) {
                // Parse pipe-separated string
                for org in org_list.split('|').filter(|s| !s.is_empty()) {
                    plant_organisms.push(org.to_string());
                }
            }
        }

        // Deduplicate and count
        plant_organisms.sort_unstable();
        plant_organisms.dedup();

        for org in plant_organisms {
            *counts.entry(org).or_insert(0) += 1;
        }
    }

    counts
}
```

## Data Loading Layer

**Optimization**: Lazy evaluation with Polars

```rust
// src/data.rs

use polars::prelude::*;
use std::path::Path;

pub struct GuildScorerData {
    plants: LazyFrame,
    organisms: LazyFrame,
    fungi: LazyFrame,
}

impl GuildScorerData {
    pub fn load(data_dir: &Path) -> Result<Self> {
        Ok(Self {
            // Lazy loading - only loads when collect() is called
            plants: LazyFrame::scan_parquet(
                data_dir.join("stage3/bill_with_csr_ecoservices_koppen_11711.parquet"),
                Default::default(),
            )?,

            organisms: LazyCsvReader::new(
                data_dir.join("validation/organism_profiles_python_VERIFIED.csv")
            ).finish()?,

            fungi: LazyCsvReader::new(
                data_dir.join("validation/fungal_guilds_python_VERIFIED.csv")
            ).finish()?,
        })
    }

    /// Filter plants by WFO IDs with push-down predicate
    pub fn filter_plants(&self, plant_ids: &[String]) -> DataFrame {
        self.plants
            .filter(col("wfo_taxon_id").is_in(lit(Series::new("ids", plant_ids))))
            .select(&[
                col("wfo_taxon_id"),
                col("wfo_scientific_name"),
                col("height_m"),
                col("try_growth_form"),
                col("CSR_C").alias("CSR_C"),
                col("CSR_S").alias("CSR_S"),
                col("CSR_R").alias("CSR_R"),
                col("light_pref"),
                // Köppen tiers...
            ])
            .collect()
            .unwrap()
    }
}
```

**Expected speedup**: 5-10× faster than Python DuckDB for data filtering

## Main Scorer Struct (Coordinator)

**Mirrors R**: `guild_scorer_v3_modular.R` (379 lines)

```rust
// src/scorer.rs

use rayon::prelude::*;

pub struct GuildScorer {
    data: GuildScorerData,
    calibration: Calibration,
    phylo_calculator: PhyloPDCalculator,
}

impl GuildScorer {
    pub fn new(
        data_dir: &Path,
        calibration_type: &str,
        climate_tier: &str,
    ) -> Result<Self> {
        // Load calibration JSON
        let calibration = Calibration::load(
            data_dir.join(format!("normalization_params_{}.json", calibration_type))
        )?;

        Ok(Self {
            data: GuildScorerData::load(data_dir)?,
            calibration,
            phylo_calculator: PhyloPDCalculator::new()?,
        })
    }

    /// Score a guild using all 7 metrics
    ///
    /// R reference: shipley_checks/src/Stage_4/guild_scorer_v3_modular.R::score_guild
    pub fn score_guild(&self, plant_ids: &[String]) -> Result<GuildScore> {
        // Load guild data once
        let plants = self.data.filter_plants(plant_ids);
        let organisms = self.data.filter_organisms(plant_ids);
        let fungi = self.data.filter_fungi(plant_ids);

        // Check climate compatibility
        self.check_climate_compatibility(&plants)?;

        // PARALLEL metric calculation (Rayon)
        let metric_results: Vec<MetricResult> = vec![
            || metrics::m1::calculate_m1(plant_ids, &self.phylo_calculator, &self.calibration),
            || metrics::m2::calculate_m2(&plants, &self.calibration),
            || metrics::m3::calculate_m3(plant_ids, &organisms, &fungi, &self.calibration),
            || metrics::m4::calculate_m4(plant_ids, &fungi, &self.calibration),
            || metrics::m5::calculate_m5(plant_ids, &fungi, &self.calibration),
            || metrics::m6::calculate_m6(&plants, &self.calibration),
            || metrics::m7::calculate_m7(plant_ids, &organisms, &self.calibration),
        ]
        .par_iter()
        .map(|f| f())
        .collect::<Result<Vec<_>>>()?;

        // Apply final inversions for M1 and M2 (matches R line 268-269)
        let metrics = vec![
            100.0 - metric_results[0].normalized, // M1: 100 - percentile
            100.0 - metric_results[1].normalized, // M2: 100 - percentile
            metric_results[2].normalized,          // M3-M7: direct percentile
            metric_results[3].normalized,
            metric_results[4].normalized,
            metric_results[5].normalized,
            metric_results[6].normalized,
        ];

        // Overall score (simple average) - matches R line 278
        let overall_score = metrics.iter().sum::<f64>() / 7.0;

        Ok(GuildScore {
            overall_score,
            metrics,
            raw_scores: metric_results.iter().map(|r| r.raw).collect(),
            details: metric_results.into_iter().map(|r| r.details).collect(),
        })
    }
}
```

**Expected speedup**: 3-5× from parallel metric calculation on 8+ core machines

## Parity Testing

**Critical**: Verify against R modular implementation at each step

```rust
// tests/parity_r.rs

#[test]
fn test_parity_with_r_modular() {
    let scorer = GuildScorer::new(
        Path::new("shipley_checks/stage4"),
        "7plant",
        "tier_3_humid_temperate",
    ).unwrap();

    // Test guilds from commit 3f1a535
    let guilds = [
        (
            "forest_garden",
            vec!["wfo-0000832453", "wfo-0000649136", "wfo-0000642673",
                 "wfo-0000984977", "wfo-0000241769", "wfo-0000092746",
                 "wfo-0000690499"],
            90.467710,
        ),
        (
            "competitive_clash",
            vec!["wfo-0000757278", "wfo-0000944034", "wfo-0000186915",
                 "wfo-0000421791", "wfo-0000418518", "wfo-0000841021",
                 "wfo-0000394258"],
            55.441621,
        ),
        (
            "stress_tolerant",
            vec!["wfo-0000721951", "wfo-0000955348", "wfo-0000901050",
                 "wfo-0000956222", "wfo-0000777518", "wfo-0000349035",
                 "wfo-0000209726"],
            45.442341,
        ),
    ];

    for (name, plant_ids, expected) in guilds {
        let result = scorer.score_guild(&plant_ids.iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap();

        let diff = (result.overall_score - expected).abs();
        assert!(
            diff < 0.0001,
            "Guild {}: Expected {}, got {} (diff: {})",
            name, expected, result.overall_score, diff
        );

        println!("✅ {}: {:.6} (diff: {:.6})", name, result.overall_score, diff);
    }
}
```

## Performance Benchmarks

```rust
// benches/single_guild.rs

use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn benchmark_guild_scoring(c: &mut Criterion) {
    let scorer = GuildScorer::new(/* ... */).unwrap();

    let guild = vec![
        "wfo-0000832453", "wfo-0000649136", "wfo-0000642673",
        "wfo-0000984977", "wfo-0000241769", "wfo-0000092746",
        "wfo-0000690499"
    ];

    c.bench_function("score_single_guild", |b| {
        b.iter(|| scorer.score_guild(black_box(&guild)))
    });
}

criterion_group!(benches, benchmark_guild_scoring);
criterion_main!(benches);
```

**Expected results**:
```
score_single_guild    time: [8.234 ms 8.456 ms 8.698 ms]
                      thrpt: [114.98 guilds/s 118.24 guilds/s 121.46 guilds/s]
```

**Comparison**:
- Python: ~230ms per guild → **27× speedup**
- R: ~86ms per guild → **10× speedup**

## Implementation Phases

### Phase 1: Foundation (Day 1)
- [x] Set up Cargo project with Polars, Rayon, serde
- [ ] Implement data loading with Polars LazyFrames
- [ ] Load calibration parameters from JSON
- [ ] Create GuildScorer coordinator struct
- [ ] Test data loading and filtering

### Phase 2: Utility Modules (Day 2)
- [ ] Implement `utils/normalization.rs` (follow R: 193 lines)
  - percentile_normalize function
  - csr_to_percentile function
  - Test against R outputs
- [ ] Implement `utils/organism_counter.rs` (follow R: 98 lines)
  - count_shared_organisms function
  - Test with M5/M7 data

### Phase 3: Core Metrics (Day 3-4)
- [ ] **M1: Pest Independence** (follow R: 169 lines)
  - Faith's PD wrapper (reuse C++ binary)
  - Exponential transformation
  - Parity test vs R
- [ ] **M2: CSR Compatibility** (follow R: 447 lines - LARGEST)
  - CSR percentile conversion
  - 4 conflict types with full modulation
  - Parallel pairwise analysis
  - Parity test vs R (most complex metric)
- [ ] **M3: Insect Control** (follow R: 292 lines)
  - 3 biocontrol mechanisms
  - Pairwise protection analysis
  - Parity test vs R
- [ ] **M4: Disease Control** (follow R: 224 lines)
  - 2 disease suppression mechanisms
  - Parity test vs R
- [ ] **M5: Beneficial Fungi** (follow R: 97 lines)
  - Shared organism counting
  - Network + coverage score
  - Parity test vs R
- [ ] **M6: Structural Diversity** (follow R: 119 lines)
  - Light-validated stratification
  - Form diversity
  - Parity test vs R
- [ ] **M7: Pollinator Support** (follow R: 90 lines)
  - Shared pollinators with quadratic weighting
  - Parity test vs R

### Phase 4: Integration & Optimization (Day 5)
- [ ] Integrate all metrics into GuildScorer
- [ ] Implement parallel metric execution with Rayon
- [ ] Full parity test: 3 guilds × 7 metrics
- [ ] Optimize hot paths (M2 conflict detection)
- [ ] Memory profiling and optimization

### Phase 5: Benchmarking (Day 6)
- [ ] Single guild benchmarks (criterion.rs)
- [ ] Batch guild benchmarks (100+ guilds)
- [ ] Flamegraph profiling
- [ ] Compare vs Python and R
- [ ] Document speedup results

### Phase 6: Polish (Day 7)
- [ ] Error handling and validation
- [ ] CLI interface (optional)
- [ ] Documentation with examples
- [ ] Final parity verification

## Expected Performance

| Operation | Python | R | Rust (Target) | Speedup vs Python |
|-----------|--------|---|---------------|-------------------|
| **Initialization** | 5ms | 540ms | 2ms | 2.5× |
| **Score 1 guild** | 230ms | 86ms | 10ms | **23×** |
| **Score 3 guilds** | 691ms | 259ms | 30ms | **23×** |
| **Score 100 guilds** | ~23s | ~8.6s | ~0.5s | **46×** |

**Key Performance Gains**:
1. **Data loading**: Polars LazyFrame (5-10× faster than DuckDB)
2. **Parallel metrics**: Rayon (3-5× on 8-core)
3. **M2 optimization**: SIMD + parallel pairwise (10-20×)
4. **Batch processing**: Amortized initialization (50-100×)

## Success Criteria

1. ✅ **100% Parity with R**: Maximum difference < 0.0001 on all test guilds
2. ✅ **20-25× faster than Python**: Single guild scoring
3. ✅ **8-10× faster than R**: Single guild scoring
4. ✅ **Sub-millisecond per guild**: Batch mode (100+ guilds)
5. ✅ **Zero panics**: All errors handled gracefully
6. ✅ **Memory efficient**: < 50MB for single guild scoring

## Safety Considerations

1. **No unsafe code** unless absolutely necessary (Polars handles FFI)
2. **Bounds checking** - Rust prevents index errors
3. **Type safety** - No silent type coercion
4. **Error propagation** - Result types, not panics
5. **Data validation** - Check for missing plant IDs, invalid values

## Profiling Tools

```bash
# Criterion benchmarks (statistical analysis)
cargo bench

# Flamegraph profiling (identify hot spots)
cargo install flamegraph
cargo flamegraph --bench single_guild

# Memory profiling
valgrind --tool=massif target/release/guild_scorer

# Assembly inspection (verify SIMD)
cargo rustc --release -- --emit asm

# Perf profiling (Linux)
perf record target/release/guild_scorer
perf report
```

## References

**R Modular Implementation**:
- Main: `shipley_checks/src/Stage_4/guild_scorer_v3_modular.R`
- Metrics: `shipley_checks/src/Stage_4/metrics/*.R`
- Utils: `shipley_checks/src/Stage_4/utils/*.R`
- Documentation: `shipley_checks/docs/Stage_4_R_Modularization.md`

**Python Implementation**:
- `src/Stage_4/guild_scorer_v3.py`

**Parity Results**:
- `shipley_checks/docs/Stage_4_Dual_Verification_Pipeline.md`
