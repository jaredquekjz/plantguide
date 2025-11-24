# Implementation Plan: Coverage-Based Metrics (M3, M4, M5, M7)

## Objective
Replace unbounded match-count formulas with bounded percentage-coverage formulas for M3, M4, M5, M7 to solve ceiling effect problem.

## Current vs Proposed Formulas

### M3 - Insect Control
**Current:**
```rust
biocontrol_raw = Σ(specific_matches × 1.0 + general_fungi × 0.2)
biocontrol_normalized = (biocontrol_raw / max_pairs) × 20.0
percentile = percentile_normalize(biocontrol_normalized, calibration)
```

**Proposed:**
```rust
plants_with_biocontrol = count(plant has ≥1 predator OR fungi match)
biocontrol_coverage_pct = (plants_with_biocontrol / n_plants) × 100.0
percentile = percentile_normalize(biocontrol_coverage_pct, calibration)
```

**Output range:** 0-100% (bounded)

### M4 - Disease Suppression
**Current:**
```rust
pathogen_raw = Σ(antagonist_matches × 1.0 + mycoparasites × 0.5 + fungivores × 0.2)
pathogen_normalized = (pathogen_raw / max_pairs) × 20.0
percentile = percentile_normalize(pathogen_normalized, calibration)
```

**Proposed:**
```rust
plants_with_disease_control = count(plant has ≥1 antagonist OR mycoparasite OR fungivore)
disease_coverage_pct = (plants_with_disease_control / n_plants) × 100.0
percentile = percentile_normalize(disease_coverage_pct, calibration)
```

**Output range:** 0-100% (bounded)

### M5 - Beneficial Fungi
**Current:**
```rust
fungi_raw = Σ(mycorrhizae count × weights)
fungi_normalized = (fungi_raw / n_plants) × some_multiplier
percentile = percentile_normalize(fungi_normalized, calibration)
```

**Proposed:**
```rust
plants_with_mycorrhizae = count(plant has ≥1 mycorrhizal association)
fungi_coverage_pct = (plants_with_mycorrhizae / n_plants) × 100.0
percentile = percentile_normalize(fungi_coverage_pct, calibration)
```

**Output range:** 0-100% (bounded)

### M7 - Pollinator Support
**Current:**
```rust
pollinator_raw = count(shared pollinator species)
pollinator_normalized = (pollinator_raw / some_factor) × multiplier
percentile = percentile_normalize(pollinator_normalized, calibration)
```

**Proposed:**
```rust
plants_with_pollinators = count(plant has ≥1 documented pollinator)
pollinator_coverage_pct = (plants_with_pollinators / n_plants) × 100.0
percentile = percentile_normalize(pollinator_coverage_pct, calibration)
```

**Output range:** 0-100% (bounded)

## Implementation Steps

### Phase 1: Code Changes (M3 Example - apply pattern to M4, M5, M7)

#### Step 1.1: Update M3Result struct
File: `src/metrics/m3_insect_control.rs`

```rust
pub struct M3Result {
    pub raw: f64,  // Change: Now stores coverage % (0-100)
    pub norm: f64, // Percentile (0-100)

    // Keep for explanation reporting:
    pub biocontrol_raw: f64,  // OLD metric (for comparison/reporting)
    pub plants_with_biocontrol: usize,  // NEW: Count of plants
    pub total_plants: usize,  // NEW: Guild size

    // Existing fields for detailed reporting:
    pub n_mechanisms: usize,
    pub predator_counts: FxHashMap<String, usize>,
    pub entomo_fungi_counts: FxHashMap<String, usize>,
    pub specific_predator_matches: usize,
    pub specific_fungi_matches: usize,
    pub matched_predator_pairs: Vec<(String, String)>,
    pub matched_fungi_pairs: Vec<(String, String)>,
}
```

#### Step 1.2: Update M3 calculation logic
File: `src/metrics/m3_insect_control.rs`, function `calculate_m3()`

Current structure:
```rust
// Loop through plant pairs
for i in 0..n_plants {
    for j in 0..n_plants {
        if i == j { continue; }
        // Count matches, accumulate biocontrol_raw
    }
}
biocontrol_normalized = (biocontrol_raw / max_pairs) × 20.0
```

New structure:
```rust
// Step 1: Track which plants have biocontrol (use HashSet)
let mut plants_with_biocontrol = FxHashSet::default();

// Step 2: Loop through plants (not pairs!)
for (i, plant_id) in plant_ids.iter().enumerate() {
    let has_predators = /* check if plant has predator matches */;
    let has_fungi = /* check if plant has fungi */;

    if has_predators || has_fungi {
        plants_with_biocontrol.insert(i);
    }
}

// Step 3: Calculate coverage percentage
let plants_with_biocontrol_count = plants_with_biocontrol.len();
let coverage_pct = (plants_with_biocontrol_count as f64 / n_plants as f64) × 100.0;

// Step 4: Percentile normalize (calibration now uses coverage %)
let m3_norm = percentile_normalize(coverage_pct, "p1", calibration, false)?;

Ok(M3Result {
    raw: coverage_pct,  // 0-100% coverage
    norm: m3_norm,      // percentile
    plants_with_biocontrol: plants_with_biocontrol_count,
    total_plants: n_plants,
    // ... keep other fields for reporting
})
```

#### Step 1.3: Update RawScores struct
File: `src/metrics/mod.rs`

```rust
pub struct RawScores {
    pub m1_faiths_pd: f64,
    pub m1_pest_risk: f64,
    pub m2_conflict_density: f64,
    pub m3_biocontrol_raw: f64,  // Change: Now coverage % (0-100)
    pub m4_pathogen_control_raw: f64,  // Change: Now coverage % (0-100)
    pub m5_beneficial_fungi_raw: f64,  // Change: Now coverage % (0-100)
    pub m6_stratification_raw: f64,
    pub m7_pollinator_raw: f64,  // Change: Now coverage % (0-100)
}
```

#### Step 1.4: Update calibration percentile calculation
File: `src/bin/calibrate_koppen_stratified.rs`

No changes needed! Calibration already uses `m3_result.raw`, which now contains coverage %.

### Phase 2: Repeat for M4, M5, M7

Apply same pattern:
1. Track plants with ≥1 match (HashSet)
2. Calculate coverage % = count / n_plants × 100
3. Update Result struct to store coverage %
4. Update RawScores mapping

Files to modify:
- `src/metrics/m4_disease_control.rs`
- `src/metrics/m5_beneficial_fungi.rs`
- `src/metrics/m7_pollinator_support.rs`

### Phase 3: Update Explanation Reporting

File: `src/explanation/formatters/markdown.rs`

Current M3 reporting:
```
Biocontrol: 100.0/100 (21.24 normalized units)
```

New M3 reporting:
```
Biocontrol: 98th percentile
  Coverage: 71% of plants (5/7) have documented pest-predator relationships
  Total matches: 44 specific predator pairs + 13 general fungi occurrences
  Average per contributing plant: 8.8 matches
```

Update format functions to:
1. Show percentile (from norm)
2. Show coverage % (from raw, which is now %)
3. Show absolute counts in details (from existing fields)

### Phase 4: Re-run Calibration

Command:
```bash
cd /home/olier/ellenberg
env RUST_MIN_STACK=134217728 \
  shipley_checks/src/Stage_4/guild_scorer_rust/target/release/calibrate_koppen_stratified
```

Expected calibration distributions:

M3 (% plants with biocontrol):
- p1-p50: 0-14% (0-1 plants)
- p90: 29% (2 plants)
- p99: 43-57% (3-4 plants)

M7 (% plants with pollinators):
- p1-p70: 0% (no pollinators)
- p90: 14-29% (1-2 plants)
- p99: 43% (3 plants)

Test guilds (predicted):
- Competitive Clash: 29-43% (2-3 plants) → ~90-95th percentile
- Entomopathogen: 71-86% (5-6 plants) → 99-100th percentile

Outcome: Better spread than before (not all 100%), but ceiling still possible for best guilds.

### Phase 5: Testing & Validation

#### Test 1: Unit test coverage calculation
```rust
#[test]
fn test_m3_coverage_calculation() {
    // Guild with 3/7 plants having biocontrol
    let result = calculate_m3(...);
    assert_eq!(result.plants_with_biocontrol, 3);
    assert_eq!(result.raw, 42.857); // 3/7 × 100
}
```

#### Test 2: Compare with 5 canonical guilds
```bash
cargo run --bin test_explanations_3_guilds
```

Expected changes:
- M3 scores change from 100/100/100/100/0 to ~90/95/98/100/0
- Overall scores shift (average includes new M3 values)

#### Test 3: Verify calibration distributions
```bash
python3 << 'EOF'
import json
cal = json.load(open('shipley_checks/stage4/phase5_output/normalization_params_7plant.json'))
p1 = cal['tier_3_humid_temperate']['p1']
print("M3 calibration (coverage %):")
for k, v in sorted(p1.items(), key=lambda x: int(x[0][1:])):
    print(f"  {k}: {v:.2f}%")
EOF
```

## Expected Outcomes

### Before (match counts):
```
M3 Calibration: 0.0 - 2.29 (normalized units)
Test guilds: 5.33 - 21.24 (all exceed p99 → 100%ile)
```

### After (coverage %):
```
M3 Calibration: 0% - 57% (discrete: 0, 14, 29, 43, 57%)
Test guilds: 29% - 86% (overlap with calibration!)
Expected percentiles: 85-100%ile (better discrimination)
```

### Benefits:
- Bounded output (0-100%)
- Interpretable ("71% of plants have biocontrol")
- Natural overlap between random/real guilds
- Better discrimination (not all 100%)
- Fair across guild sizes (already normalized as %)

### Remaining challenges:
- Best guilds may still hit 99-100%ile (acceptable - they're exceptional)
- Discrete values (7 plants = only 8 possible percentages)
- Loses intensity information (1 match = 10 matches per plant)

## Rollback Plan

If coverage % doesn't improve distributions:

**Option A:** Apply sqrt to coverage % before percentile conversion
```rust
coverage_pct = (count / n_plants) × 100.0
coverage_compressed = sqrt(coverage_pct)  // 0-10 range
percentile = percentile_normalize(coverage_compressed, calibration)
```

**Option B:** Accept ceiling, improve reporting
- Report "99+" instead of capping at 100
- Add qualitative tiers: "Excellent (95-100)", "Good (75-95)", etc.
- Emphasize raw counts in explanations

**Option C:** Revert to old formulas with binary interpretation
- Keep match counts
- Change messaging: "95-100% = Biocontrol present"

## Files Summary

To modify:
1. `src/metrics/m3_insect_control.rs` - Coverage calculation
2. `src/metrics/m4_disease_control.rs` - Coverage calculation
3. `src/metrics/m5_beneficial_fungi.rs` - Coverage calculation
4. `src/metrics/m7_pollinator_support.rs` - Coverage calculation
5. `src/metrics/mod.rs` - RawScores struct comments
6. `src/explanation/formatters/markdown.rs` - Reporting format

To rebuild:
- `cargo build --release` (main library)
- `cargo build --release --bin calibrate_koppen_stratified`
- `cargo build --bin test_explanations_3_guilds`

To run:
1. Calibration: 5 minutes
2. Tests: 30 seconds
3. Validation: 2 minutes

Total implementation time estimate: 2-3 hours
