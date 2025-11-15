# Rust Guild Scorer: Memory Optimization Implementation Plan

**Date**: 2025-11-13
**Objective**: Reduce DataFrame cloning and implement LazyFrame loading for Cloud Run deployment
**Expected Impact**: 60-70% memory reduction, 30-40% faster cold starts

## Current Architecture Analysis

### Memory Flow (Current)

```
GuildScorer::new()
├── Load plants.parquet → DataFrame (73 MB)
├── Load organisms.parquet → DataFrame (4.7 MB)
└── Load fungi.parquet → DataFrame (2.8 MB)
Total: ~80 MB in memory

score_guild(plant_ids)
├── Filter plants → Clone 1 (43 KB × 782 cols)
├── calculate_m1() → may clone → Clone 2
├── calculate_m2() → may clone → Clone 3
├── calculate_m3()
│   ├── Filter organisms → Clone 4
│   └── Filter fungi → Clone 5
├── calculate_m4() → Filter fungi → Clone 6
├── calculate_m5() → Filter fungi → Clone 7
├── calculate_m6() → may clone → Clone 8
└── calculate_m7() → Filter organisms → Clone 9

Total clones per guild: 6-9 full DataFrame copies
Memory multiplier: 6-9×
```

### Target Architecture

```
GuildScorer::new()
├── Scan plants.parquet → LazyFrame (schema only, ~50 KB)
├── Scan organisms.parquet → LazyFrame (schema only, ~30 KB)
└── Scan fungi.parquet → LazyFrame (schema only, ~20 KB)
Total: ~100 KB in memory

score_guild(plant_ids)
├── Build plants_lazy.filter() → Query plan (no execution)
├── calculate_m1(&plants_lazy, plant_ids)
│   └── Select only ["wfo_id"] → collect() → Materialize 7 × 1 = 7 cells
├── calculate_m2(&plants_lazy)
│   └── Select only ["c_percentile", "s_percentile", ...] → collect() → 7 × 7 = 49 cells
├── calculate_m3(&plants_lazy, &organisms_lazy, plant_ids)
│   ├── organisms_lazy.filter().select() → collect() → Only needed columns
│   └── No cloning, just query plans
├── ... similar for M4-M7

Total memory per guild: ~5-10 KB (only materialized projections)
Memory multiplier: 1× (no clones, only projections)
```

## Implementation Phases

### Phase 0: Preparation (30 minutes)

**Goal**: Set up testing infrastructure and baseline measurements

#### 0.1: Create Memory Profiling Test

```bash
# File: shipley_checks/src/Stage_4/guild_scorer_rust/src/bin/test_memory_baseline.rs
```

```rust
use guild_scorer_rust::*;
use std::time::Instant;

fn main() -> anyhow::Result<()> {
    println!("=== MEMORY BASELINE TEST ===\n");

    // Measure initialization memory
    let init_start = Instant::now();
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")?;
    let init_time = init_start.elapsed();

    println!("Initialization: {:?}", init_time);
    println!("Press Enter to continue (check memory usage now)...");
    let mut input = String::new();
    std::io::stdin().read_line(&mut input)?;

    // Test guilds
    let guilds = vec![
        ("Forest Garden", vec![
            "wfo-0000832453", "wfo-0000649136", "wfo-0000642673",
            "wfo-0000984977", "wfo-0000241769", "wfo-0000092746",
            "wfo-0000690499"
        ]),
    ];

    for (name, plant_ids) in guilds {
        let ids: Vec<String> = plant_ids.iter().map(|s| s.to_string()).collect();

        println!("\nScoring: {}", name);
        let score_start = Instant::now();
        let result = scorer.score_guild(&ids)?;
        let score_time = score_start.elapsed();

        println!("  Score: {:.2}", result.overall);
        println!("  Time: {:?}", score_time);
        println!("  Press Enter for next (check memory)...");
        std::io::stdin().read_line(&mut input)?;
    }

    Ok(())
}
```

#### 0.2: Add to Cargo.toml

```toml
[[bin]]
name = "test_memory_baseline"
path = "src/bin/test_memory_baseline.rs"

[[bin]]
name = "test_memory_optimized"
path = "src/bin/test_memory_optimized.rs"
```

#### 0.3: Build and Run Baseline

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust

# Build
cargo build --release --bin test_memory_baseline

# Run with memory monitoring
/usr/bin/time -v ./target/release/test_memory_baseline 2>&1 | tee baseline_memory.log

# In another terminal, monitor with:
# watch -n 1 'ps aux | grep test_memory_baseline'
```

#### 0.4: Record Baseline Metrics

Create file: `shipley_checks/src/Stage_4/guild_scorer_rust/OPTIMIZATION_METRICS.md`

```markdown
# Memory Optimization Metrics

## Baseline (Before Optimization)

**Date**: 2025-11-13

### Initialization
- Time: ___ ms
- Peak RSS: ___ MB
- Working set: ___ MB

### Guild Scoring (Forest Garden)
- Time: ___ ms
- Peak RSS: ___ MB
- Memory delta: ___ MB

## Target (After Optimization)

### Initialization
- Time: < 500 ms (19× faster)
- Peak RSS: < 150 MB (50% reduction)

### Guild Scoring
- Time: < 4 ms (1.5× faster)
- Peak RSS: < 200 MB (no growth)
```

---

### Phase 1: Data Loading Module (2 hours)

**Goal**: Convert `data.rs` to use LazyFrame for schema-only loading

#### 1.1: Update GuildData Structure

**File**: `src/data.rs`

**Current**:
```rust
pub struct GuildData {
    pub plants: DataFrame,
    pub organisms: DataFrame,
    pub fungi: DataFrame,
    pub herbivore_predators: FxHashMap<String, Vec<String>>,
    pub insect_parasites: FxHashMap<String, Vec<String>>,
    pub pathogen_antagonists: FxHashMap<String, Vec<String>>,
}
```

**Change to**:
```rust
pub struct GuildData {
    // Keep DataFrames for backward compatibility during migration
    pub plants: DataFrame,
    pub organisms: DataFrame,
    pub fungi: DataFrame,

    // Add LazyFrames for optimized access
    pub plants_lazy: LazyFrame,
    pub organisms_lazy: LazyFrame,
    pub fungi_lazy: LazyFrame,

    // Hash maps stay the same (already optimal)
    pub herbivore_predators: FxHashMap<String, Vec<String>>,
    pub insect_parasites: FxHashMap<String, Vec<String>>,
    pub pathogen_antagonists: FxHashMap<String, Vec<String>>,
}
```

#### 1.2: Update Load Functions

**Current pattern**:
```rust
fn load_plants_parquet(path: &str) -> Result<DataFrame> {
    let df = LazyFrame::scan_parquet(path, Default::default())?
        .select(&[/* all columns */])
        .collect()?;  // ← Materializes everything immediately
    Ok(df)
}
```

**New pattern**:
```rust
fn load_plants_lazy(path: &str) -> Result<(DataFrame, LazyFrame)> {
    // Scan parquet - only loads schema
    let lazy = LazyFrame::scan_parquet(path, Default::default())?;

    // For backward compatibility, materialize a minimal DataFrame
    // (Later phases will eliminate this)
    let df = lazy
        .clone()
        .select(&[
            col("wfo_id"),
            col("wfo_scientific_name"),
            // Only essential columns for initialization
        ])
        .collect()?;

    Ok((df, lazy))
}
```

#### 1.3: Update GuildData::load()

**Change**:
```rust
impl GuildData {
    pub fn load() -> Result<Self> {
        println!("Loading datasets (LazyFrame schema-only mode)...");

        // Load with lazy frames
        let (plants_df, plants_lazy) = Self::load_plants_lazy(
            "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_rust.parquet"
        )?;

        let (organisms_df, organisms_lazy) = Self::load_organisms_lazy(
            "shipley_checks/validation/organism_profiles_pure_rust.parquet"
        )?;

        let (fungi_df, fungi_lazy) = Self::load_fungi_lazy(
            "shipley_checks/validation/fungal_guilds_pure_rust.parquet"
        )?;

        // Lookup tables stay the same (already efficient)
        let herbivore_predators = Self::load_lookup_table(
            "shipley_checks/validation/herbivore_predators_pure_rust.parquet",
            "herbivore",
            "predators",
        )?;

        // ... other lookups

        println!("  Plants lazy: schema only");
        println!("  Organisms lazy: schema only");
        println!("  Fungi lazy: schema only");
        println!("  Herbivore predators: {}", herbivore_predators.len());

        Ok(GuildData {
            plants: plants_df,
            organisms: organisms_df,
            fungi: fungi_df,
            plants_lazy,
            organisms_lazy,
            fungi_lazy,
            herbivore_predators,
            insect_parasites,
            pathogen_antagonists,
        })
    }
}
```

#### 1.4: Test Phase 1

```bash
# Build
cargo build --release --bin test_3_guilds

# Run existing test (should still pass with backward compatibility)
./target/release/test_3_guilds

# Expected output:
# ✅ PARITY ACHIEVED: 100% match with R implementation
# (Times should be similar - no breaking changes yet)
```

**Verification**:
- [ ] All 3 guilds score correctly
- [ ] Parity maintained (difference < 0.0001)
- [ ] No panics or errors
- [ ] Memory usage similar (backward compatibility mode)

---

### Phase 2: M1 Metric Optimization (1 hour)

**Goal**: Convert M1 to use LazyFrame, eliminate cloning

#### 2.1: Update calculate_m1 Signature

**File**: `src/metrics/m1_pest_pathogen_indep.rs`

**Current**:
```rust
pub fn calculate_m1(
    guild_plants: &DataFrame,
    plant_ids: &[String],
    pd_calculator: &PhyloPDCalculator,
    normalizer: &Normalizer,
) -> Result<M1Result>
```

**Change to**:
```rust
pub fn calculate_m1(
    plants_lazy: &LazyFrame,           // ← Take lazy frame
    plant_ids: &[String],
    pd_calculator: &PhyloPDCalculator,
    normalizer: &Normalizer,
) -> Result<M1Result>
```

#### 2.2: Update M1 Implementation

**Current pattern** (conceptual):
```rust
pub fn calculate_m1(...) -> Result<M1Result> {
    // Works on materialized DataFrame
    let tips: Vec<String> = guild_plants
        .column("wfo_id")?
        .utf8()?
        .into_iter()
        .filter_map(|opt_id| {
            opt_id.and_then(|id| pd_calculator.wfo_to_tip.get(id).cloned())
        })
        .collect();

    // ... rest of logic
}
```

**New pattern**:
```rust
pub fn calculate_m1(
    plants_lazy: &LazyFrame,
    plant_ids: &[String],
    pd_calculator: &PhyloPDCalculator,
    normalizer: &Normalizer,
) -> Result<M1Result> {
    // Build query plan
    let guild_plants_filtered = plants_lazy
        .clone()
        .filter(col("wfo_id").is_in(lit(plant_ids)));

    // Materialize ONLY the wfo_id column
    let wfo_ids = guild_plants_filtered
        .select(&[col("wfo_id")])
        .collect()?;

    // Extract tree tips (minimal data materialized)
    let tips: Vec<String> = wfo_ids
        .column("wfo_id")?
        .utf8()?
        .into_iter()
        .filter_map(|opt_id| {
            opt_id.and_then(|id| pd_calculator.wfo_to_tip.get(id).cloned())
        })
        .collect();

    // Rest of M1 logic unchanged
    if tips.is_empty() {
        return Ok(M1Result {
            faiths_pd: 0.0,
            pest_risk: 100.0,
            normalized: 100.0,
        });
    }

    if tips.len() == 1 {
        return Ok(M1Result {
            faiths_pd: 0.0,
            pest_risk: 100.0,
            normalized: 100.0,
        });
    }

    let faiths_pd = pd_calculator.calculate_faiths_pd(&tips)?;
    let k = 0.001;
    let pest_risk = 100.0 * (-k * faiths_pd).exp();
    let normalized = normalizer.normalize("m1", pest_risk)?;

    Ok(M1Result {
        faiths_pd,
        pest_risk,
        normalized,
    })
}
```

**Key changes**:
- Takes `LazyFrame` instead of `DataFrame`
- Filters using Polars expressions (pushed into Parquet reader)
- Materializes ONLY `wfo_id` column (not all 782 columns)
- No cloning of full DataFrames

#### 2.3: Update Scorer to Call New M1

**File**: `src/scorer.rs`

**Current**:
```rust
let guild_plants = /* filter plants DataFrame */;
let m1 = calculate_m1(&guild_plants, plant_ids, &self.pd_calculator, &self.normalizer)?;
```

**Change to**:
```rust
// No filtering here - pass lazy frame directly
let m1 = calculate_m1(
    &self.data.plants_lazy,  // ← Pass lazy frame
    plant_ids,
    &self.pd_calculator,
    &self.normalizer
)?;
```

#### 2.4: Test Phase 2

```bash
# Build
cargo build --release --bin test_3_guilds

# Run test
./target/release/test_3_guilds

# Check M1 values specifically
```

**Verification**:
- [ ] M1 scores match baseline exactly (all 3 guilds)
- [ ] No performance regression
- [ ] Memory usage reduced slightly

**Expected M1 scores**:
- Forest Garden: 58.6
- Competitive Clash: 70.4
- Stress-Tolerant: 36.7

---

### Phase 3: M2 Metric Optimization (1 hour)

**Goal**: Eliminate cloning in CSR conflict detection

#### 3.1: Update calculate_m2 Signature

**File**: `src/metrics/m2_growth_compatibility.rs`

**Current**:
```rust
pub fn calculate_m2(
    guild_plants: &DataFrame,
    normalizer: &Normalizer,
) -> Result<M2Result>
```

**Change to**:
```rust
pub fn calculate_m2(
    plants_lazy: &LazyFrame,
    plant_ids: &[String],
    normalizer: &Normalizer,
) -> Result<M2Result>
```

#### 3.2: Update M2 Implementation

**Current pattern** (conceptual):
```rust
pub fn calculate_m2(guild_plants: &DataFrame, normalizer: &Normalizer) -> Result<M2Result> {
    // Parse CSR strategies
    let plants: Vec<PlantCSR> = (0..guild_plants.height())
        .map(|i| {
            // Extract from DataFrame rows
            let c = guild_plants.column("c_percentile")?.f64()?.get(i);
            let s = guild_plants.column("s_percentile")?.f64()?.get(i);
            // ... extract multiple columns
        })
        .collect();

    // Detect conflicts...
}
```

**New pattern**:
```rust
pub fn calculate_m2(
    plants_lazy: &LazyFrame,
    plant_ids: &[String],
    normalizer: &Normalizer,
) -> Result<M2Result> {
    // Materialize ONLY columns needed for M2
    let guild_csr = plants_lazy
        .clone()
        .filter(col("wfo_id").is_in(lit(plant_ids)))
        .select(&[
            col("wfo_id"),
            col("c_percentile"),
            col("s_percentile"),
            col("r_percentile"),
            col("growth_form"),
            col("height_m"),
            col("light_pref"),
        ])
        .collect()?;  // Materialize only 7 columns, not 782

    // Parse CSR strategies (same logic, smaller DataFrame)
    let c_col = guild_csr.column("c_percentile")?.f64()?;
    let s_col = guild_csr.column("s_percentile")?.f64()?;
    let r_col = guild_csr.column("r_percentile")?.f64()?;
    let form_col = guild_csr.column("growth_form")?.utf8()?;
    let height_col = guild_csr.column("height_m")?.f64()?;
    let light_col = guild_csr.column("light_pref")?.utf8()?;

    let plants: Vec<PlantCSR> = (0..guild_csr.height())
        .map(|i| {
            PlantCSR {
                id: i,
                c_percentile: c_col.get(i).unwrap_or(0.0),
                s_percentile: s_col.get(i).unwrap_or(0.0),
                r_percentile: r_col.get(i).unwrap_or(0.0),
                growth_form: form_col.get(i).unwrap_or("").to_string(),
                height_m: height_col.get(i).unwrap_or(0.0),
                light_pref: light_col.get(i).unwrap_or("").to_string(),
            }
        })
        .collect();

    // Rest of M2 logic unchanged (conflict detection, etc.)
    let conflicts = detect_all_conflicts(&plants);
    let n_plants = plants.len();
    let max_pairs = n_plants * (n_plants - 1) / 2;

    let conflict_density = if max_pairs > 0 {
        conflicts.total_score / max_pairs as f64
    } else {
        0.0
    };

    let normalized = normalizer.normalize("m2", conflict_density)?;

    Ok(M2Result {
        conflict_density,
        normalized,
        n_conflicts: conflicts.count,
        high_c: plants.iter().filter(|p| p.c_percentile > 0.6).count(),
        high_r: plants.iter().filter(|p| p.r_percentile > 0.6).count(),
    })
}
```

**Memory savings**:
- Before: 7 rows × 782 cols = 5,474 cells materialized
- After: 7 rows × 7 cols = 49 cells materialized
- **111× less data loaded into memory**

#### 3.3: Update Scorer Call

**File**: `src/scorer.rs`

**Change**:
```rust
let m2 = calculate_m2(
    &self.data.plants_lazy,
    plant_ids,
    &self.normalizer
)?;
```

#### 3.4: Test Phase 3

```bash
cargo build --release --bin test_3_guilds
./target/release/test_3_guilds
```

**Verification**:
- [ ] M2 scores match exactly
- [ ] Conflict detection still correct
- [ ] Memory usage reduced

**Expected M2 scores**:
- Forest Garden: 100.0
- Competitive Clash: 2.0
- Stress-Tolerant: 100.0

---

### Phase 4: M3/M4/M5/M7 - Organism/Fungi Filtering (2 hours)

**Goal**: Eliminate duplicate filtering of organisms and fungi DataFrames

#### 4.1: Current Problem

```rust
// M3 calls filter_to_guild
let guild_organisms = filter_to_guild(organisms_df, plant_ids, "plant_wfo_id")?;  // Clone 1
let guild_fungi = filter_to_guild(fungi_df, plant_ids, "plant_wfo_id")?;          // Clone 2

// M4 calls filter_to_guild again
let guild_fungi = filter_to_guild(fungi_df, plant_ids, "plant_wfo_id")?;          // Clone 3 (duplicate!)

// M5 calls filter_to_guild again
let guild_fungi = filter_to_guild(fungi_df, plant_ids, "plant_wfo_id")?;          // Clone 4 (duplicate!)

// M7 calls filter_to_guild
let guild_organisms = filter_to_guild(organisms_df, plant_ids, "plant_wfo_id")?;  // Clone 5 (duplicate!)
```

**Problem**: Same filtering operation repeated 5 times, creating 5 clones!

#### 4.2: Solution: Pre-filter in Scorer

**File**: `src/scorer.rs`

**Add helper method**:
```rust
impl GuildScorer {
    /// Build filtered LazyFrames for guild organisms and fungi
    /// Returns query plans (not materialized)
    fn build_guild_lazy_frames(
        &self,
        plant_ids: &[String],
    ) -> (LazyFrame, LazyFrame) {
        // Build query plans (NO execution)
        let guild_organisms_lazy = self.data.organisms_lazy
            .clone()
            .filter(col("plant_wfo_id").is_in(lit(plant_ids)));

        let guild_fungi_lazy = self.data.fungi_lazy
            .clone()
            .filter(col("plant_wfo_id").is_in(lit(plant_ids)));

        (guild_organisms_lazy, guild_fungi_lazy)
    }
}
```

#### 4.3: Update M3 Signature and Implementation

**File**: `src/metrics/m3_insect_control.rs`

**Current**:
```rust
pub fn calculate_m3(
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    fungi_df: &DataFrame,
    plant_ids: &[String],
    herbivore_predators: &FxHashMap<String, Vec<String>>,
    insect_parasites: &FxHashMap<String, Vec<String>>,
    normalizer: &Normalizer,
) -> Result<M3Result>
```

**Change to**:
```rust
pub fn calculate_m3(
    organisms_lazy: &LazyFrame,        // ← Already filtered to guild
    fungi_lazy: &LazyFrame,            // ← Already filtered to guild
    herbivore_predators: &FxHashMap<String, Vec<String>>,
    insect_parasites: &FxHashMap<String, Vec<String>>,
    normalizer: &Normalizer,
) -> Result<M3Result>
```

**Update implementation**:
```rust
pub fn calculate_m3(
    organisms_lazy: &LazyFrame,
    fungi_lazy: &LazyFrame,
    herbivore_predators: &FxHashMap<String, Vec<String>>,
    insect_parasites: &FxHashMap<String, Vec<String>>,
    normalizer: &Normalizer,
) -> Result<M3Result> {
    // Materialize ONLY columns needed for biocontrol
    let guild_organisms = organisms_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("herbivores"),
            col("predators_hasHost"),
            col("predators_interactsWith"),
            col("predators_adjacentTo"),
        ])
        .collect()?;

    let guild_fungi = fungi_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("entomopathogenic_fungi"),
        ])
        .collect()?;

    // Rest of M3 logic unchanged
    // ... biocontrol mechanism detection ...
}
```

#### 4.4: Update M4, M5, M7 Similarly

**M4 (Disease Control)**:
```rust
pub fn calculate_m4(
    fungi_lazy: &LazyFrame,  // ← Already filtered
    pathogen_antagonists: &FxHashMap<String, Vec<String>>,
    normalizer: &Normalizer,
) -> Result<M4Result> {
    let guild_fungi = fungi_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("pathogen_fungi"),
            col("mycoparasite_fungi"),
        ])
        .collect()?;

    // ... M4 logic
}
```

**M5 (Beneficial Fungi)**:
```rust
pub fn calculate_m5(
    fungi_lazy: &LazyFrame,
    normalizer: &Normalizer,
) -> Result<M5Result> {
    let guild_fungi = fungi_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("amf_fungi"),
            col("emf_fungi"),
            col("endophytic_fungi"),
            col("saprotrophic_fungi"),
        ])
        .collect()?;

    // ... M5 logic
}
```

**M7 (Pollinator Support)**:
```rust
pub fn calculate_m7(
    organisms_lazy: &LazyFrame,
    normalizer: &Normalizer,
) -> Result<M7Result> {
    let guild_organisms = organisms_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("pollinators"),
            col("flower_visitors"),
        ])
        .collect()?;

    // ... M7 logic
}
```

#### 4.5: Update Scorer to Use Pre-filtered LazyFrames

**File**: `src/scorer.rs`

**Update score_guild method**:
```rust
pub fn score_guild(&self, plant_ids: &[String]) -> Result<GuildScore> {
    // Build filtered lazy frames ONCE
    let (guild_organisms_lazy, guild_fungi_lazy) =
        self.build_guild_lazy_frames(plant_ids);

    // Calculate metrics (each materializes only what it needs)
    let m1 = calculate_m1(
        &self.data.plants_lazy,
        plant_ids,
        &self.pd_calculator,
        &self.normalizer
    )?;

    let m2 = calculate_m2(
        &self.data.plants_lazy,
        plant_ids,
        &self.normalizer
    )?;

    let m3 = calculate_m3(
        &guild_organisms_lazy,  // ← Filtered lazy frame
        &guild_fungi_lazy,      // ← Filtered lazy frame
        &self.data.herbivore_predators,
        &self.data.insect_parasites,
        &self.normalizer
    )?;

    let m4 = calculate_m4(
        &guild_fungi_lazy,      // ← Reuse same filtered lazy frame
        &self.data.pathogen_antagonists,
        &self.normalizer
    )?;

    let m5 = calculate_m5(
        &guild_fungi_lazy,      // ← Reuse again
        &self.normalizer
    )?;

    let m6 = calculate_m6(
        &self.data.plants_lazy,
        plant_ids,
        &self.normalizer
    )?;

    let m7 = calculate_m7(
        &guild_organisms_lazy,  // ← Reuse filtered lazy frame
        &self.normalizer
    )?;

    // ... aggregate metrics
}
```

#### 4.6: Test Phase 4

```bash
cargo build --release --bin test_3_guilds
./target/release/test_3_guilds
```

**Verification**:
- [ ] M3, M4, M5, M7 scores match exactly
- [ ] All biocontrol/fungi/pollinator logic correct
- [ ] Significant memory reduction visible

---

### Phase 5: M6 Optimization (30 minutes)

**Goal**: Optimize structural diversity calculation

#### 5.1: Update calculate_m6

**File**: `src/metrics/m6_structural_diversity.rs`

**Current signature**:
```rust
pub fn calculate_m6(
    guild_plants: &DataFrame,
    normalizer: &Normalizer,
) -> Result<M6Result>
```

**Change to**:
```rust
pub fn calculate_m6(
    plants_lazy: &LazyFrame,
    plant_ids: &[String],
    normalizer: &Normalizer,
) -> Result<M6Result>
```

**Update implementation**:
```rust
pub fn calculate_m6(
    plants_lazy: &LazyFrame,
    plant_ids: &[String],
    normalizer: &Normalizer,
) -> Result<M6Result> {
    // Materialize only columns for structural diversity
    let guild_plants = plants_lazy
        .clone()
        .filter(col("wfo_id").is_in(lit(plant_ids)))
        .select(&[
            col("wfo_id"),
            col("height_m"),
            col("growth_form"),
            col("light_pref"),
        ])
        .collect()?;

    // Sort by height (CRITICAL for parity)
    let sorted = guild_plants
        .clone()
        .lazy()
        .sort(["height_m"], Default::default())
        .collect()?;

    // Rest of M6 logic unchanged
    // ... stratification analysis
}
```

#### 5.2: Test Phase 5

```bash
cargo build --release --bin test_3_guilds
./target/release/test_3_guilds
```

**Verification**:
- [ ] M6 scores match exactly
- [ ] Stratification logic correct

---

### Phase 6: Explanation Engine Optimization (1 hour)

**Goal**: Update explanation engine to work with LazyFrames

#### 6.1: Update score_guild_with_explanation_parallel

**File**: `src/scorer.rs`

**Current pattern**:
```rust
pub fn score_guild_with_explanation_parallel(&self, plant_ids: &[String])
    -> Result<(GuildScore, Vec<MetricFragment>, DataFrame)>
{
    // Filter guild plants once
    let guild_plants = /* filter from self.data.plants */;

    // Pass to parallel metrics
    let metric_results: Vec<_> = (0..7)
        .into_iter()  // Sequential for Cloud Run
        .map(|i| {
            match i {
                0 => {
                    let m1 = calculate_m1(&guild_plants, ...)?;
                    // ...
                }
            }
        })
        .collect();
}
```

**Update to**:
```rust
pub fn score_guild_with_explanation_parallel(&self, plant_ids: &[String])
    -> Result<(GuildScore, Vec<MetricFragment>, DataFrame)>
{
    // Build filtered lazy frames
    let (guild_organisms_lazy, guild_fungi_lazy) =
        self.build_guild_lazy_frames(plant_ids);

    // For explanation, materialize guild plants with names
    let guild_plants_for_explanation = self.data.plants_lazy
        .clone()
        .filter(col("wfo_id").is_in(lit(plant_ids)))
        .select(&[
            col("wfo_id"),
            col("wfo_scientific_name"),
            col("koppen_zone"),
        ])
        .collect()?;

    // Sequential metric calculation with lazy frames
    let metric_results: Vec<_> = (0..7)
        .into_iter()
        .map(|i| {
            match i {
                0 => {
                    let m1 = calculate_m1(
                        &self.data.plants_lazy,
                        plant_ids,
                        &self.pd_calculator,
                        &self.normalizer
                    )?;
                    let fragment = generate_m1_fragment(&m1, 100.0 - m1.normalized);
                    Ok((Box::new(m1), fragment))
                },
                1 => {
                    let m2 = calculate_m2(
                        &self.data.plants_lazy,
                        plant_ids,
                        &self.normalizer
                    )?;
                    let fragment = generate_m2_fragment(&m2, 100.0 - m2.normalized);
                    Ok((Box::new(m2), fragment))
                },
                2 => {
                    let m3 = calculate_m3(
                        &guild_organisms_lazy,
                        &guild_fungi_lazy,
                        &self.data.herbivore_predators,
                        &self.data.insect_parasites,
                        &self.normalizer
                    )?;
                    let fragment = generate_m3_fragment(&m3, m3.normalized);
                    Ok((Box::new(m3), fragment))
                },
                // ... M4-M7 similar
                _ => unreachable!()
            }
        })
        .collect::<Result<Vec<_>>>()?;

    // Rest of explanation generation unchanged
    // ...
}
```

#### 6.2: Test Phase 6

```bash
cargo build --release --bin test_explanations_3_guilds
./target/release/test_explanations_3_guilds
```

**Verification**:
- [ ] All explanations generate correctly
- [ ] Markdown/JSON/HTML output unchanged
- [ ] Scores match exactly

---

### Phase 7: Final Testing and Measurement (1 hour)

#### 7.1: Build Optimized Memory Test

**File**: `src/bin/test_memory_optimized.rs` (copy from baseline, same code)

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust

# Build optimized version
cargo build --release --bin test_memory_optimized

# Run with memory monitoring
/usr/bin/time -v ./target/release/test_memory_optimized 2>&1 | tee optimized_memory.log
```

#### 7.2: Compare Metrics

Update `OPTIMIZATION_METRICS.md`:

```markdown
## After Optimization

**Date**: ___

### Initialization
- Time: ___ ms (Target: < 500 ms)
- Peak RSS: ___ MB (Target: < 150 MB)
- Improvement: ___% faster, ___% less memory

### Guild Scoring (Forest Garden)
- Time: ___ ms (Target: < 4 ms)
- Peak RSS: ___ MB (Target: < 200 MB)
- Memory delta: ___ MB (Target: minimal growth)
- Improvement: ___% faster, ___% less memory

### Overall Improvements
- Cold start: ___× faster
- Memory footprint: ___% reduction
- Cloning eliminated: ___ → 0 full DataFrame clones
```

#### 7.3: Run Full Parity Test

```bash
# R test
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/test_r_explanation_3guilds.R

# Rust optimized test
./target/release/test_explanations_3_guilds

# Compare outputs
diff shipley_checks/reports/explanations/r_explanation_forest_garden.md \
     shipley_checks/reports/explanations/rust_explanation_forest_garden.md
```

**Verification**:
- [ ] All 3 guilds: R vs Rust scores match (< 0.0001 difference)
- [ ] All metrics individually correct
- [ ] Explanation content equivalent
- [ ] Performance improved
- [ ] Memory usage reduced

#### 7.4: Run Unit Tests

```bash
cargo test --release

# Expected: 25 passed, 2 ignored
```

---

### Phase 8: Documentation and Git Commit (30 minutes)

#### 8.1: Update Implementation Summary

**File**: `shipley_checks/docs/Stage_4_Rust_Implementation_Summary.md`

Add new section:

```markdown
## Memory Optimization (Phase 2)

**Date**: 2025-11-13
**Status**: ✅ COMPLETE

### Changes Applied

1. **LazyFrame Schema-Only Loading**
   - Plants: 73 MB → 50 KB (schema only)
   - Organisms: 4.7 MB → 30 KB (schema only)
   - Fungi: 2.8 MB → 20 KB (schema only)
   - Total initialization: 80 MB → 100 KB (800× reduction)

2. **Eliminated DataFrame Cloning**
   - Before: 6-9 full clones per guild (43 KB × 9 = 387 KB)
   - After: 0 clones, only column projections (~5-10 KB total)
   - Memory per guild: 95% reduction

3. **Column Projection Optimization**
   - M1: Loads 1 column (wfo_id) instead of 782
   - M2: Loads 7 columns (CSR + modulation) instead of 782
   - M3: Loads 5 columns from organisms, 1 from fungi
   - M4: Loads 2 columns from fungi
   - M5: Loads 4 columns from fungi
   - M6: Loads 4 columns (height, form, light)
   - M7: Loads 2 columns from organisms

### Performance Results

**Before optimization:**
- Cold start: 9.5s
- Guild scoring: 5.7ms
- Peak memory: ~500 MB

**After optimization:**
- Cold start: ___ ms (__×improvement)
- Guild scoring: ___ ms (__× improvement)
- Peak memory: ___ MB (__% reduction)

### Cloud Run Cost Impact

**Projected savings:**
- Instance size: 512 MB → 256 MB (50% reduction)
- Cold start penalty: Reduced by ___%
- Throughput per instance: Increased by ___%
- **Total cost reduction: ~60-70%**
```

#### 8.2: Git Commit

```bash
cd /home/olier/ellenberg

# Stage changes
git add shipley_checks/src/Stage_4/guild_scorer_rust/src/data.rs
git add shipley_checks/src/Stage_4/guild_scorer_rust/src/scorer.rs
git add shipley_checks/src/Stage_4/guild_scorer_rust/src/metrics/
git add shipley_checks/src/Stage_4/guild_scorer_rust/OPTIMIZATION_METRICS.md
git add shipley_checks/docs/Stage_4_Rust_Implementation_Summary.md
git add shipley_checks/docs/TEMP_Rust_Memory_Optimization_Plan.md

# Commit
git commit -m "Optimize Rust guild scorer: LazyFrame loading and zero-copy operations

- Convert data loading to LazyFrame schema-only scans (800× less memory)
- Eliminate DataFrame cloning in all metrics (95% memory reduction per guild)
- Implement column projection optimization (load only needed columns)
- Update M1-M7 to use LazyFrame references instead of owned DataFrames
- Maintain 100% parity with R implementation (verified on 3 test guilds)
- Target: 60-70% Cloud Run cost reduction via smaller instances"

# Push
git push origin main
```

---

## Testing Checklist

### After Each Phase

- [ ] `cargo build --release` succeeds with no warnings
- [ ] `cargo test --release` passes (25 passed, 2 ignored)
- [ ] `./target/release/test_3_guilds` shows parity maintained
- [ ] No performance regression (timing similar or better)

### Final Validation

- [ ] All 3 guilds score correctly (< 0.0001 difference from R)
- [ ] Memory usage significantly reduced
- [ ] Cold start time improved
- [ ] Explanation generation still works
- [ ] All unit tests pass
- [ ] Documentation updated
- [ ] Git commit created

---

## Rollback Plan

If any phase breaks parity:

1. **Identify breaking phase**:
   ```bash
   git log --oneline  # Find last working commit
   ```

2. **Revert specific changes**:
   ```bash
   git diff HEAD~1 src/metrics/m2_growth_compatibility.rs  # Review changes
   git checkout HEAD~1 -- src/metrics/m2_growth_compatibility.rs  # Revert file
   ```

3. **Test after revert**:
   ```bash
   cargo build --release --bin test_3_guilds
   ./target/release/test_3_guilds
   ```

4. **Debug issue**:
   - Check column names (LazyFrame select might have typos)
   - Verify filter expressions (col("wfo_id") vs col("wfo_scientific_name"))
   - Compare materialized data shapes (print schema)

---

## Expected Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 0: Preparation | 30 min | 30 min |
| Phase 1: Data Loading | 2 hours | 2.5 hours |
| Phase 2: M1 | 1 hour | 3.5 hours |
| Phase 3: M2 | 1 hour | 4.5 hours |
| Phase 4: M3/M4/M5/M7 | 2 hours | 6.5 hours |
| Phase 5: M6 | 30 min | 7 hours |
| Phase 6: Explanation | 1 hour | 8 hours |
| Phase 7: Testing | 1 hour | 9 hours |
| Phase 8: Documentation | 30 min | 9.5 hours |

**Total: ~9.5 hours (1-2 days)**

---

## Success Criteria

1. ✅ **Correctness**: 100% parity maintained (< 0.0001 difference)
2. ✅ **Memory**: 60-70% reduction in peak RSS
3. ✅ **Performance**: Cold start < 500ms (target: 19× faster)
4. ✅ **Maintainability**: Code remains readable, well-documented
5. ✅ **Testing**: All unit tests pass, integration tests pass
6. ✅ **Cloud Run Ready**: Can run in 256 MB instance (50% cost savings)
